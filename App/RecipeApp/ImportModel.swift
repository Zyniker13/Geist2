import Foundation
import RecipeCore
import RecipeImport

/// Runs one import job: fetch a URL (or read a paste) and extract a
/// recipe through the RecipeExtractor chain.
@MainActor
final class ImportModel: ObservableObject {
    enum Stage: Equatable {
        case idle
        case working(String)
        case done(RecipeDocument)
        case failed(String)
    }

    @Published var stage: Stage = .idle

    /// Imports from a pasted or typed link. The fetch is real URLSession
    /// with a browser-like User-Agent; many recipe sites 403 bare
    /// clients. Timeouts surface as readable failures.
    func importLink(_ link: String, into library: LibraryModel) async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme,
            scheme == "http" || scheme == "https"
        else {
            stage = .failed("That does not look like a web link.")
            return
        }
        stage = .working("Fetching the page…")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                stage = .failed("The site answered \(http.statusCode).")
                return
            }
            guard
                let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
            else {
                stage = .failed("The page could not be read.")
                return
            }
            await finish(html: html, url: trimmed, into: library)
        } catch {
            stage = .failed("Could not reach the site: \(error.localizedDescription)")
        }
    }

    /// Imports pasted recipe text (no web page involved).
    func importText(_ text: String, into library: LibraryModel) async {
        stage = .working("Reading the text…")
        await finish(html: nil, text: text, url: nil, into: library)
    }

    /// Extracts from already-fetched HTML (the share extension and the
    /// browser fallback call this with page contents they got elsewhere).
    func importHTML(_ html: String, url: String?, into library: LibraryModel) async {
        stage = .working("Reading the page…")
        await finish(html: html, url: url, into: library)
    }

    private func finish(
        html: String? = nil, text: String? = nil, url: String? = nil,
        into library: LibraryModel
    ) async {
        let now = Int64(Date().timeIntervalSince1970)
        let id = UUID().uuidString
        do {
            let report: RecipeExtractor.Report?
            if let html {
                report = RecipeExtractor.extract(fromHTML: html, now: now, id: id)
            } else if let text {
                report = RecipeExtractor.extract(fromText: text, now: now, id: id)
            } else {
                report = nil
            }
            guard let report else {
                stage = .failed("No recipe found in that.")
                return
            }
            var document = report.document
            if let url { document.sourceURL = url }
            try await library.save(
                RecipeExtractor.Report(
                    source: report.source, document: document))
            stage = .done(document)
        } catch {
            stage = .failed("Import failed: \(error.localizedDescription)")
        }
    }
}
