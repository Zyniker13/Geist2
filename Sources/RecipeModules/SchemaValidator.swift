import Foundation

/// A JSON Schema (2020-12) validator for the subset the module format's
/// schemas use: `type`, `properties` with `required`, `items`, `minItems`,
/// `minLength`, `minimum`, `maximum`, `enum`, `const`, `pattern`, `anyOf`,
/// and `oneOf`. The schemas are self-contained — they never reference each
/// other — so this validator resolves no `$ref` and fetches nothing: it is
/// data over data, applied to canonical JSON value trees in memory.
///
/// Keywords this subset does not implement are ignored, the way a reader
/// tolerates unknown fields; the shipped schemas are pinned by tests so a
/// keyword outside the subset would show up as a schema the tests fail.
public enum SchemaValidator {
    /// One failure, located by JSON pointer-ish path (`$.a[0].b`).
    public struct Issue: Equatable, Sendable {
        public let path: String
        public let message: String

        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }
    }

    /// The raw bytes of one shipped schema resource.
    public static func schemaResourceData(named name: String) throws -> Data {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: nil, subdirectory: "Schemas")
        else { throw SchemaError.missingShippedSchema(name) }
        return try Data(contentsOf: url)
    }

    /// The format's shipped schemas, loaded from the package's resources:
    /// the manifest schema, the recipe-line schema, and the module
    /// ingredient-line schema. Validation needs no network and no external
    /// files; the published copies under `docs/modules/schema` are pinned
    /// byte-identical by a package test.
    public static func formatSchemas() throws -> (
        manifest: CanonicalJSON.Value, recipe: CanonicalJSON.Value,
        ingredient: CanonicalJSON.Value
    ) {
        func load(_ name: String) throws -> CanonicalJSON.Value {
            guard
                let url = Bundle.module.url(
                    forResource: name, withExtension: "json",
                    subdirectory: "Schemas")
            else { throw SchemaError.missingShippedSchema(name) }
            return try CanonicalJSON.parse(try Data(contentsOf: url))
        }
        return try (
            manifest: load("module-manifest-v1.schema"),
            recipe: load("recipe-v1.schema"),
            ingredient: load("module-ingredient-v1.schema")
        )
    }

    public enum SchemaError: Error, Equatable, Sendable {
        case missingShippedSchema(String)
    }

    /// Validate `value` against `schema`, returning every failure. An empty
    /// result means the value conforms.
    public static func validate(
        _ value: CanonicalJSON.Value, against schema: CanonicalJSON.Value
    ) -> [Issue] {
        var issues: [Issue] = []
        apply(value, schema: schema, path: "$", into: &issues)
        return issues
    }

    /// Apply every keyword the schema carries at this position.
    static func apply(
        _ value: CanonicalJSON.Value, schema: CanonicalJSON.Value, path: String,
        into issues: inout [Issue]
    ) {
        guard case .object(let keywords) = schema else { return }

        for typeValue in typeNames(keywords["type"]) where !matchesType(value, typeValue) {
            issues.append(Issue(path: path, message: "expected type \(typeValue)"))
        }
        if let allowed = literalSet(keywords["const"]), !allowed.contains(value) {
            issues.append(Issue(path: path, message: "must equal the const"))
        }
        if let allowed = literalSet(keywords["enum"]), !allowed.contains(value) {
            issues.append(Issue(path: path, message: "not one of the enum values"))
        }
        if case .array(let branches) = keywords["anyOf"],
            !branches.contains(where: { applyIsEmpty(value, schema: $0) })
        {
            issues.append(Issue(path: path, message: "no anyOf branch matched"))
        }
        if case .array(let branches) = keywords["oneOf"] {
            let passing = branches.filter { applyIsEmpty(value, schema: $0) }
            if passing.count != 1 {
                issues.append(
                    Issue(path: path, message: "\(passing.count) oneOf branches matched"))
            }
        }

        if case .object(let tree) = value {
            for key in requiredKeys(keywords["required"]) where tree[key] == nil {
                issues.append(
                    Issue(path: "\(path).\(key)", message: "missing required field"))
            }
            if case .object(let properties) = keywords["properties"] {
                for (key, propertySchema) in properties where tree[key] != nil {
                    apply(tree[key]!, schema: propertySchema, path: "\(path).\(key)", into: &issues)
                }
            }
        }
        if case .array(let items) = value {
            if case .object(let itemSchema) = keywords["items"] {
                for (index, item) in items.enumerated() {
                    apply(
                        item, schema: .object(itemSchema), path: "\(path)[\(index)]",
                        into: &issues)
                }
            }
            if case .int(let minItems) = keywords["minItems"], items.count < Int(minItems) {
                issues.append(Issue(path: path, message: "fewer than \(minItems) items"))
            }
        }
        if case .string(let text) = value {
            if case .int(let minLength) = keywords["minLength"],
                text.count < Int(minLength)
            {
                issues.append(Issue(path: path, message: "shorter than \(minLength)"))
            }
            if let pattern = patternValue(keywords["pattern"]),
                !matches(text, pattern)
            {
                issues.append(Issue(path: path, message: "does not match \(pattern.pattern)"))
            }
        }
        if value.isNumber {
            if case .int(let minimum) = keywords["minimum"], value.doubleValue < Double(minimum) {
                issues.append(Issue(path: path, message: "below the minimum"))
            }
            if case .int(let maximum) = keywords["maximum"], value.doubleValue > Double(maximum) {
                issues.append(Issue(path: path, message: "above the maximum"))
            }
        }
    }

    static func applyIsEmpty(_ value: CanonicalJSON.Value, schema: CanonicalJSON.Value) -> Bool {
        var issues: [Issue] = []
        apply(value, schema: schema, path: "$", into: &issues)
        return issues.isEmpty
    }

    /// The type names a `type` keyword declares (one or several).
    static func typeNames(_ value: CanonicalJSON.Value?) -> [String] {
        switch value {
        case .string(let name): return [name]
        case .array(let members):
            return members.compactMap {
                if case .string(let name) = $0 { return name } else { return nil }
            }
        default: return []
        }
    }

    static func matchesType(_ value: CanonicalJSON.Value, _ name: String) -> Bool {
        switch (value, name) {
        case (.null, "null"), (.bool, "boolean"), (.string, "string"),
            (.int, "integer"), (.int, "number"), (.double, "number"),
            (.array, "array"), (.object, "object"):
            return true
        default:
            return false
        }
    }

    /// The literal values a `const` or `enum` keyword allows.
    static func literalSet(_ value: CanonicalJSON.Value?) -> [CanonicalJSON.Value]? {
        switch value {
        case .array(let members): return members
        case .some: return [value!]
        case nil: return nil
        }
    }

    static func requiredKeys(_ value: CanonicalJSON.Value?) -> [String] {
        guard case .array(let members) = value else { return [] }
        return members.compactMap {
            if case .string(let key) = $0 { return key } else { return nil }
        }
    }

    static func patternValue(_ value: CanonicalJSON.Value?) -> NSRegularExpression? {
        guard case .string(let pattern) = value else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }

    static func matches(_ text: String, _ pattern: NSRegularExpression) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.firstMatch(in: text, range: range) != nil
    }
}

extension CanonicalJSON.Value {
    /// Whether the value is a number of either kind.
    var isNumber: Bool {
        switch self {
        case .int, .double: return true
        default: return false
        }
    }

    /// The value as a double, for numeric comparisons across kinds.
    var doubleValue: Double {
        switch self {
        case .int(let int): return Double(int)
        case .double(let double): return double
        default: return 0
        }
    }
}
