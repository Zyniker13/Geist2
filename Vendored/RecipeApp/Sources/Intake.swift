import Foundation
import Vision
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import WebKit

enum RecipeIntake {
    static func fromText(_ text: String) -> Recipe {
        let lines = text.recipeLines
        let headings = ["directions", "instructions", "method", "preparation", "steps"]
        let ingredient = lines.firstIndex { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased() == "ingredients" }
        let direction = lines.indices.first {
            $0 > (ingredient ?? -1) && headings.contains(lines[$0].trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased())
        }
        var recipe = Recipe()
        recipe.title = (ingredient == 0 || direction == 0) ? "" : (lines.first ?? "")
        if let ingredient {
            recipe.ingredients = lines[(ingredient + 1)..<(direction ?? lines.endIndex)].map {
                $0.replacingOccurrences(of: #"^[•●*–-]\s*"#, with: "", options: .regularExpression)
            }
        }
        if let direction { recipe.directions = lines.dropFirst(direction + 1).joined(separator: "\n") }
        else if ingredient == nil { recipe.directions = lines.dropFirst().joined(separator: "\n") }
        return recipe
    }

    static func readPhoto(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            guard !lines.isEmpty else { throw RecipeError.message("No text found. Try a clearer photo.") }
            return lines.joined(separator: "\n")
        }.value
    }

    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmed), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func fromWebsite(_ address: String) async throws -> Recipe {
        guard let url = webURL(address) else { throw RecipeError.message("Enter the full website URL.") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecipeError.message("The website didn’t return a recipe page.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RecipeError.message("The website refused direct import (HTTP \(http.statusCode)). Try Open in browser.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 5_000_000 else { throw RecipeError.message("This page is too large to import. Paste the recipe text below.") }
            data.append(byte)
        }
        let html = String(decoding: data, as: UTF8.self)
        guard var recipe = structuredRecipe(in: html, base: response.url ?? url) else {
            throw RecipeError.message("No structured recipe found. You can paste the ingredients and directions below.")
        }
        recipe.source = response.url?.absoluteString ?? url.absoluteString
        return recipe
    }

    static func structuredRecipe(in html: String, base: URL) -> Recipe? {
        guard let pattern = try? NSRegularExpression(pattern: #"<script\b([^>]*)>([\s\S]*?)</script\s*>"#, options: .caseInsensitive) else { return nil }
        let source = html as NSString
        for match in pattern.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let attributes = source.substring(with: match.range(at: 1)).lowercased()
            guard attributes.contains("application/ld+json"),
                  let json = try? JSONSerialization.jsonObject(with: Data(source.substring(with: match.range(at: 2)).utf8)),
                  let object = recipeObject(in: json) else { continue }
            var recipe = Recipe()
            recipe.title = plain(object["name"] as? String ?? "")
            recipe.ingredients = (object["recipeIngredient"] as? [String] ?? []).map(plain).filter { !$0.isEmpty }
            recipe.categories = ((object["recipeCategory"] as? [String]) ?? [object["recipeCategory"] as? String ?? ""]).map(plain)
            recipe.directions = steps(object["recipeInstructions"]).joined(separator: "\n")
            recipe.photos = RecipeImage.fromURLs(imageAddresses(object["image"]), relativeTo: base)
            if let duration = object["totalTime"] as? String, duration.hasPrefix("PT") {
                recipe.time = duration.dropFirst(2).replacingOccurrences(of: "H", with: " hr ").replacingOccurrences(of: "M", with: " min ").trimmed
            }
            return recipe
        }
        return nil
    }

    static func photoURL(_ address: String, relativeTo base: URL? = nil) -> URL? {
        guard !address.trimmed.isEmpty, let url = URL(string: address.trimmed, relativeTo: base)?.absoluteURL,
              let validated = webURL(url.absoluteString), validated.scheme?.lowercased() == "https" else { return nil }
        return validated
    }

    private static func imageAddresses(_ value: Any?) -> [String] {
        if let address = value as? String { return [plain(address)] }
        if let values = value as? [Any] { return values.flatMap { imageAddresses($0) } }
        if let image = value as? [String: Any] {
            return ["contentUrl", "url", "@id"].flatMap { imageAddresses(image[$0]) }
        }
        return []
    }

    private static func recipeObject(in value: Any) -> [String: Any]? {
        if let array = value as? [Any] { return array.lazy.compactMap { recipeObject(in: $0) }.first }
        guard let object = value as? [String: Any] else { return nil }
        let types = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
        if types.contains(where: { $0.split(separator: "/").last?.lowercased() == "recipe" }),
           object["recipeIngredient"] is [String] { return object }
        return object.values.lazy.compactMap { recipeObject(in: $0) }.first
    }

    private static func steps(_ value: Any?) -> [String] {
        if let text = value as? String {
            let separated = text.replacingOccurrences(
                of: #"<(?:br\s*/?|/(?:li|p|div))\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive]
            )
            return separated.components(separatedBy: .newlines).map(plain).filter { !$0.isEmpty }
        }
        if let values = value as? [Any] { return values.flatMap { steps($0) } }
        if let object = value as? [String: Any] {
            if let children = object["itemListElement"] { return steps(children) }
            return steps(object["text"] ?? object["name"])
        }
        return []
    }

    private static func plain(_ value: String) -> String {
        let text = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let entities = ["&quot;":"\"", "&#39;":"'", "&amp;":"&", "&nbsp;":" ", "&lt;":"<", "&gt;":">",
                        "&frac12;":"½", "&frac14;":"¼", "&frac34;":"¾", "&deg;":"°"]
        guard let pattern = try? NSRegularExpression(pattern: #"&(?:#x[0-9a-fA-F]+|#\d+|[a-zA-Z0-9]+);"#) else { return text.trimmed }
        let result = NSMutableString(string: text)
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let entity = result.substring(with: match.range)
            let number = entity.hasPrefix("&#x") ? UInt32(entity.dropFirst(3).dropLast(), radix: 16) :
                (entity.hasPrefix("&#") ? UInt32(entity.dropFirst(2).dropLast()) : nil)
            if let decoded = entities[entity] ?? number.flatMap(UnicodeScalar.init).map(String.init) {
                result.replaceCharacters(in: match.range, with: decoded)
            }
        }
        return (result as String).trimmed
    }
}

