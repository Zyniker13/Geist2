import Foundation
import RecipeCore
import RecipeImport
import Vision

/// On-device OCR for photographed recipes, using Vision. The recognized
/// lines go through the same text scanner as pasted text.
@MainActor
final class OCRModel {
    static let shared = OCRModel()

    /// Recognizes text in image bytes and returns the lines in reading
    /// order, or nil when nothing readable was found.
    nonisolated static func recognize(_ data: Data) async throws -> [String] {
        guard let image = VNImageRequestHandler(data: data, options: [:]) as VNImageRequestHandler?
        else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try image.perform([request])
        return (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
    }

    /// Recognizes a photo, joins the lines, and runs the import.
    func importPhoto(
        _ data: Data, into library: LibraryModel, importer: ImportModel
    ) async {
        importer.stage = .working("Reading the photo…")
        do {
            let lines = try await Self.recognize(data)
            let text = lines.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                importer.stage = .failed("No readable text in that photo.")
                return
            }
            // Keep the photo: it becomes the recipe's first image.
            if let hash = try? library.photos.store(data) {
                await importer.importText(text, into: library)
                // Re-stamp the saved document with the photo hash.
                if case .done(var document) = importer.stage {
                    if document.photoHashes.isEmpty {
                        document.photoHashes = [hash]
                        try await library.store.write(document)
                        await library.refresh()
                        importer.stage = .done(document)
                    }
                }
            } else {
                await importer.importText(text, into: library)
            }
        } catch {
            importer.stage = .failed("Could not read the photo: \(error.localizedDescription)")
        }
    }
}
