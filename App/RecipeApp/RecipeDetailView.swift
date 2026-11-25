import RecipeCore
import SwiftUI

/// Loads a recipe by ID and shows it: the split view's detail pane and
/// the iPhone stack destination both come through here.
struct RecipeDetailLoader: View {
    @EnvironmentObject private var library: LibraryModel
    let recipeID: String

    var body: some View {
        if let recipe = library.recipes.first(where: { $0.id == recipeID }) {
            RecipeDetailView(recipe: recipe)
        } else {
            ContentUnavailableView("Recipe not found", systemImage: "questionmark.folder")
        }
    }
}

/// The recipe detail screen (M4.2): photos, the yield stepper that
/// scales live, the unit toggle, check-off ingredients, the step list
/// with scaled amounts, notes, rating, and source attribution.
///
/// The stored document is never mutated for display: scale and unit
/// choices live in the view model and flow through `RecipeDisplay`.
struct RecipeDetailView: View {
    @EnvironmentObject private var library: LibraryModel
    @StateObject private var viewModelHolder = ViewHolder()
    let recipe: RecipeDocument

    var body: some View {
        if let viewModel = viewModelHolder.viewModel(for: recipe, library: library) {
            RecipeDetailContent(viewModel: viewModel)
        } else {
            // First pass: the holder adopts the recipe on the next tick.
            Color.clear.onAppear { viewModelHolder.adopt(recipe: recipe, library: library) }
        }
    }
}

/// `@StateObject` needs an init-time value; the holder adopts the recipe
/// the detail pane is showing (which changes with split-view selection).
@MainActor
private final class ViewHolder: ObservableObject {
    private var model: RecipeViewModel?
    private var adoptedID: String?

    func viewModel(for recipe: RecipeDocument, library: LibraryModel) -> RecipeViewModel? {
        if adoptedID == recipe.id, let model { return model }
        return nil
    }

    func adopt(recipe: RecipeDocument, library: LibraryModel) {
        guard adoptedID != recipe.id else { return }
        adoptedID = recipe.id
        model = RecipeViewModel(recipe: recipe, library: library)
        objectWillChange.send()
    }
}

private struct RecipeDetailContent: View {
    @EnvironmentObject private var library: LibraryModel
    @ObservedObject var viewModel: RecipeViewModel
    @State private var showingEditor = false

    var body: some View {
        List {
            if !viewModel.recipe.photoHashes.isEmpty {
                PhotoStrip(hashes: viewModel.recipe.photoHashes, viewModel: viewModel)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            summarySection
            factsSection
            ingredientsSection
            stepsSection
            notesSection
        }
        .listStyle(.plain)
        .navigationTitle(viewModel.recipe.title.isEmpty ? "Untitled" : viewModel.recipe.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("editRecipe")
            }
        }
        .sheet(isPresented: $showingEditor) {
            RecipeEditorView(recipe: viewModel.recipe)
                .onDisappear {
                    viewModel.reloadFromLibrary()
                }
        }
    }

    // MARK: Summary

    private var summarySection: some View {
        Section {
            if !viewModel.recipe.summary.isEmpty {
                Text(viewModel.recipe.summary)
                    .foregroundStyle(.secondary)
            }
            RatingStars(
                value: viewModel.recipe.rating,
                editable: true,
                onSet: { newValue in
                    Task { await viewModel.setRating(newValue) }
                })
        }
    }

    // MARK: Facts + scaling controls

