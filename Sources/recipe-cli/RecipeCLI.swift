import ArgumentParser
import Foundation
import RecipeCore

@main
struct RecipeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recipe-cli",
        abstract: "Import, parse, scale and validate recipes from the command line.",
        subcommands: [ScaleCommand.self],
        defaultSubcommand: ScaleCommand.self)
}

extension RecipeCLI {
    struct ScaleCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "scale",
            abstract: "Scale a recipe's ingredient amounts by a factor.")

        @Argument(help: "The scaling factor (0.5, 2, 3 ...).")
        var factor: Double

        func run() throws {
            guard let factor = Decimal(string: "\(factor)") else {
                throw ValidationError("not a decimal: \(factor)")
            }
            print("recipe-cli scale \(factor): full parsing lands in M2")
        }
    }
}
