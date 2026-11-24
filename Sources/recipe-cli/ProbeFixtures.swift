import ArgumentParser
import Foundation
import RecipeCore
import RecipeImport

/// Probe every fixture page and print a one-line summary per file.
/// Used while tuning the fixture corpus; also a handy debugging tool.
struct ProbeFixturesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe-fixtures",
        abstract: "Extract every fixture and print what came out.")

    @Option(help: "Directory holding the fixtures.")
    var dir: String = "Tests/RecipeImportTests/Fixtures"

    private static let names = [
        "f01-jsonld-full", "f02-jsonld-howtosections", "f03-jsonld-step-objects",
        "f04-jsonld-graph", "f05-jsonld-durations", "f06-jsonld-yield-cookies",
        "f07-jsonld-nutrition", "f08-jsonld-author-org", "f09-jsonld-itemlist-falls-back",
        "f10-jsonld-escapes", "f11-microdata-full", "f12-microdata-ingredient-stubs",
        "f13-microdata-nested-duration", "f14-microdata-howtosections",
        "f15-microdata-minimal", "f16-microdata-images", "f17-heuristic-lists",
        "f18-heuristic-paragraphs", "f19-heuristic-meta-line", "f20-heuristic-divs",
        "f21-heuristic-no-yield", "f22-not-recipe", "f23-broken-jsonld-falls-back",
        "f24-empty-page", "f25-yield-number-only", "f26-name-from-title",
        "f27-ingredient-entities", "f28-category-cuisine-keywords", "f29-step-names",
        "f30-two-recipes", "f31-source-url", "f32-malformed-duration",
        "f33-microdata-author-date", "f34-heuristic-servings-phrase",
        "f35-step-durations", "f36-json-script", "f37-heuristic-french-headers",
        "f38-yield-range", "f39-heuristic-pipe-meta", "f40-nested-graph",
        "f41-empty-jsonld-recipe", "f42-whitespace-values",
        "f43-category-cuisine-heuristic", "f44-upper-name", "f45-yield-verbose",
        "f46-fraction-chars", "f47-long-description", "f48-video-object",
        "f49-aggregate-rating", "f50-zero-ingredients", "f51-yield-double-hint",
        "f52-notes-field", "f53-url-with-query", "f54-script-type-filtering",
        "f55-partial-nutrition", "f56-microdata-yield-range",
        "f57-heuristic-numbered-divs", "f58-ingredients-only", "f59-author-string",
        "f60-faq-with-recipe", "f61-microdata-article", "f62-instructions-string",
        "f63-heuristic-yield-label", "f64-single-ingredient-string",
        "f65-keywords-array", "f66-microdata-duplicate-names",
        "f67-microdata-case-insensitive", "f68-heuristic-duplicates",
        "f69-notes-and-tips", "f70-yield-serving-noun",
    ]

    func run() throws {
        for n in Self.names {
            let html = try String(
                contentsOfFile: "\(dir)/\(n).html", encoding: .utf8)
            if let r = RecipeExtractor.extract(
                fromHTML: html, now: 1_800_000_000, id: n)
            {
                let ing = r.document.ingredientSections
                    .map { "\($0.name.isEmpty ? "-":$0.name):\(String($0.lines.count))" }
                    .joined(separator: ",")
                let steps = r.document.stepSections
                    .map { "\($0.name.isEmpty ? "-":$0.name):\(String($0.steps.count))" }
                    .joined(separator: ",")
                let source =
                    switch r.source {
                    case .jsonLd: "jsonld"
                    case .microdata: "microdata"
                    case .heuristic: "heuristic"
                    default: String(describing: r.source)
                    }
                print(
                    "\(n)|\(source)|\(r.document.title)|y=\(r.document.yieldAmount?.description ?? "nil") u=\(r.document.yieldUnit)|ing \(ing)|steps \(steps)|prep=\(r.document.prepTime?.display ?? "-") cook=\(r.document.cookTime?.display ?? "-") total=\(r.document.totalTime?.display ?? "-")|tags=\(r.document.tags.joined(separator: ";"))|cat=\(r.document.categories.joined(separator: ";"))|cui=\(r.document.cuisine ?? "-")|attr=\(r.document.attribution ?? "-")|url=\(r.document.sourceURL ?? "-")|notes=\(r.document.notes.isEmpty ? "-":String(r.document.notes.prefix(30)))"
                )
            } else {
                print("\(n)|NIL")
            }
        }
    }
}
