import Foundation
import Testing

@testable import BarModules

/// The module reader: manifest, fixed layout, the schema file, SHA-256
/// integrity digests, and JSONL payloads — structural checks only; the
/// meaning checks (references, units) live with the recipe validation.
@Suite
struct ModuleReaderTests {
    // MARK: Builders

    /// A minimal, correct manifest as JSON text.
    private static let minimalManifest = """
        {
          "formatVersion": 1,
          "id": "com.example.cocktails",
          "version": "1.0.0",
          "title": "Example module",
          "description": "A tiny module for tests.",
          "languages": ["en"],
          "authors": ["alice"],
          "license": "MIT",
          "attribution": "© example",
          "minTaxonomyVersion": 9,
          "contents": {"recipes": 2},
          "integrity": {}
        }
        """

    private static func sha256Hex(_ data: Data) -> String {
        Digests.sha256Hex(data)
    }

    /// Build an archive whose integrity digests cover what it carries.
    private static func module(
        manifest: String? = nil,
        schema: Data = Data("1".utf8),
        recipesJSONL: Data? = Data(
            ("{\"id\":\"ex-one\",\"name\":\"One\",\"aliases\":[],\"instructions\":\"Stir.\",\"tags\":[],\"provenance\":{\"sources\":[]}}\n"
                + "{\"id\":\"ex-two\",\"name\":\"Two\",\"aliases\":[],\"instructions\":\"Shake.\",\"tags\":[],\"provenance\":{\"sources\":[]}}\n")
                .utf8
        ),
        ingredientsJSONL: Data? = nil,
        assets: [(String, Data)] = []
    ) throws -> Data {
        var files: [(String, Data)] = [
            ("schema", schema)
        ]
        if let recipesJSONL { files.append(("data/recipes.jsonl", recipesJSONL)) }
        if let ingredientsJSONL { files.append(("data/ingredients.jsonl", ingredientsJSONL)) }
        files.append(contentsOf: assets)

        // The manifest is generated last, with digests for everything else.
        var digests: [String] = []
        for (name, data) in files {
            digests.append("    \"\(name)\": \"\(sha256Hex(data))\"")
        }
        let integrity = digests.joined(separator: ",\n")
        let contentsRecipes =
            recipesJSONL.map { jsonl in
                jsonl.split(separator: 0x0A).count
            } ?? 0
        let contentsIngredients =
            ingredientsJSONL.map { jsonl in
                jsonl.split(separator: 0x0A).count
            } ?? 0
        var contents = ""
        if contentsRecipes > 0 { contents += "\"recipes\": \(contentsRecipes)" }
        if contentsIngredients > 0 {
            contents += contents.isEmpty ? "" : ", "
            contents += "\"ingredients\": \(contentsIngredients)"
        }
        let manifestJSON = (manifest ?? minimalManifest)
            .replacingOccurrences(
                of: "\"contents\": {\"recipes\": 2}", with: "\"contents\": {\(contents)}"
            )
            .replacingOccurrences(
                of: "\"integrity\": {}", with: "\"integrity\": {\n\(integrity)\n  }")
        let all = [("manifest.json", Data(manifestJSON.utf8))] + files
        return ZIPTests.multiEntryArchive(names: all.map(\.0), contents: all.map(\.1))
    }

    // MARK: The happy path

    @Test func readsAMinimalModule() throws {
        let archive = try ModuleReader.read(try Self.module())
        #expect(archive.manifest.formatVersion == 1)
        #expect(archive.manifest.id == "com.example.cocktails")
        #expect(archive.manifest.title == "Example module")
        #expect(archive.recipesCount == 2)
        #expect(archive.recipePayloads.count == 2)
        #expect(archive.recipePayloads[0]["id"] == .string("ex-one"))
    }

