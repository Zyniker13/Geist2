import Foundation

/// Reads a module archive: the fixed layout of decision 0005, the manifest's
/// required shape, the schema file's agreement with the manifest, and the
/// integrity digests over every other file.
///
/// Structural checks only. Meaning — references resolving, units valid,
/// recipe shapes — belongs to the layers above (the recipe validation in
/// `BarRecipes`), which receive the decoded payloads from here.
public enum ModuleReader {
    /// The fixed layout: the only entry names an archive may carry.
    static let requiredFiles: Set<String> = ["manifest.json", "schema"]
    static let optionalFiles: Set<String> = [
        "data/recipes.jsonl", "data/ingredients.jsonl",
        "data/bottles.jsonl", "data/taxonomy.json", "data/tags.json",
    ]
    /// Asset names: one level under `assets/`, letters, digits, dot, dash,
    /// underscore, at most 64 bytes.
    static let assetNamePattern = "^[A-Za-z0-9._-]{1,64}$"

    /// How reading fails, each its own defined error.
    public enum ModuleError: Error, Equatable, Sendable {
        /// The archive is not a valid module container.
        case badContainer(ZIPError)
        /// A required file is absent.
        case missingRequiredFile(String)
        /// An entry outside the fixed layout.
        case unknownEntry(String)
        /// The schema file is not the format version as plain text.
        case badSchemaFile
        /// The schema file and the manifest disagree about the format
        /// version, or the manifest declares a version this reader does
        /// not read.
        case schemaVersionMismatch
        /// The manifest fails its required shape, with the reason.
        case badManifest(ModuleManifest.ManifestError)
        /// A file's bytes do not match the digest the manifest recorded.
        case digestMismatch(String)
        /// A JSONL payload has a line that is not a complete JSON object.
        case badJSONL(file: String, line: Int)
        /// The manifest's contents counts disagree with the archive.
        case contentsMismatch(String)
    }

    /// What a read archive holds: the manifest plus decoded payloads.
    public struct Module: Sendable {
        public let manifest: ModuleManifest
        /// The schema file's text (the format version as an integer string).
        public let schemaText: String
        /// Recipe payload lines, each a parsed JSON object.
        public let recipePayloads: [CanonicalJSON.Value]
        /// Ingredient payload lines, each a parsed JSON object.
        public let ingredientPayloads: [CanonicalJSON.Value]
        /// Assets by their name under `assets/`.
        public let assets: [String: Data]

        public func asset(named name: String) -> Data? {
            assets[name]
        }

        /// The manifest's declared recipe count.
        public var recipesCount: Int { manifest.contents["recipes"] ?? 0 }
    }

    /// The archive's manifest alone: the cheap launch-path read. Bounds,
    /// path safety, and manifest decoding all apply; digest verification
    /// and payload parsing do not.
    public static func manifest(from data: Data) throws -> ModuleManifest {
        let zip: ZIPReader.Archive
        do {
            zip = try ZIPReader.read(data)
        } catch let error as ZIPError {
            throw ModuleError.badContainer(error)
        }
        guard let entry = zip.entry(named: "manifest.json") else {
            throw ModuleError.missingRequiredFile("manifest.json")
        }
        do {
            return try ModuleManifest(rawJSON: entry.data)
        } catch let error as ModuleManifest.ManifestError {
            throw ModuleError.badManifest(error)
        }
    }

    /// Read and structurally verify a module archive.
    public static func read(_ data: Data) throws -> Module {
        let zip: ZIPReader.Archive
        do {
            zip = try ZIPReader.read(data)
        } catch let error as ZIPError {
            throw ModuleError.badContainer(error)
        }
        var files: [String: Data] = [:]
        for entry in zip.entries {
            files[entry.name] = entry.data
        }
        for name in files.keys {
            try checkEntryAllowed(name)
        }
        for required in requiredFiles where files[required] == nil {
            throw ModuleError.missingRequiredFile(required)
        }

        // The schema file: the format version as plain text.
        let schemaText = String(decoding: files["schema"]!, as: UTF8.self)
        let schemaVersion = Int(schemaText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let schemaVersion else { throw ModuleError.badSchemaFile }

        // The manifest.
        let manifest: ModuleManifest
        do {
            manifest = try ModuleManifest(rawJSON: files["manifest.json"]!)
        } catch let error as ModuleManifest.ManifestError {
            throw ModuleError.badManifest(error)
        }
        guard schemaVersion == manifest.formatVersion else {
            throw ModuleError.schemaVersionMismatch
        }
        guard manifest.formatVersion == ModuleManifest.currentFormatVersion else {
            throw ModuleError.schemaVersionMismatch
        }

        // Integrity: every non-manifest file must match its recorded digest.
        for (name, data) in files where name != "manifest.json" {
            let recorded = manifest.integrity[name]
            guard recorded == Digests.sha256Hex(data) else {
                throw ModuleError.digestMismatch(name)
            }
        }

        // Payloads.
        let recipes = try decodeJSONL(files["data/recipes.jsonl"], file: "data/recipes.jsonl")
        let ingredients = try decodeJSONL(
            files["data/ingredients.jsonl"], file: "data/ingredients.jsonl")

        // Contents counts must agree with what the archive carries.
        for (key, count) in manifest.contents {
            let actual: Int
            switch key {
            case "recipes": actual = recipes.count
            case "ingredients": actual = ingredients.count
            default: actual = count  // other content kinds are checked by their loaders
            }
            guard actual == count else { throw ModuleError.contentsMismatch(key) }
        }

        var assets: [String: Data] = [:]
        for (name, data) in files where name.hasPrefix("assets/") {
            assets[String(name.dropFirst("assets/".count))] = data
        }
        return Module(
            manifest: manifest,
            schemaText: schemaText,
            recipePayloads: recipes,
            ingredientPayloads: ingredients,
            assets: assets
        )
    }

    // MARK: Layout

    static func checkEntryAllowed(_ name: String) throws {
        guard !requiredFiles.contains(name), !optionalFiles.contains(name) else { return }
        guard name.hasPrefix("assets/") else { throw ModuleError.unknownEntry(name) }
        let assetName = name.dropFirst("assets/".count)
        guard !assetName.contains("/"), assetName.count <= 64,
            assetName.allSatisfy({
                $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_"
            })
        else { throw ModuleError.unknownEntry(name) }
    }

    /// Decode a JSONL payload: UTF-8, LF-terminated lines, each one JSON
    /// object; a final line terminator is the line's end, not a new line.
    static func decodeJSONL(_ data: Data?, file: String) throws -> [CanonicalJSON.Value] {
        guard let data, !data.isEmpty else { return [] }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        var lines: [CanonicalJSON.Value] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
        {
            guard !line.isEmpty else { throw ModuleError.badJSONL(file: file, line: index + 1) }
            do {
                let value = try CanonicalJSON.parse(Data(line.utf8))
                guard case .object = value else {
                    throw CanonicalJSON.CanonicalJSONError.badByte(0)
                }
                lines.append(value)
            } catch {
                throw ModuleError.badJSONL(file: file, line: index + 1)
            }
        }
        return lines
    }
}
