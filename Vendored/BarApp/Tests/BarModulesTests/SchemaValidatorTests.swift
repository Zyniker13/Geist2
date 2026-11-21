import BarModules
import Foundation
import Testing

/// The schema validator, driven against the schemas the repository ships.
/// The three format schemas live in `docs/modules/schema/` so third parties
/// can read them; the tests load them from there so a schema that drifts
/// from the validator (or the other way) fails here first.
@Suite
struct SchemaValidatorTests {
    /// The directory holding the shipped schemas (…/docs/modules/schema).
    static var schemaDirectory: String {
        // Tests run from a package scratch dir several levels deep; walk up
        // to the package root and into docs.
        var url = URL(fileURLWithPath: #filePath)
        // Tests/<target>/<file>.swift: the root is three levels up, whatever
        // the checkout directory is called.
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("docs/modules/schema").path
    }

    static func schema(named name: String) throws -> CanonicalJSON.Value {
        let url = URL(fileURLWithPath: schemaDirectory).appendingPathComponent(name)
        return try CanonicalJSON.parse(try Data(contentsOf: url))
    }

    // MARK: manifest schema

    @Test func manifestSchemaAcceptsTheDocumentedShape() throws {
        let schema = try Self.schema(named: "module-manifest-v1.schema.json")
        let manifest = try CanonicalJSON.parse(
            Data(
                """
                {"formatVersion":1,"id":"com.example.cocktails","version":"1.0.0","title":"T",
                "description":"D","languages":["en"],"authors":["alice"],"license":"MIT",
                "attribution":"A","minTaxonomyVersion":9,"contents":{"recipes":2},
                "integrity":{"data/recipes.jsonl":"abc"},"unknownField":true}
                """.replacingOccurrences(of: "\n", with: "").utf8))
        #expect(SchemaValidator.validate(manifest, against: schema).isEmpty)
    }

    @Test func manifestSchemaRejectsWrongTypesAndMissingFields() throws {
        let schema = try Self.schema(named: "module-manifest-v1.schema.json")
        let missing = try CanonicalJSON.parse(
            Data(
                #"{"formatVersion":1,"id":"com.example.cocktails"}"#.utf8))
        let issues = SchemaValidator.validate(missing, against: schema)
        #expect(issues.contains { $0.path.contains("title") })

        let badVersion = try CanonicalJSON.parse(
            Data(
                #"{"formatVersion":"1","id":"com.example.cocktails","version":"1.0.0","title":"T","description":"D","languages":["en"],"authors":["alice"],"license":"MIT","attribution":"A","minTaxonomyVersion":9,"contents":{},"integrity":{}}"#
                    .utf8))
        #expect(!SchemaValidator.validate(badVersion, against: schema).isEmpty)

        let wrongFormat = try CanonicalJSON.parse(
            Data(
                #"{"formatVersion":2,"id":"com.example.cocktails","version":"1.0.0","title":"T","description":"D","languages":["en"],"authors":["alice"],"license":"MIT","attribution":"A","minTaxonomyVersion":9,"contents":{},"integrity":{}}"#
                    .utf8))
        #expect(!SchemaValidator.validate(wrongFormat, against: schema).isEmpty)
    }

    @Test func manifestSchemaPinsTheDeclaredPatterns() throws {
        let schema = try Self.schema(named: "module-manifest-v1.schema.json")
        func issues(_ json: String) throws -> [SchemaValidator.Issue] {
            SchemaValidator.validate(try CanonicalJSON.parse(Data(json.utf8)), against: schema)
        }
        // Module ids are reverse-domain with at least two labels.
        #expect(
            !(try issues(
                #"{"formatVersion":1,"id":"cocktails","version":"1.0.0","title":"T","description":"D","languages":["en"],"authors":["alice"],"license":"MIT","attribution":"A","minTaxonomyVersion":9,"contents":{},"integrity":{}}"#
            ).isEmpty))
        // Versions are a semver core.
        #expect(
            !(try issues(
                #"{"formatVersion":1,"id":"com.example.cocktails","version":"1.0","title":"T","description":"D","languages":["en"],"authors":["alice"],"license":"MIT","attribution":"A","minTaxonomyVersion":9,"contents":{},"integrity":{}}"#
            ).isEmpty))
        // A signature is exactly 64 bytes of base64.
        #expect(
            !(try issues(
                #"{"formatVersion":1,"id":"com.example.cocktails","version":"1.0.0","title":"T","description":"D","languages":["en"],"authors":["alice"],"license":"MIT","attribution":"A","minTaxonomyVersion":9,"contents":{},"integrity":{},"signature":{"keyId":"k","signature":"AAAA"}}"#
            ).isEmpty))
    }

    // MARK: recipe schema

