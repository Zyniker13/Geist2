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

        let document = SharedLibrary.extract(
            html: html, text: text, url: url,
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
}
