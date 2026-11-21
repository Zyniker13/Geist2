import Foundation

/// One problem found while validating a taxonomy document. Validation is
/// strict because the document is reference data written into the
/// replaceable taxonomy tables: a bad document must be refused before it
/// can degrade search or browsing for everyone.
public struct TaxonomyValidationIssue: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The document's version is not a positive integer.
        case versionBelowOne
        /// The document carries no nodes at all.
        case emptyDocument
        /// A node has an empty id.
        case emptyId
        /// A node's id is not a dot path of lowercase segments
        /// (`spirit.scotch.single-malt`).
        case invalidId(String)
        /// Two nodes share an id.
        case duplicateId(String)
        /// A node points at a parent that does not exist in the document.
        case missingParent(String)
        /// A node appears before its parent in document order; the loader
        /// writes nodes in order, so a child would violate its foreign key.
        case parentAfterChild(String)
        /// A node's parent chain loops back on itself.
        case cycle(String)
        /// A node has an empty display name.
        case emptyName
        /// The same alias is listed twice on one node.
        case duplicateAlias(String)
        /// A node's alias equals its own id, which would leak an internal
        /// path into user-facing search.
        case aliasEqualsId(String)
        /// A detail-field name is empty or not kebab-case.
        case invalidDetailField(String)
    }

    /// The id of the offending node, when the reason is about one node.
    public let nodeId: String?
    public let reason: Reason

    public init(nodeId: String?, reason: Reason) {
        self.nodeId = nodeId
        self.reason = reason
    }
}

/// Thrown by `AppDatabase.replaceTaxonomy` when a document fails
/// validation; the database is left untouched.
public struct TaxonomyValidationError: Error, Equatable, Sendable {
    public let issues: [TaxonomyValidationIssue]

    public init(issues: [TaxonomyValidationIssue]) {
        self.issues = issues
    }
}

extension TaxonomyDocument {
    /// Returns every problem with the document, in document order per
    /// node; an empty array means the document may be written.
    public func validate() -> [TaxonomyValidationIssue] {
        var issues: [TaxonomyValidationIssue] = []
        if version < 1 {
            issues.append(TaxonomyValidationIssue(nodeId: nil, reason: .versionBelowOne))
        }
        if nodes.isEmpty {
            issues.append(TaxonomyValidationIssue(nodeId: nil, reason: .emptyDocument))
        }

        var seenIds = Set<String>()
        var idsInOrder: [String] = []
        for node in nodes {
            if node.id.isEmpty {
                issues.append(TaxonomyValidationIssue(nodeId: nil, reason: .emptyId))
            } else if !isValidId(node.id) {
                issues.append(
                    TaxonomyValidationIssue(nodeId: node.id, reason: .invalidId(node.id))
                )
            }
            if seenIds.contains(node.id) {
                issues.append(
                    TaxonomyValidationIssue(nodeId: node.id, reason: .duplicateId(node.id))
                )
            }
            seenIds.insert(node.id)
            idsInOrder.append(node.id)

            if node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(TaxonomyValidationIssue(nodeId: node.id, reason: .emptyName))
            }
            var seenAliases = Set<String>()
            for alias in node.aliases {
                if !seenAliases.insert(alias).inserted {
                    issues.append(
                        TaxonomyValidationIssue(
                            nodeId: node.id,
                            reason: .duplicateAlias(alias)
                        )
                    )
                }
                if alias == node.id {
                    issues.append(
                        TaxonomyValidationIssue(nodeId: node.id, reason: .aliasEqualsId(alias))
                    )
                }
            }
            for field in node.detailFields where !isValidDetailFieldName(field) {
                issues.append(
                    TaxonomyValidationIssue(
                        nodeId: node.id,
                        reason: .invalidDetailField(field)
                    )
                )
            }
        }

        let ids = Set(idsInOrder)
        var positionById: [String: Int] = [:]
        for (index, id) in idsInOrder.enumerated() {
            positionById[id] = index
        }
        for node in nodes {
            if let parentId = node.parentId {
                if !ids.contains(parentId) {
                    issues.append(
                        TaxonomyValidationIssue(
                            nodeId: node.id,
                            reason: .missingParent(parentId)
                        )
                    )
                } else if let parentPosition = positionById[parentId],
                    parentPosition >= positionById[node.id, default: 0]
                {
                    issues.append(
                        TaxonomyValidationIssue(
                            nodeId: node.id,
                            reason: .parentAfterChild(parentId)
                        )
                    )
                }
            }
        }

        // Cycle check: walk each node's parent chain; a chain that revisits
        // a node loops. Missing parents are already reported above, so the
        // walk stops at them.
        for node in nodes {
            var visited = Set<String>()
            var current = node.parentId
            while let id = current {
                if visited.contains(id) || id == node.id {
                    issues.append(
                        TaxonomyValidationIssue(nodeId: node.id, reason: .cycle(node.id))
                    )
                    break
                }
                visited.insert(id)
                current = nodes.first(where: { $0.id == id })?.parentId
            }
        }

        return issues
    }

    /// An id is a dot path of one or more segments; a segment is lowercase
    /// letters or digits joined by single hyphens, like `spirit.scotch`.
    private func isValidId(_ id: String) -> Bool {
        id.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { segment in
            isValidSegment(String(segment))
        }
    }

    private func isValidSegment(_ segment: String) -> Bool {
        guard !segment.isEmpty else { return false }
        return segment.split(separator: "-", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isLowercase || $0.isNumber }
        }
    }

    /// A detail-field name is one kebab-case word, like `still-type`.
    private func isValidDetailFieldName(_ field: String) -> Bool {
        isValidSegment(field)
    }
}
