import Foundation
import RecipeCore
import RecipeImport
import SwiftUI

/// Editable mirror of a `RecipeDocument` for the M4.3 editor.
///
/// Editing keeps the document's shape: each row composes its text and
/// re-parses it through `IngredientParser` — the same parser import
/// uses — so a hand-typed line behaves exactly like an imported one and
/// the display pipeline sees only lines it understands. Saves go
/// through `LibraryStore.write`, which stamps `modifiedAt` and emits
/// the sync change.
@MainActor
final class RecipeEditorModel: ObservableObject {
    /// The document being edited: an existing recipe or a fresh one.
    @Published var document: RecipeDocument

    /// Ingredient sections as editable rows.
    @Published var ingredientSections: [EditableIngredientSection]

    /// Step sections as editable rows.
    @Published var stepSections: [EditableStepSection]

    /// Photos: pending bytes not yet stored, and stored hashes the user
    /// removed since the editor opened.
    @Published var pendingPhotoData: [Data] = []
    @Published var removedPhotoHashes: Set<String> = []

    /// The yield the editor edits: amount as text ("" = none stated)
    /// and the unit word.
    @Published var yieldAmountText: String
    @Published var yieldUnit: String

    /// Non-fatal problems from the last compose or save attempt.
    @Published var problems: [String] = []

    /// True when the editor opened without a recipe.
    let isNew: Bool

    private let library: LibraryModel

    init(recipe: RecipeDocument?, library: LibraryModel) {
        self.library = library
        self.isNew = recipe == nil
        let base: RecipeDocument
        if let recipe {
            base = recipe
            yieldAmountText = recipe.yieldAmount.map { RecipeMath.kitchenFraction(of: $0) } ?? ""
            yieldUnit = recipe.yieldUnit.isEmpty ? "servings" : recipe.yieldUnit
        } else {
            base = RecipeDocument(
                id: UUID().uuidString,
                createdAt: Int64(Date().timeIntervalSince1970),
                modifiedAt: 0)
            yieldAmountText = ""
            yieldUnit = "servings"
        }
        document = base
        ingredientSections = Self.sections(from: base)
        stepSections = Self.stepSections(from: base)
    }

    // MARK: Building the editor state

    private static func sections(from document: RecipeDocument) -> [EditableIngredientSection] {
        var sections = document.ingredientSections.map { section in
            EditableIngredientSection(
                name: section.name, rows: section.lines.map { EditableIngredientRow(existing: $0) })
        }
        // A fresh or empty document has a section with no lines: give
        // the editor one starter row to type into.
        if sections.isEmpty {
            sections = [EditableIngredientSection(name: "", rows: [EditableIngredientRow()])]
        } else if sections.allSatisfy({ $0.rows.isEmpty }) {
            sections[0].rows = [EditableIngredientRow()]
        }
        return sections
    }

    private static func stepSections(from document: RecipeDocument) -> [EditableStepSection] {
        var sections = document.stepSections.map { section in
            EditableStepSection(
                name: section.name, steps: section.steps.map { EditableStepRow(existing: $0) })
        }
        if sections.isEmpty {
            sections = [EditableStepSection(name: "", steps: [EditableStepRow()])]
        } else if sections.allSatisfy({ $0.steps.isEmpty }) {
            sections[0].steps = [EditableStepRow()]
        }
        return sections
    }

    // MARK: Ingredient rows and sections

    func addIngredientRow(in section: Int) {
        guard ingredientSections.indices.contains(section) else { return }
        ingredientSections[section].rows.append(EditableIngredientRow())
    }

    func addIngredientSection() {
        ingredientSections.append(
            EditableIngredientSection(name: "", rows: [EditableIngredientRow()]))
    }

    func removeIngredientRow(at index: Int, in section: Int) {
        guard ingredientSections.indices.contains(section),
            ingredientSections[section].rows.indices.contains(index)
        else { return }
        ingredientSections[section].rows.remove(at: index)
        if ingredientSections[section].rows.isEmpty {
            removeIngredientSection(at: section)
        }
    }

