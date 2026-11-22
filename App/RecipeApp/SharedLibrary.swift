import Foundation
import RecipeCore
import RecipeImport

/// Where the app and the share extensions meet on disk. The App Group
/// container holds the library root so an extension can save a recipe
/// straight into the same library the app reads. When the group is
/// unavailable (tests, or a host that did not create it yet) the root
/// falls back to the app's own Documents/Library.
enum SharedLibrary {
    /// The App Group identifier. Same value in project.yml entitlements.
    static let groupID = "group.com.bristleconeit.geist2"

    /// The library root: App Group container when available, else the
    /// app sandbox's Documents/Library.
    static var root: URL {
        if let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID)
        {
            return base.appendingPathComponent("Library", isDirectory: true)
        }
        return FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Library", isDirectory: true)
    }

    /// Runs the shared extraction used by the import sheet and the
    /// share extension: extract a document from HTML or text and stamp
    /// the source URL. Returns the document, or nil when nothing
    /// recipe-shaped was found. Writing stays with the caller so each
    /// surface records its own source and emits its own change.
    static func extract(
        html: String? = nil, text: String? = nil, url: String?,
        now: Int64, id: String
    ) -> RecipeDocument? {
        let report: RecipeExtractor.Report?
        if let html {
            report = RecipeExtractor.extract(fromHTML: html, now: now, id: id)
        } else if let text {
            report = RecipeExtractor.extract(fromText: text, now: now, id: id)
        } else {
            report = nil
        }
        guard var document = report?.document else { return nil }
        if let url { document.sourceURL = url }
        return document
    }
}
