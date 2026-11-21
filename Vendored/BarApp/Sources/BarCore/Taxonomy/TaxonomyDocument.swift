import Foundation

/// One entry in the versioned ingredient and beverage taxonomy (M2).
///
/// Taxonomy data is reference data: it ships with the app as a versioned
/// document and is written into the replaceable `taxonomyNode` and
/// `taxonomyAlias` tables by `AppDatabase.replaceTaxonomy`. Identifiers are
/// stable dot paths (`spirit.scotch.single-malt`) so recipes, products, and
/// stored data can reference a node across app versions and across the
/// shared libraries added later.
public struct TaxonomyNodeData: Decodable, Equatable, Sendable {
    /// A category is a grouping node the user browses through; an
    /// ingredient is a leaf a bottle or a recipe ingredient can point at.
    /// Recipes may also reference a category when the drink calls for the
    /// class of spirit rather than a style ("scotch" in a Rob Roy).
    public enum Kind: String, Decodable, Sendable, CaseIterable {
        case category
        case ingredient
    }

    public let id: String
    public let parentId: String?
    public let kind: Kind
    public let name: String
    /// Alternate names the node answers to in search, in the user's
    /// language as written in the data file (for example "curaçao" for the
    /// orange liqueur node).
    public let aliases: [String]
    /// Names of the optional detail fields a product in this category may
    /// record, in kebab-case: rum carries "origin", "still-type",
    /// "fermentation", and "age"; wine carries "grape" and "region". The
    /// fields are descriptive metadata for the inventory, not required.
    public let detailFields: [String]
    /// A prose note in our own words, used where the taxonomy needs to
    /// explain itself (for example why sotol sits beside the agave
    /// spirits).
    public let notes: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case parentId
        case kind
        case name
        case aliases
        case detailFields
        case notes
    }

    public init(
        id: String,
        parentId: String?,
        kind: Kind,
        name: String,
        aliases: [String] = [],
        detailFields: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.kind = kind
        self.name = name
        self.aliases = aliases
        self.detailFields = detailFields
        self.notes = notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        kind = try container.decode(Kind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        detailFields = try container.decodeIfPresent([String].self, forKey: .detailFields) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// The whole versioned taxonomy document: the version and the nodes in
/// parent-before-child order.
public struct TaxonomyDocument: Decodable, Equatable, Sendable {
    /// Monotonic version of the reference data. The loader records it in
    /// `taxonomyVersion`; a higher number means the stored copy is stale.
    public let version: Int
    public let nodes: [TaxonomyNodeData]

    public init(version: Int, nodes: [TaxonomyNodeData]) {
        self.version = version
        self.nodes = nodes
    }
}
