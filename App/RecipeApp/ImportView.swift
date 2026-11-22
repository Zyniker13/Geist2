import PhotosUI
import RecipeCore
import RecipeImport
import SwiftUI

/// The import sheet: paste a link, paste text, or a photo. All three
/// end in the same extractor chain.
struct ImportView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var importer: ImportModel
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case link, text, photo
        var id: String { rawValue }
    }
    @State private var tab: Tab = .link
    @State private var link = ""
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $tab) {
                    Text("Link").tag(Tab.link)
                    Text("Text").tag(Tab.text)
                    Text("Photo").tag(Tab.photo)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sourcePicker")
                switch tab {
                case .link:
                    #if os(iOS)
                        TextField("https://example.com/recipe", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("linkField")
                    #else
                        TextField("https://example.com/recipe", text: $link)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("linkField")
                    #endif
                    Button("Import") {
                        Task { await importer.importLink(link, into: library) }
                    }
                    .accessibilityIdentifier("linkImport")
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                case .text:
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .accessibilityIdentifier("pasteEditor")
                    Button("Import") {
                        Task { await importer.importText(text, into: library) }
                    }
                    .accessibilityIdentifier("textImport")
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                case .photo:
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose a recipe photo", systemImage: "photo")
                    }
                    .onChange(of: photoItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                await OCRModel.shared.importPhoto(
                                    data, into: library, importer: importer)
                            }
                        }
                    }
                    Text("A photo of a printed recipe or recipe card. The text is read on-device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                stageFooter
            }
            .navigationTitle("Import")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var stageFooter: some View {
        switch importer.stage {
        case .idle:
            EmptyView()
        case .working(let label):
            HStack(spacing: 8) {
                ProgressView()
                Text(label).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .done(let document):
            Label(
                "Saved “\(document.title)”.",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        }
    }
}
