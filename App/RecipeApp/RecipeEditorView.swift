import PhotosUI
import RecipeCore
import SwiftUI

/// The recipe editor (M4.3): structured ingredient rows, paste-lines
/// mode, sections, steps with timers, photos, and the recipe's facts.
/// Opens from the library's "+" and from an existing recipe's Edit
/// button; saves through the library, which stamps `modifiedAt`.
struct RecipeEditorView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss

    /// Nil opens a new recipe; otherwise the given recipe is edited.
    let recipe: RecipeDocument?

    @StateObject private var holder = EditorHolder()

    var body: some View {
        if let model = holder.model(for: recipe, library: library) {
            EditorForm(model: model)
        } else {
            // First pass: the holder adopts on the next tick.
            Color.clear.onAppear {
                holder.adopt(recipe: recipe, library: library)
            }
        }
    }
}

/// `@StateObject` needs an init-time value; the holder adopts the
/// recipe on the first render tick.
@MainActor
private final class EditorHolder: ObservableObject {
    private(set) var model: RecipeEditorModel?
    private var adoptedKey: String?

    func model(for recipe: RecipeDocument?, library: LibraryModel) -> RecipeEditorModel? {
        let key = recipe?.id ?? "new"
        if adoptedKey == key, let model { return model }
        return nil
    }

    func adopt(recipe: RecipeDocument?, library: LibraryModel) {
        let key = recipe?.id ?? "new"
        guard adoptedKey != key else { return }
        adoptedKey = key
        model = RecipeEditorModel(recipe: recipe, library: library)
        objectWillChange.send()
    }
}

private struct EditorForm: View {
    @ObservedObject var model: RecipeEditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingPasteSheet = false
    @State private var pasteText = ""
    @State private var pasteTarget = 0
    @State private var saving = false
    @State private var showProblems = false

    var body: some View {
        #if os(iOS)
            NavigationStack {
                formBody
            }
        #else
            formBody
        #endif
    }

