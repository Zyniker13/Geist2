import ArgumentParser
import Foundation
import RecipeCore

@main
struct RecipeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recipe-cli",
        abstract: "Import, parse, scale and validate recipes from the command line.",
        subcommands: [ScaleCommand.self, ParseCommand.self, ProbeFixturesCommand.self],
        defaultSubcommand: ScaleCommand.self)
}

extension RecipeCLI {
    struct ScaleCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "scale",
            abstract: "Scale a recipe's ingredient amounts by a factor.")

        @Argument(help: "The scaling factor (0.5, 2, 3 ...).")
        var factor: Double

        @Option(name: .shortAndLong, help: "A recipe JSON file to scale; omit for the demo recipe.")
        var file: String?

        func run() throws {
            guard let factor = Decimal(string: "\(factor)") else {
                throw ValidationError("not a decimal: \(factor)")
            }
            let recipe = try Self.loadRecipe(file)
            try Self.printScaled(recipe, by: factor)
        }

        /// The recipe scaled with `factor`, printed as the CLI shows it.
        static func printScaled(_ recipe: RecipeDocument, by factor: Decimal) throws {
            let catalog = UnitCatalog()
            let sections = try RecipeMath.scaledSections(
                recipe.ingredientSections, by: factor, catalog: catalog)
            if !recipe.title.isEmpty {
                print("\(recipe.title) — \(factor)x")
                if let yield = recipe.yieldAmount {
                    let scaledYield = yield * factor
                    print(
                        "Yield: \(RecipeMath.kitchenFraction(of: scaledYield)) "
                            + recipe.yieldUnit)
                }
                print()
            }
            for section in sections {
                if !section.name.isEmpty {
                    print(section.name + ":")
                }
                for line in section.lines {
                    print("  " + render(line))
                }
                if !section.name.isEmpty { print() }
            }
            for stepSection in recipe.stepSections {
                if !stepSection.name.isEmpty {
                    print(stepSection.name + ":")
                }
                for step in stepSection.steps {
                    let text = try RecipeMath.stepText(
                        step.text, lines: recipe.ingredientSections.flatMap(\.lines),
                        by: factor, catalog: catalog)
                    print("  " + text)
                }
                if !stepSection.name.isEmpty { print() }
            }
        }

        /// One ingredient line as the CLI prints it.
        static func render(_ line: IngredientLine) -> String {
            var parts: [String] = []
            if let quantity = line.quantity {
                parts.append(RecipeMath.kitchenFraction(of: quantity.amount))
            }
            if let high = line.quantityHigh {
                parts.append("-")
                parts.append(RecipeMath.kitchenFraction(of: high.amount))
            }
            if let unit = line.unitID {
                parts.append(unit)
            }
            parts.append(line.item)
            if let prep = line.preparation {
                parts.append(", " + prep)
            }
            if let note = line.note {
                parts.append(" (\(note))")
            }
            if line.toTaste {
                parts.append(", to taste")
            }
            if line.optional {
                parts.append(" (optional)")
            }
            return parts.joined(separator: " ")
                .replacingOccurrences(of: " ,", with: ",")
                .replacingOccurrences(of: "  ", with: " ")
        }

        /// A recipe from a JSON file, or the built-in demo recipe the
        /// Done-when line names (0.5x, 2x, 3x).
        static func loadRecipe(_ path: String?) throws -> RecipeDocument {
            if let path {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try JSONDecoder().decode(RecipeDocument.self, from: data)
            }
            return DemoRecipe.creamyTomatoSoup
        }
    }

    struct ParseCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "parse",
            abstract: "Parse ingredient lines from stdin or a file, one per line.")

        @Option(
            name: .shortAndLong,
            help: "A text file with one ingredient line per line; omit for stdin.")
        var file: String?

        func run() throws {
            let text: String
            if let file {
                text = try String(contentsOfFile: file, encoding: .utf8)
            } else {
                text = String(
                    decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            for line in text.split(separator: "\n") where !line.isEmpty {
                let parsed = IngredientParser.parse(String(line))
                print(Self.describe(parsed))
            }
        }

        static func describe(_ line: IngredientLine) -> String {
            var parts: [String] = []
            if let quantity = line.quantity { parts.append("q=\(quantity.amount)") }
            if let high = line.quantityHigh { parts.append("high=\(high.amount)") }
            if let unit = line.unitID { parts.append("u=\(unit)") }
            parts.append("item=\(line.item)")
            if let prep = line.preparation { parts.append("prep=\(prep)") }
            if let note = line.note { parts.append("note=\(note)") }
            if line.optional { parts.append("optional") }
            if line.toTaste { parts.append("to-taste") }
            return parts.joined(separator: " ")
        }
    }
}

/// The demo recipe `recipe-cli scale` shows at 0.5x, 2x and 3x.
enum DemoRecipe {
    static let creamyTomatoSoup: RecipeDocument = {
        var recipe = RecipeDocument(
            id: "demo-soup", title: "Creamy Tomato Soup", createdAt: 0, modifiedAt: 0)
        recipe.yieldAmount = 4
        recipe.yieldUnit = "servings"
        recipe.ingredientSections = [
            IngredientSection(
                name: "",
                lines: [
                    IngredientParser.parse("2 tbsp olive oil"),
                    IngredientParser.parse("1 medium yellow onion, chopped"),
                    IngredientParser.parse("3 cloves garlic, minced"),
                    IngredientParser.parse("28 oz crushed tomatoes"),
                    IngredientParser.parse("2 cups chicken broth"),
                    IngredientParser.parse("1/2 cup heavy cream"),
                    IngredientParser.parse("1 tsp sugar"),
                    IngredientParser.parse("salt to taste"),
                    IngredientParser.parse("basil leaves, torn (optional)"),
                ])
        ]
        recipe.stepSections = [
            StepSection(
                name: "",
                steps: [
                    Step(text: "Heat 2 tbsp olive oil in a pot over medium heat."),
                    Step(text: "Soften the onion, 5 minutes. Add the garlic, 1 minute."),
                    Step(text: "Stir in the crushed tomatoes and the broth; simmer 20 minutes."),
                    Step(
                        text:
                            "Blend smooth, then stir in the cream. Season with the sugar and salt to taste."
                    ),
                ])
        ]
        return recipe
    }()
}