    @Test func readsAssets() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let archive = try ModuleReader.read(
            try Self.module(assets: [("assets/daiquiri.png", png)])
        )
        #expect(archive.asset(named: "daiquiri.png") == png)
    }

    // MARK: Structural rejections, each its own defined error

    private func reject(_ data: Data, _ error: ModuleReader.ModuleError) {
        #expect(throws: error) {
            _ = try ModuleReader.read(data)
        }
    }

    @Test func rejectsMissingManifestAndSchema() throws {
        var missingManifest = try Self.module()
        // Drop the manifest entry: rebuild without it.
        let files: [(String, Data)] = [("schema", Data("1".utf8))]
        missingManifest = ZIPTests.multiEntryArchive(
            names: files.map(\.0), contents: files.map(\.1))
        reject(missingManifest, .missingRequiredFile("manifest.json"))

        var missingSchema = try Self.module()
        // The schema entry is required: rebuild the archive without it.
        let recipes = Data("{\"id\":\"x\"}\n".utf8)
        let noSchema: [(String, Data)] = [("manifest.json", Data(Self.minimalManifest.utf8))]
        missingSchema = ZIPTests.multiEntryArchive(
            names: noSchema.map(\.0), contents: noSchema.map(\.1))
        reject(missingSchema, .missingRequiredFile("schema"))
        _ = recipes
    }

    @Test func rejectsUnknownEntriesAndBadAssetNames() throws {
        let stray = try Self.module(assets: [("notes/readme.txt", Data())])
        reject(stray, .unknownEntry("notes/readme.txt"))
        let badName = try Self.module(assets: [("assets/has space.png", Data())])
        reject(badName, .unknownEntry("assets/has space.png"))
        let tooDeep = try Self.module(assets: [("assets/a/b.png", Data())])
        reject(tooDeep, .unknownEntry("assets/a/b.png"))
    }

    @Test func rejectsSchemaFileMismatches() throws {
        // The schema file must hold the format version as plain text.
        reject(try Self.module(schema: Data("2".utf8)), .schemaVersionMismatch)
        reject(try Self.module(schema: Data("one".utf8)), .badSchemaFile)
        // The manifest's formatVersion must agree with the schema file.
        let lying = Self.minimalManifest.replacingOccurrences(
            of: "\"formatVersion\": 1", with: "\"formatVersion\": 2")
        reject(try Self.module(manifest: lying), .schemaVersionMismatch)
    }

    @Test func rejectsManifestThatFailsItsShape() throws {
        // Not JSON at all.
        reject(try Self.module(manifest: "{"), .badManifest(.badJSON))
        // The module id is not reverse-domain.
        let badID = Self.minimalManifest.replacingOccurrences(
            of: "\"com.example.cocktails\"", with: "\"not-an-id\"")
        reject(try Self.module(manifest: badID), .badManifest(.badModuleID))
        // formatVersion must be the integer 1.
        let floatVersion = Self.minimalManifest.replacingOccurrences(
            of: "\"formatVersion\": 1", with: "\"formatVersion\": 1.0")
        reject(try Self.module(manifest: floatVersion), .badManifest(.badFormatVersion))
        // A required field is missing.
        let noTitle = Self.minimalManifest.replacingOccurrences(
            of: "\"title\": \"Example module\",", with: "")
        reject(try Self.module(manifest: noTitle), .badManifest(.missingField("title")))
        // Authors must be a non-empty array of strings.
        let noAuthors = Self.minimalManifest.replacingOccurrences(
            of: "\"authors\": [\"alice\"],", with: "")
        reject(try Self.module(manifest: noAuthors), .badManifest(.missingField("authors")))
    }

    @Test func rejectsDigestMismatches() throws {
        // The archive carries a payload whose digest the manifest did not
        // record: the ZIP container stays intact, the integrity check
        // catches the difference.
        let realPayload = Data("{\"id\":\"real\"}\n".utf8)
        let otherPayload = Data("{\"id\":\"other\"}\n".utf8)
        let files: [(String, Data)] = [("schema", Data("1".utf8))]
        let manifestJSON = Self.minimalManifest
            .replacingOccurrences(
                of: "\"contents\": {\"recipes\": 2}", with: "\"contents\": {\"recipes\": 1}"
            )
            .replacingOccurrences(
                of: "\"integrity\": {}",
                with:
                    "\"integrity\": {\"data/recipes.jsonl\": \"\(Self.sha256Hex(otherPayload))\", \"schema\": \"\(Self.sha256Hex(files[0].1))\"}"
            )
        let all: [(String, Data)] = [
            ("manifest.json", Data(manifestJSON.utf8)),
            ("schema", files[0].1),
            ("data/recipes.jsonl", realPayload),
        ]
        reject(
            ZIPTests.multiEntryArchive(names: all.map(\.0), contents: all.map(\.1)),
            .digestMismatch("data/recipes.jsonl")
        )
    }

    @Test func rejectsContentsCountsThatLie() throws {
        // The manifest claims two recipes; the payload has one, and the
        // digests are correct: the contents count is the lie.
        let files: [(String, Data)] = [
            ("schema", Data("1".utf8)),
            ("data/recipes.jsonl", Data("{\"id\":\"x\"}\n".utf8)),
        ]
        let withDigests = Self.minimalManifest.replacingOccurrences(
            of: "\"integrity\": {}",
            with:
                "\"integrity\": {\"data/recipes.jsonl\": \"\(Self.sha256Hex(files[1].1))\", \"schema\": \"\(Self.sha256Hex(files[0].1))\"}"
        )
        let data = ZIPTests.multiEntryArchive(
            names: ["manifest.json"] + files.map(\.0),
            contents: [Data(withDigests.utf8)] + files.map(\.1)
        )
        reject(data, .contentsMismatch("recipes"))
    }

    @Test func rejectsBadJSONLAndDuplicateRecipeIDsAreMeaningChecks() throws {
        // A truncated line is a structural error with the line number.
        reject(
            try Self.module(recipesJSONL: Data("{\"id\":\"x\"\n{\"id\":\"y\"}\n".utf8)),
            .badJSONL(file: "data/recipes.jsonl", line: 1)
        )
    }
}