struct IntakeView: View {
    let scan: Bool
    let review: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var chooseFile = false
    @State private var loading = false
    @State private var message = ""
    @State private var browserRequest: BrowserRequest?

    private struct BrowserRequest {
        let url: URL
        let autoImport: Bool
    }

    var body: some View {
        if let browserRequest {
            RecipeBrowser(url: browserRequest.url, autoImport: browserRequest.autoImport,
                          close: { self.browserRequest = nil }) { recipe in
                self.browserRequest = nil
                review(recipe)
            }
        } else {
            intakeForm
        }
    }

    private var intakeForm: some View {
        NavigationStack {
            Form {
                if scan {
                    Section("Recipe photo") {
                        PhotosPicker("Choose from Photos", selection: $photo, matching: .images)
                        Button("Choose image file") { chooseFile = true }
                    }
                } else {
                    Section("Recipe link") {
                        TextField("https://…", text: $address)
                        Button("Import link") { Task { await loadLink() } }
                            .disabled(loading || address.trimmed.isEmpty)
                        Button("Open in browser", systemImage: "globe") {
                            if let url = RecipeIntake.webURL(address) {
                                browserRequest = BrowserRequest(url: url, autoImport: false)
                            }
                        }.disabled(loading || RecipeIntake.webURL(address) == nil)
                    }
                }
                Section(scan ? "Detected text" : "Paste recipe text") {
                    TextEditor(text: $text).frame(minHeight: 150)
                        .accessibilityLabel(scan ? "Detected text" : "Recipe text")
                }
                if loading { ProgressView() }
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            .appSurface()
            .navigationTitle(scan ? "Scan a recipe" : "Import a recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        var recipe = RecipeIntake.fromText(text)
                        if !scan { recipe.source = RecipeIntake.webURL(address)?.absoluteString }
                        review(recipe)
                    }.disabled(loading || text.trimmed.isEmpty)
                }
            }
            .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.image]) { result in
                Task {
                    await read {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try Data(contentsOf: url)
                    }
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    await read {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw RecipeError.message("Could not open the photo.") }
                        return data
                    }
                    photo = nil
                }
            }
        }
    }

    private func read(_ image: () async throws -> Data) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            text = try await RecipeIntake.readPhoto(image())
            message = "Check the detected text before saving."
        } catch { message = error.localizedDescription }
    }

    private func loadLink() async {
        guard let url = RecipeIntake.webURL(address) else {
            message = "Enter the full website URL."
            return
        }
        loading = true
        message = ""
        defer { loading = false }
        do {
            let recipe = try await RecipeIntake.fromWebsite(url.absoluteString)
            try Task.checkCancellation()
            review(recipe)
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            message = error.localizedDescription
            browserRequest = BrowserRequest(url: url, autoImport: true)
        }
    }
}

