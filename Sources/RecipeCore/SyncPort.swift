import Foundation

/// The document kinds the library stores, one JSON document each.
public enum DocumentKind: String, Sendable, CaseIterable, Codable {
    case recipe
    case plan
    case list
    case pantry
}

/// A field-level change to one document, as `SyncPort` receives it.
///
/// Changes are described as maps of fields so a transport can carry them
/// without knowing the model, and two devices editing different fields of
/// one document both survive (M10.2). `changedFieldIDs` names the fields
/// that were written; `document` carries the writer's full post-change
/// document state for that document.
public struct DocumentChange: Equatable, Sendable {
    public let kind: DocumentKind
    /// The document's stable ID.
    public let documentID: String
    /// The fields written by this change, by stable field name.
    public let changedFieldIDs: Set<String>
    /// The document's state after the change, as a sync-shaped map of
    /// fields to JSON values.
    public let fields: [String: FieldValue]
    /// When the change was made (writer's clock).
    public let modifiedAt: Int64

    public init(
        kind: DocumentKind,
        documentID: String,
        changedFieldIDs: Set<String>,
        fields: [String: FieldValue],
        modifiedAt: Int64
    ) {
        self.kind = kind
        self.documentID = documentID
        self.changedFieldIDs = changedFieldIDs
        self.fields = fields
        self.modifiedAt = modifiedAt
    }
}

/// A sync-shaped field value: exactly what JSON can carry, no Dates.
public enum FieldValue: Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([FieldValue])
    case object([String: FieldValue])
    case null
}

/// The protocol every library write goes through (decision 0005).
///
/// The library store calls `apply` after each successful local write;
/// a transport implements `apply` to forward the change or record it for
/// later delivery. The protocol is deliberately tiny: it receives
/// changes, it does not fetch.
public protocol SyncPort: Sendable {
    /// Called once per committed local change, in commit order.
    func apply(_ change: DocumentChange) async
}

/// A no-op port: what the app uses until real sync exists.
public struct NullSyncPort: SyncPort {
    public init() {}

    public func apply(_ change: DocumentChange) async {}
}

/// A test port that records every change in order.
public actor RecordingSyncPort: SyncPort {
    private var recorded: [DocumentChange] = []

    public init() {}

    public func apply(_ change: DocumentChange) async {
        recorded.append(change)
    }

    /// The changes applied so far, in order.
    public var changes: [DocumentChange] {
        recorded
    }
}