    func removeIngredientSection(at index: Int) {
        guard ingredientSections.indices.contains(index) else { return }
        ingredientSections.remove(at: index)
        if ingredientSections.isEmpty {
            ingredientSections = [
                EditableIngredientSection(name: "", rows: [EditableIngredientRow()])
            ]
        }
    }

    // MARK: Paste-lines mode

    /// Parses pasted lines into rows: section headers open new
    /// sections, everything else becomes a row in the current one.
    /// Returns the number of lines that produced a row.
    @discardableResult
    func pasteIngredientLines(_ text: String, into section: Int) -> Int {
        var added = 0
        var target = ingredientSections.indices.contains(section) ? section : 0
        // The target section's starter row (a fresh editor starts with
        // one blank row) is replaced by the first pasted row.
        var consumedStarter = false
        if ingredientSections.indices.contains(target),
            ingredientSections[target].rows.count == 1,
            ingredientSections[target].rows[0].isEmptyRow
        {
            ingredientSections[target].rows.remove(at: 0)
            consumedStarter = true
        }
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if IngredientParser.isSectionHeader(line) {
                let name = line.hasSuffix(":") ? String(line.dropLast()) : line
                ingredientSections.append(
                    EditableIngredientSection(name: name, rows: []))
                target = ingredientSections.count - 1
                consumedStarter = false
                continue
            }
            ingredientSections[target].rows.append(
                EditableIngredientRow(parsedFrom: line))
            added += 1
        }
        // Sections left empty by the paste (the target when the paste
        // held only headers, a header with no lines under it) keep a
        // starter row unless they were empty before the paste.
        if ingredientSections.indices.contains(target), ingredientSections[target].rows.isEmpty {
            ingredientSections[target].rows.append(EditableIngredientRow())
        } else if consumedStarter, added == 0 {
            ingredientSections[target].rows.append(EditableIngredientRow())
        }
        return added
    }

    // MARK: Steps

    func addStep(in section: Int) {
        guard stepSections.indices.contains(section) else { return }
        stepSections[section].steps.append(EditableStepRow())
    }

    func addStepSection() {
        stepSections.append(EditableStepSection(name: "", steps: [EditableStepRow()]))
    }

    func removeStep(at index: Int, in section: Int) {
        guard stepSections.indices.contains(section),
            stepSections[section].steps.indices.contains(index)
        else { return }
        stepSections[section].steps.remove(at: index)
        if stepSections[section].steps.isEmpty {
            removeStepSection(at: section)
        }
    }

    func removeStepSection(at index: Int) {
        guard stepSections.indices.contains(index) else { return }
        stepSections.remove(at: index)
        if stepSections.isEmpty {
            stepSections = [EditableStepSection(name: "", steps: [EditableStepRow()])]
        }
    }

    // MARK: Photos

    func addPhoto(_ data: Data) {
        guard !data.isEmpty else { return }
        pendingPhotoData.append(data)
    }

    func removePhoto(hash: String) {
        removedPhotoHashes.insert(hash)
    }

    func removePendingPhoto(at index: Int) {
        guard pendingPhotoData.indices.contains(index) else { return }
        pendingPhotoData.remove(at: index)
    }

    // MARK: Saving

    /// Whether Save may run: the title carries the recipe's identity in
    /// the list.
    var canSave: Bool {
        !document.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Composes the edited rows into the document and writes it.
    func save() async throws {
        guard canSave else { return }
        problems = []

        document.yieldAmount = Self.yieldAmount(from: yieldAmountText)
        document.yieldUnit =
            yieldUnit.trimmingCharacters(in: .whitespaces).isEmpty
            ? "servings" : yieldUnit.trimmingCharacters(in: .whitespaces)

        var ingredientOutput: [IngredientSection] = []
        for (sectionIndex, section) in ingredientSections.enumerated() {
            var lines: [IngredientLine] = []
            for (rowIndex, row) in section.rows.enumerated() {
                let text = row.text
                let line = IngredientParser.parse(text)
                if line.item.isEmpty && line.quantity == nil {
                    problems.append(
                        "Ingredient \(rowIndex + 1) in section \(sectionIndex + 1) could not be read."
                    )
                }
                var composed = line
                composed.originalText = text
                lines.append(composed)
            }
            if !lines.isEmpty {
                ingredientOutput.append(IngredientSection(name: section.name, lines: lines))
            }
        }
        document.ingredientSections =
            ingredientOutput.isEmpty
            ? [IngredientSection(name: "", lines: [])] : ingredientOutput

        var stepOutput: [StepSection] = []
        for section in stepSections {
            var steps: [Step] = []
            for row in section.steps {
                let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                var timers = RecipeAssembler.timedSteps(from: text)
                for minutesText in row.manualTimers {
                    if let minutes = Int(minutesText), minutes > 0 {
                        timers.append(Duration.minutes(minutes))
                    }
                }
                steps.append(Step(text: text, timers: timers))
            }
            if !steps.isEmpty {
                stepOutput.append(StepSection(name: section.name, steps: steps))
            }
        }
        document.stepSections =
            stepOutput.isEmpty
            ? [StepSection(name: "", steps: [])] : stepOutput

        // Photos: store pending bytes, apply removals.
        var hashes = document.photoHashes.filter { !removedPhotoHashes.contains($0) }
        for data in pendingPhotoData {
            if let hash = try? library.photos.store(data) {
                hashes.append(hash)
            }
        }
        pendingPhotoData = []
        removedPhotoHashes = []
        document.photoHashes = hashes

        try await library.store.write(document)
        await library.refresh()
    }

    /// Parses the yield amount field: kitchen fractions ("1 1/2") and
    /// plain decimals. Nil when the field is empty or unreadable.
    static func yieldAmount(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Try the fraction form first: Decimal(string:) parses "1 1/2"
        // as 1, dropping the fraction.
        let parts = trimmed.split(separator: " ")
        if parts.count == 2, let whole = Decimal(string: String(parts[0])),
            let fraction = fractionPart(String(parts[1]))
        {
            return whole + fraction
        }
        if parts.count == 1, let fraction = fractionPart(trimmed) {
            return fraction
        }
        return Decimal(string: trimmed)
    }

    private static func fractionPart(_ text: String) -> Decimal? {
        let parts = text.split(separator: "/")
        guard parts.count == 2,
            let top = Decimal(string: String(parts[0])),
            let bottom = Decimal(string: String(parts[1])),
            bottom != 0
        else { return nil }
        return top / bottom
    }
}