    private var factsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if let yieldText = viewModel.yieldText {
                        Label(yieldText, systemImage: "person.2")
                    }
                    if let total = viewModel.recipe.totalTime {
                        Label(total.display, systemImage: "clock")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if viewModel.recipe.yieldAmount != nil {
                    YieldStepper(viewModel: viewModel)
                }
                UnitToggle(viewModel: viewModel)
            }
            if let url = viewModel.recipe.sourceURL, let link = URL(string: url) {
                Link(destination: link) {
                    Label("Source", systemImage: "safari")
                        .lineLimit(1)
                }
                .font(.subheadline)
            }
            if let attribution = viewModel.recipe.attribution, !attribution.isEmpty {
                Text(attribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Ingredients

    private var ingredientsSection: some View {
        ForEach(
            Array(viewModel.renderedSections.enumerated()), id: \.offset
        ) { sectionIndex, section in
            Section(section.name.isEmpty ? "Ingredients" : section.name) {
                ForEach(Array(section.lines.enumerated()), id: \.offset) { lineIndex, rendered in
                    IngredientRow(
                        rendered: rendered,
                        checked: viewModel.isChecked(section: sectionIndex, line: lineIndex)
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.toggleCheck(section: sectionIndex, line: lineIndex)
                        }
                    }
                }
            }
        }
    }

    // MARK: Steps

    private var stepsSection: some View {
        ForEach(
            Array(viewModel.recipe.stepSections.enumerated()), id: \.offset
        ) { _, section in
            Section(section.name.isEmpty ? "Directions" : section.name) {
                ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1).")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(viewModel.stepText(step))
                    }
                    if !step.timers.isEmpty {
                        TimerChips(timers: step.timers)
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        Group {
            if !viewModel.recipe.notes.isEmpty {
                Section("Notes") {
                    ForEach(
                        viewModel.recipe.notes
                            .split(separator: "\n\n", omittingEmptySubsequences: true)
                            .map(String.init), id: \.self
                    ) { paragraph in
                        Text(paragraph)
                    }
                }
            }
        }
    }
}

/// The photo strip: stored photos by hash, shown edge to edge. A
/// dangling reference shows a placeholder rather than failing.
private struct PhotoStrip: View {
    let hashes: [String]
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(hashes, id: \.self) { hash in
                    PhotoImage(hash: hash, viewModel: viewModel)
                        .frame(width: 320, height: 240)
                        .clipped()
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// One photo from the library's photo store.
private struct PhotoImage: View {
    let hash: String
    @ObservedObject var viewModel: RecipeViewModel
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.15))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: hash) {
            image = Self.image(from: viewModel.photoData(hash: hash))
        }
        .accessibilityLabel("Recipe photo")
    }

    static func image(from data: Data?) -> Image? {
        guard let data, let platformImage = PlatformImage(data: data) else { return nil }
        return Image(platformImage: platformImage)
    }
}

#if os(macOS)
    typealias PlatformImage = NSImage
#else
    typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}

/// The yield stepper: target yield on the left, the factor it implies
/// on the right. Stepping keeps the friendly rounding of the pipeline.
private struct YieldStepper: View {
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Makes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.yieldText ?? "—")
                    .font(.headline.monospacedDigit())
            }
            Spacer()
            Stepper {
                Text("Yield: \(steppedTargetDescription)")
            } onIncrement: {
                step(by: 1)
            } onDecrement: {
                step(by: -1)
            }
            .labelsHidden()
            .accessibilityLabel("Scale the recipe")
            .accessibilityValue("Serves \(steppedTargetDescription)")
        }
    }

    private var steppedTargetDescription: String {
        guard let target = viewModel.targetYield else { return "—" }
        return "\(RecipeMath.kitchenFraction(of: target))"
    }

    private func step(by direction: Int) {
        let current = (viewModel.targetYield ?? 0) as NSDecimalNumber
        let next = current.adding(NSDecimalNumber(value: direction))
        guard let written = viewModel.recipe.yieldAmount, next.decimalValue >= 1,
            next.decimalValue <= written * 50
        else { return }
        if let factor = viewModel.factor(forTargetYield: next.decimalValue) {
            viewModel.factor = factor
        }
    }
}

/// The unit system toggle: As written / Metric / US.
private struct UnitToggle: View {
    @ObservedObject var viewModel: RecipeViewModel

    var body: some View {
        Picker(
            "Units",
            selection: Binding(
                get: { viewModel.system },
                set: { viewModel.system = $0 })
        ) {
            ForEach(RecipeDisplay.UnitSystem.allCases, id: \.self) { system in
                Text(system.label).tag(system)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .accessibilityLabel("Ingredient units")
    }
}

/// One ingredient row: a check-off circle and the rendered text.
private struct IngredientRow: View {
    let rendered: RecipeDisplay.RenderedLine
    let checked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(rendered.text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rendered.text)
        .accessibilityHint(checked ? "Checked. Tap to uncheck." : "Tap to check off")
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// Timer chips under a step that names one: "30m" tappable later for
/// cook mode (M6); for now they display the durations.
private struct TimerChips: View {
    let timers: [Duration]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(timers.enumerated()), id: \.offset) { _, timer in
                Label(timer.display, systemImage: "timer")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
    }
}

/// Five stars, shown or editable. Tap a star to set the rating; tap the
/// same value again to clear it.
struct RatingStars: View {
    let value: Int
    let editable: Bool
    let onSet: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Group {
                    if editable {
                        Button {
                            onSet(value == star ? 0 : star)
                        } label: {
                            starImage(star)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    } else {
                        starImage(star)
                    }
                }
            }
            if !editable && value == 0 {
                Text("Not rated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func starImage(_ star: Int) -> some View {
        Image(
            systemName: star <= value
                ? "star.fill" : (star == value + 1 && value == 0 ? "star" : "star")
        )
        .foregroundStyle(star <= value ? Color.yellow : Color.secondary.opacity(0.4))
        .symbolRenderingMode(.multicolor)
    }
}
