import Foundation
import RecipeCore
import UniformTypeIdentifiers

/// The share extension's principal handler: receives URL, HTML or
/// text attachments from the share sheet, extracts a recipe through
/// the shared path, and writes it into the library. No visible UI;
/// the sheet closes as soon as the write lands. Compiles for iOS and
/// macOS from one body.
final class ShareHandler: NSObject, NSExtensionRequestHandling {
    /// NSExtensionContext is not Sendable; the box carries it into the
    /// task that finishes the request.
    private final class ContextBox: @unchecked Sendable {
        let context: NSExtensionContext
        init(_ context: NSExtensionContext) { self.context = context }
    }

    func beginRequest(with context: NSExtensionContext) {
        let box = ContextBox(context)
        Task {
            await ShareHandler.run(box)
        }
    }

    private static func run(_ box: ContextBox) async {
        let attachments = box.context.inputItems.compactMap {
            ($0 as? NSExtensionItem)?.attachments
        }.flatMap { $0 }

        var html: String?
        var url: String?
        var text: String?

        for attachment in attachments {
            if url == nil,
                attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            {
                let item = try? await attachment.loadItem(
                    forTypeIdentifier: UTType.url.identifier
                )
                url = (item as? URL)?.absoluteString
            }
            if html == nil,
                attachment.hasItemConformingToTypeIdentifier(UTType.html.identifier)
            {
                html =
                    (try? await attachment.loadItem(
                        forTypeIdentifier: UTType.html.identifier
                    )) as? String
            }
            if text == nil,
                attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            {
                text =
                    (try? await attachment.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier
                    )) as? String
            }
        }

        var effectiveHTML = html
        if effectiveHTML == nil, text == nil, let url {
            // Safari usually shares only the URL: fetch the page here so
            // extraction has something to work with.
            effectiveHTML = await Self.fetchHTML(for: url)
        }

        let document = SharedLibrary.extract(
            html: effectiveHTML, text: text, url: url,
            now: Int64(Date().timeIntervalSince1970),
            id: UUID().uuidString)

        if let document {
            do {
                let store = LibraryStore(root: SharedLibrary.root)
                try await store.write(document)
            } catch {
                // Nothing to show in a no-UI extension; the request
                // still completes so the host app returns cleanly.
            }
        }
        box.context.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Fetches the page body for URL-only shares. Plain URLSession data
    /// task, bridged to async; errors return nil and extraction sees
    /// "nothing" exactly as before.
    private static func fetchHTML(for urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }
}