    private var formBody: some View {
        Form {
            factsSection
            photosSection
            ingredientsSection
            stepsSection
            problemsSection
        }
        .navigationTitle(model.isNew ? "New Recipe" : "Edit Recipe")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!model.canSave || saving)
                .accessibilityIdentifier("editorSave")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("editorCancel")
            }
        }
        .sheet(isPresented: $showingPasteSheet) {
            PasteLinesSheet(
                text: $pasteText,
                onPaste: { text in
                    let added = model.pasteIngredientLines(text, into: pasteTarget)
                    showingPasteSheet = false
                    pasteText = ""
                    return added
                })
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await model.save()
            dismiss()
        } catch {
            model.problems = ["Saving failed: \(error.localizedDescription)"]
            showProblems = true
        }
    }

    // MARK: Facts

    private var factsSection: some View {
        Section("Recipe") {
            TextField("Title", text: $model.document.title)
                .accessibilityIdentifier("editorTitle")
            TextField(
                "Summary",
                text: Binding(
                    get: { model.document.summary },
                    set: { model.document.summary = $0 }),
                axis: .vertical)
            HStack {
                TextField("Yield amount", text: $model.yieldAmountText)
                    .frame(maxWidth: 80)
                    .accessibilityIdentifier("editorYieldAmount")
                TextField("Yield unit", text: $model.yieldUnit)
                    .accessibilityIdentifier("editorYieldUnit")
            }
            TextField(
                "Tags (comma separated)",
                text: Binding(
                    get: { model.document.tags.joined(separator: ", ") },
                    set: { text in
                        model.document.tags =
                            text
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }))
        }
    }

    // MARK: Photos

    @State private var photoPickerItem: PhotosPickerItem?

    private var photosSection: some View {
        Section("Photos") {
            if !model.document.photoHashes.isEmpty {
                PhotoHashStrip(
                    hashes: model.document.photoHashes.filter {
                        !model.removedPhotoHashes.contains($0)
                    },
                    onRemove: { model.removePhoto(hash: $0) })
            }
            ForEach(Array(model.pendingPhotoData.enumerated()), id: \.offset) { index, _ in
                HStack {
                    Image(systemName: "photo")
                    Text("New photo \(index + 1)")
                }
            }
            PhotosPicker(
                selection: $photoPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Add photo", systemImage: "plus.circle")
            }
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        model.addPhoto(data)
                    }
                    photoPickerItem = nil
                }
            }
        }
    }

    // MARK: Ingredients

    private var ingredientsSection: some View {
        Section {
            ForEach(Array(model.ingredientSections.enumerated()), id: \.element.id) {
                sectionIndex,
                section in
                if !section.name.isEmpty || model.ingredientSections.count > 1 {
                    TextField("Section name", text: $model.ingredientSections[sectionIndex].name)
                        .font(.subheadline.bold())
                }
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { rowIndex, row in
                    IngredientRowEditor(row: $model.ingredientSections[sectionIndex].rows[rowIndex])
                }
                .onDelete { offsets in
                    for offset in offsets.sorted(by: >) {
                        model.removeIngredientRow(at: offset, in: sectionIndex)
                    }
                }
                Button {
                    model.addIngredientRow(in: sectionIndex)
                } label: {
                    Label("Add ingredient", systemImage: "plus.circle")
                }
                Button {
                    pasteTarget = sectionIndex
                    showingPasteSheet = true
                } label: {
                    Label("Paste lines…", systemImage: "doc.on.clipboard")
                }
            }
            Button {
                model.addIngredientSection()
            } label: {
                Label("Add section", systemImage: "folder.badge.plus")
            }
        }
    }

    // MARK: Steps

    private var stepsSection: some View {
        Section("Directions") {
            ForEach(Array(model.stepSections.enumerated()), id: \.element.id) {
                sectionIndex,
                section in
                if !section.name.isEmpty || model.stepSections.count > 1 {
                    TextField("Section name", text: $model.stepSections[sectionIndex].name)
                        .font(.subheadline.bold())
                }
                ForEach(Array(section.steps.enumerated()), id: \.element.id) { stepIndex, step in
                    StepRowEditor(step: $model.stepSections[sectionIndex].steps[stepIndex])
                }
                .onDelete { offsets in
                    for offset in offsets.sorted(by: >) {
                        model.removeStep(at: offset, in: sectionIndex)
                    }
                }
                Button {
                    model.addStep(in: sectionIndex)
                } label: {
                    Label("Add step", systemImage: "plus.circle")
                }
            }
            Button {
                model.addStepSection()
            } label: {
                Label("Add section", systemImage: "folder.badge.plus")
            }
        }
    }

    // MARK: Problems

    private var problemsSection: some View {
        Group {
            if !model.problems.isEmpty {
                Section("Problems") {
                    ForEach(model.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

/// One ingredient row: amount, unit, item, preparation, note, flags.
/// At accessibility Dynamic Type sizes the fixed column widths would
/// truncate the ingredient name, so the rows stack vertically instead.
private struct IngredientRowEditor: View {
    @Binding var row: EditableIngredientRow
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Ingredient", text: $row.item)
                    HStack(spacing: 6) {
                        TextField("Amount", text: $row.amount)
                        TextField("Unit", text: $row.unit)
                    }
                    TextField("Preparation", text: $row.preparation)
                    TextField("Note", text: $row.note)
                    Toggle("Optional", isOn: $row.optional)
                    Toggle("To taste", isOn: $row.toTaste)
                }
            } else {
                HStack(spacing: 6) {
                    TextField("Amount", text: $row.amount)
                        .frame(maxWidth: 70)
                    TextField("Unit", text: $row.unit)
                        .frame(maxWidth: 90)
                    TextField("Ingredient", text: $row.item)
                }
                HStack(spacing: 6) {
                    TextField("Preparation", text: $row.preparation)
                    TextField("Note", text: $row.note)
                        .frame(maxWidth: 120)
                }
                HStack {
                    Toggle("Optional", isOn: $row.optional)
                        .frame(maxWidth: 130)
                    Toggle("To taste", isOn: $row.toTaste)
                        .frame(maxWidth: 130)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

/// One step: text plus timers detected in it and hand-added ones.
private struct StepRowEditor: View {
    @Binding var step: EditableStepRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Step", text: $step.text, axis: .vertical)
                .lineLimit(1...4)
            if !step.detectedTimers.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(step.detectedTimers.enumerated()), id: \.offset) { _, timer in
                        Label(timer.display, systemImage: "timer")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    Text("found in text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                ForEach(Array(step.manualTimers.enumerated()), id: \.offset) { index, _ in
                    TextField("Min", text: $step.manualTimers[index])
                        .frame(maxWidth: 60)
                }
                Button {
                    step.manualTimers.append("")
                } label: {
                    Label("Timer", systemImage: "plus.circle")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

/// The paste-lines sheet: type or paste raw ingredient lines, they
/// parse into rows like an import would.
private struct PasteLinesSheet: View {
    @Binding var text: String
    let onPaste: (String) -> Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .accessibilityIdentifier("pasteLinesEditor")
                Text(
                    "One ingredient per line. A line ending in a colon (\"For the marinade:\") starts a section."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Paste ingredient lines")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Paste") {
                        _ = onPaste(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pasteLinesConfirm")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The stored photos with remove buttons.
private struct PhotoHashStrip: View {
    let hashes: [String]
    let onRemove: (String) -> Void
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hashes, id: \.self) { hash in
                    PhotoThumb(hash: hash, onRemove: { onRemove(hash) })
                }
            }
        }
    }
}

private struct PhotoThumb: View {
    let hash: String
    let onRemove: () -> Void
    @EnvironmentObject private var library: LibraryModel
    @State private var image: Image?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .task(id: hash) {
            image = Self.editorImage(from: library.photos.data(for: hash))
        }
    }

    static func editorImage(from data: Data?) -> Image? {
        guard let data, let platformImage = PlatformImage(data: data) else { return nil }
        return Image(platformImage: platformImage)
    }
}