@MainActor @Observable private final class BrowserSession: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var message = ""
    var loaded = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loaded = false
        message = ""
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, RecipeIntake.webURL(url.absoluteString) != nil else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame {
            let status = (response.response as? HTTPURLResponse)?.statusCode ?? 0
            loaded = false
            if !(200..<300).contains(status) {
                message = "The website returned HTTP \(status). Import is available after the recipe page loads."
            } else {
                message = ""
            }
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = message.isEmpty && RecipeIntake.webURL(webView.url?.absoluteString ?? "") != nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { message = error.localizedDescription }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded = false
        message = error.localizedDescription
    }

    func recipe() async throws -> Recipe {
        guard loaded, let url = webView.url else { throw RecipeError.message("Wait for the recipe to load.") }
        let page = try await webView.evaluateJavaScript("""
            (() => {
                const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
                    .map(script => script.textContent)
                    .filter(text => text && text.length < 2000000)
                    .slice(0, 30);
                const imageURLs = Array.from(document.querySelectorAll(
                    'main [itemprop="image"], article [itemprop="image"], meta[property="og:image:secure_url"], meta[property="og:image"], meta[name="twitter:image"]'
                )).slice(0, 30).map(element => {
                    const image = element.matches('img') ? element : element.querySelector('img');
                    const address = image?.currentSrc || image?.getAttribute('src')
                        || element.getAttribute('content') || element.getAttribute('href');
                    try { return address ? new URL(address, document.baseURI).href : null; }
                    catch { return null; }
                }).filter(Boolean);
                const normalize = text => (text || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, ' ');
                const title = normalize(document.querySelector('h1')?.textContent);
                const rendered = title ? Array.from(document.images).find(image =>
                    normalize(image.alt) === title && image.naturalWidth >= 240 && image.currentSrc
                ) : null;
                let photos = [];
                if (rendered) {
                    try {
                        const canvas = document.createElement('canvas');
                        const scale = Math.min(1, 960 / Math.max(rendered.naturalWidth, rendered.naturalHeight));
                        canvas.width = Math.max(1, Math.round(rendered.naturalWidth * scale));
                        canvas.height = Math.max(1, Math.round(rendered.naturalHeight * scale));
                        canvas.getContext('2d').drawImage(rendered, 0, 0, canvas.width, canvas.height);
                        const jpeg = canvas.toDataURL('image/jpeg', 0.85).split(',')[1];
                        if (jpeg && jpeg.length < 1500000) photos = [jpeg];
                    } catch {
                        // Keep the image URL if the publisher restricts access to image pixels.
                    }
                }
                return { scripts, imageURLs, rendered: rendered ? [rendered.currentSrc] : [], photos };
            })()
            """, in: nil, contentWorld: .defaultClient) as? [String: [String]] ?? [:]
        guard loaded, url == webView.url else { throw RecipeError.message("The page changed. Try importing again.") }
        let html = (page["scripts"] ?? []).map { "<script type=\"application/ld+json\">" + $0 + "</script>" }.joined()
        guard var recipe = RecipeIntake.structuredRecipe(in: html, base: url), !recipe.ingredients.isEmpty else {
            throw RecipeError.message("This page doesn’t expose structured recipe ingredients.")
        }
        let structured = recipe.photos.compactMap(\.url)
        let rendered = page["rendered"] ?? []
        let preferred = rendered + structured
        var photos = RecipeImage.fromURLs(preferred.isEmpty ? Array((page["imageURLs"] ?? []).prefix(1)) : preferred)
        if !photos.isEmpty, let jpeg = page["photos"]?.first {
            photos[0].data = Data(base64Encoded: jpeg)
        }
        recipe.photos = photos
        recipe.source = url.absoluteString
        return recipe
    }

}

private struct RecipeBrowser: View {
    let url: URL
    let autoImport: Bool
    let close: () -> Void
    let review: (Recipe) -> Void
    @State private var session = BrowserSession()
    @State private var importError = ""
    @State private var importing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WebPageView(webView: session.webView)
                if autoImport && session.message.isEmpty && importError.isEmpty && (!session.loaded || importing) {
                    ProgressView("Trying browser import…")
                        .padding(10)
                }
                if !session.message.isEmpty || !importError.isEmpty {
                    Text(session.message.isEmpty ? importError : session.message)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Recipe browser")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: close).disabled(importing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import this page") {
                        Task { await importPage() }
                    }.disabled(!session.loaded || importing)
                }
            }
            .onAppear {
                if session.webView.url == nil { session.webView.load(URLRequest(url: url)) }
            }
            .task(id: session.loaded) {
                guard session.loaded else { return }
                importError = ""
                if autoImport { await importPage() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 530)
        #endif
    }

    private func importPage() async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        do {
            let recipe = try await session.recipe()
            try Task.checkCancellation()
            review(recipe)
        } catch {
            if !Task.isCancelled { importError = error.localizedDescription }
        }
    }
}

#if os(macOS)
private struct WebPageView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
private struct WebPageView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

extension RecipeImage {
    static func fromURLs(_ addresses: [String], relativeTo base: URL? = nil) -> [Self] {
        var seen = Set<URL>()
        return addresses.compactMap { RecipeIntake.photoURL($0, relativeTo: base) }
            .filter { seen.insert($0).inserted }.prefix(8)
            .map { Self(url: $0.absoluteString) }
    }
}