    @Test func recipeSchemaAcceptsTheDocumentedShape() throws {
        let schema = try Self.schema(named: "recipe-v1.schema.json")
        let recipe = try CanonicalJSON.parse(
            Data(
                ("{\"id\":\"lib-daiquiri\",\"name\":\"Daiquiri\",\"ingredients\":"
                    + "[{\"taxonomyId\":\"spirit.rum.white\",\"amount\":\"2\",\"unit\":\"oz\"}],"
                    + "\"instructions\":\"Shake.\",\"provenance\":{\"source\":\"own-words\"}}").utf8
            ))
        #expect(SchemaValidator.validate(recipe, against: schema).isEmpty)
    }

    @Test func recipeSchemaRejectsBadShapes() throws {
        let schema = try Self.schema(named: "recipe-v1.schema.json")
        func issues(_ json: String) throws -> [SchemaValidator.Issue] {
            SchemaValidator.validate(try CanonicalJSON.parse(Data(json.utf8)), against: schema)
        }
        // Provenance is required.
        #expect(
            !(try issues(
                #"{"id":"x","name":"X","ingredients":[],"instructions":"Stir."}"#
            ).isEmpty))
        // An ingredient line names the node or a label, not neither.
        #expect(
            !(try issues(
                #"{"id":"x","name":"X","ingredients":[{}],"instructions":"Stir.","provenance":{"source":"own-words"}}"#
            ).isEmpty))
        // The method vocabulary is closed.
        #expect(
            !(try issues(
                #"{"id":"x","name":"X","method":"ferment","ingredients":[],"instructions":"Stir.","provenance":{"source":"own-words"}}"#
            ).isEmpty))
        // Instructions are non-empty.
        #expect(
            !(try issues(
                #"{"id":"x","name":"X","ingredients":[],"instructions":"","provenance":{"source":"own-words"}}"#
            ).isEmpty))
    }

    // MARK: module ingredient schema

    @Test func ingredientSchemaAcceptsAndRejects() throws {
        let schema = try Self.schema(named: "module-ingredient-v1.schema.json")
        let good = try CanonicalJSON.parse(
            Data(
                """
                {"id":"liqueur.orange.curacao-mod","parentId":"liqueur.orange","kind":"ingredient",
                "name":"Curaçao","aliases":["curacao"],"detailFields":["origin"]}
                """.replacingOccurrences(of: "\n", with: "").utf8))
        #expect(SchemaValidator.validate(good, against: schema).isEmpty)

        // A module ingredient always names its parent.
        let orphan = try CanonicalJSON.parse(
            Data(
                #"{"id":"a.b","kind":"ingredient","name":"X"}"#.utf8))
        #expect(!SchemaValidator.validate(orphan, against: schema).isEmpty)
        // The kind vocabulary is closed.
        let badKind = try CanonicalJSON.parse(
            Data(
                #"{"id":"a.b","parentId":"a","kind":"spirit","name":"X"}"#.utf8))
        #expect(!SchemaValidator.validate(badKind, against: schema).isEmpty)
    }

    // MARK: validator mechanics

    @Test func validatorReportsPathsForNestedFailures() throws {
        let schema = try CanonicalJSON.parse(
            Data(
                #"{"type":"object","properties":{"a":{"type":"array","items":{"type":"integer","minimum":1}}}}"#
                    .utf8
            ))
        let value = try CanonicalJSON.parse(Data(#"{"a":[1,0]}"#.utf8))
        let issues = SchemaValidator.validate(value, against: schema)
        #expect(issues.count == 1)
        #expect(issues.first?.path == "$.a[1]")
    }

    @Test func shippedSchemasMatchThePublishedCopiesByteForByte() throws {
        // The copies the package ships and the copies under docs/modules/
        // schema must not drift: compare the raw files.
        for name in [
            "module-manifest-v1.schema.json",
            "recipe-v1.schema.json",
            "module-ingredient-v1.schema.json",
        ] {
            let shipped = try SchemaValidator.schemaResourceData(named: name)
            let published = try Data(
                contentsOf: URL(fileURLWithPath: Self.schemaDirectory)
                    .appendingPathComponent(name))
            #expect(shipped == published, "\(name) drifted")
        }
    }

    @Test func validatorHandlesEveryShippedSchema() throws {
        for name in [
            "module-manifest-v1.schema.json",
            "recipe-v1.schema.json",
            "module-ingredient-v1.schema.json",
        ] {
            let schema = try Self.schema(named: name)
            // Each schema is itself an object with a type and an $id.
            guard case .object(let tree) = schema else {
                Issue.record("\(name) is not an object")
                continue
            }
            guard case .string = tree["$id"] else {
                Issue.record("\(name) has no $id")
                continue
            }
            guard case .string = tree["type"] else {
                Issue.record("\(name) has no type")
                continue
            }
        }
    }
}