/// One ingredient section being edited.
@MainActor
struct EditableIngredientSection: Identifiable {
    let id = UUID()
    var name: String
    var rows: [EditableIngredientRow]

    init(name: String, rows: [EditableIngredientRow]) {
        self.name = name
        self.rows = rows
    }
}

/// One ingredient row being edited: the fields the M2 parser keeps,
/// shown as separate editors. The row's text composes from the fields
/// and re-parses on save, so display and scaling see a normal line.
@MainActor
struct EditableIngredientRow: Identifiable {
    let id = UUID()
    var amount: String
    var unit: String
    var item: String
    var preparation: String
    var note: String
    var optional: Bool
    var toTaste: Bool

    init(
        amount: String = "", unit: String = "", item: String = "",
        preparation: String = "", note: String = "",
        optional: Bool = false, toTaste: Bool = false
    ) {
        self.amount = amount
        self.unit = unit
        self.item = item
        self.preparation = preparation
        self.note = note
        self.optional = optional
        self.toTaste = toTaste
    }

    /// A row parsed from one pasted line: the line's fields fill the
    /// editors, so the paste is inspectable and editable.
    init(parsedFrom text: String) {
        let line = IngredientParser.parse(text)
        amount = line.quantity.map { RecipeMath.kitchenFraction(of: $0.amount) } ?? ""
        if let high = line.quantityHigh {
            amount =
                amount.isEmpty
                ? RecipeMath.kitchenFraction(of: high.amount)
                : "\(amount) – \(RecipeMath.kitchenFraction(of: high.amount))"
        }
        if let unitID = line.unitID, !unitID.isEmpty {
            unit = RecipeDisplay.unitLabel(unitID, amount: line.quantity?.amount ?? 1)
        } else {
            unit = ""
        }
        item = line.item
        preparation = line.preparation ?? ""
        note = line.note ?? ""
        optional = line.optional
        toTaste = line.toTaste
    }

    init(existing line: IngredientLine) {
        self.init(parsedFrom: line.originalText.isEmpty ? Self.compose(line) : line.originalText)
        // A line whose original text was lost (a composed scaled line)
        // still fills the fields from its structure.
        if item.isEmpty { item = line.item }
        if amount.isEmpty, let quantity = line.quantity {
            amount = RecipeMath.kitchenFraction(of: quantity.amount)
        }
        if unit.isEmpty, let unitID = line.unitID, !unitID.isEmpty {
            unit = RecipeDisplay.unitLabel(unitID, amount: line.quantity?.amount ?? 1)
        }
        if preparation.isEmpty { preparation = line.preparation ?? "" }
        if note.isEmpty { note = line.note ?? "" }
        optional = optional || line.optional
        toTaste = toTaste || line.toTaste
    }

    /// Rebuilds a line's text from its structure when no original text
    /// survives.
    private static func compose(_ line: IngredientLine) -> String {
        var parts: [String] = []
        if let quantity = line.quantity {
            parts.append(RecipeMath.kitchenFraction(of: quantity.amount))
        }
        if let unitID = line.unitID, !unitID.isEmpty {
            parts.append(RecipeDisplay.unitLabel(unitID, amount: line.quantity?.amount ?? 1))
        }
        parts.append(line.item)
        if let preparation = line.preparation, !preparation.isEmpty {
            parts.append(preparation)
        }
        if let note = line.note, !note.isEmpty {
            parts.append("(\(note))")
        }
        if line.optional { parts.append("(optional)") }
        if line.toTaste { parts.append("to taste") }
        return parts.joined(separator: " ")
    }

    /// True when the row is the untouched starter row: nothing typed.
    var isEmptyRow: Bool {
        amount.isEmpty && unit.isEmpty && item.isEmpty && preparation.isEmpty
            && note.isEmpty && !optional && !toTaste
    }

    /// The row's text as the parser sees it on save. A range in the
    /// amount field composes with "to" so the parser reads the range.
    var text: String {
        var amountText = amount.trimmingCharacters(in: .whitespaces)
        if amountText.contains("–") || amountText.contains("-") {
            amountText =
                amountText
                .replacingOccurrences(of: "–", with: " to ")
                .replacingOccurrences(of: "-", with: " to ")
        }
        var parts: [String] = []
        if !amountText.isEmpty { parts.append(amountText) }
        let unitText = unit.trimmingCharacters(in: .whitespaces)
        if !unitText.isEmpty { parts.append(unitText) }
        parts.append(item)
        let preparationText = preparation.trimmingCharacters(in: .whitespaces)
        if !preparationText.isEmpty { parts.append(", \(preparationText)") }
        let noteText = note.trimmingCharacters(in: .whitespaces)
        if !noteText.isEmpty { parts.append("(\(noteText))") }
        if optional { parts.append("(optional)") }
        if toTaste { parts.append("to taste") }
        return parts.joined(separator: " ")
    }
}

/// One step being edited: the text, plus timers the parser finds in it
/// and any the user adds by hand.
@MainActor
struct EditableStepRow: Identifiable {
    let id = UUID()
    var text: String
    /// Timers the text names; recomposed on save.
    var detectedTimers: [Duration]
    /// Hand-added timer lengths in minutes, as typed.
    var manualTimers: [String]

    init(text: String = "", detectedTimers: [Duration] = [], manualTimers: [String] = []) {
        self.text = text
        self.detectedTimers = detectedTimers
        self.manualTimers = manualTimers
    }

    init(existing step: Step) {
        text = step.text
        detectedTimers = step.timers
        manualTimers = []
    }
}

/// One step section being edited.
@MainActor
struct EditableStepSection: Identifiable {
    let id = UUID()
    var name: String
    var steps: [EditableStepRow]

    init(name: String, steps: [EditableStepRow]) {
        self.name = name
        self.steps = steps
    }
}
