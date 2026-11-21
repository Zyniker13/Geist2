import Foundation

/// The sync-shaped view of each document: maps of fields to `FieldValue`s
/// that travel through `SyncPort` (decision 0005, `docs/sync.md` at M10).
///
/// The mapping is explicit and exhaustive: adding a field to a document
/// means adding it here, so nothing syncs silently.
public protocol SyncDocument: Sendable {
    var documentID: String { get }
    var schemaVersion: Int { get }
    var createdAt: Int64 { get }
    var modifiedAt: Int64 { get }
    var deletedAt: Int64? { get }
    /// Every field of the document, by stable field name.
    func syncFields() -> [String: FieldValue]
    /// The document encoded as its on-disk JSON.
    func encoded() -> Data
}

extension RecipeDocument: SyncDocument {
    public var documentID: String { id }

    public func syncFields() -> [String: FieldValue] {
        var fields: [String: FieldValue] = [
            "schemaVersion": .int(Int64(schemaVersion)),
            "title": .string(title),
            "summary": .string(summary),
            "yieldUnit": .string(yieldUnit),
            "tags": .array(tags.map { .string($0) }),
            "categories": .array(categories.map { .string($0) }),
            "notes": .string(notes),
            "rating": .int(Int64(rating)),
            "createdAt": .int(createdAt),
            "modifiedAt": .int(modifiedAt),
        ]
        fields["yieldAmount"] = yieldAmount.map { .string("\($0)") } ?? .null
        fields["prepTime"] = prepTime.map { .int(Int64($0.seconds)) } ?? .null
        fields["cookTime"] = cookTime.map { .int(Int64($0.seconds)) } ?? .null
        fields["totalTime"] = totalTime.map { .int(Int64($0.seconds)) } ?? .null
        fields["cuisine"] = cuisine.map { .string($0) } ?? .null
        fields["sourceURL"] = sourceURL.map { .string($0) } ?? .null
        fields["attribution"] = attribution.map { .string($0) } ?? .null
        fields["deletedAt"] = deletedAt.map { .int($0) } ?? .null
        fields["ingredientSections"] = .array(
            ingredientSections.map { section in
                .object([
                    "name": .string(section.name),
                    "lines": .array(section.lines.map(\.syncValue)),
                ])
            })
        fields["stepSections"] = .array(
            stepSections.map { section in
                .object([
                    "name": .string(section.name),
                    "steps": .array(
                        section.steps.map { step in
                            .object([
                                "text": .string(step.text),
                                "timers": .array(step.timers.map { .int(Int64($0.seconds)) }),
                            ])
                        }),
                ])
            })
        fields["photoHashes"] = .array(photoHashes.map { .string($0) })
        fields["nutrition"] = .object(
            Dictionary(uniqueKeysWithValues: nutrition.map { ($0.key, .string($0.value)) }))
        return fields
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

extension IngredientLine {
    var syncValue: FieldValue {
        .object([
            "quantity": quantity.map { .string("\($0.amount)") } ?? .null,
            "quantityHigh": quantityHigh.map { .string("\($0.amount)") } ?? .null,
            "unitID": unitID.map { .string($0) } ?? .null,
            "item": .string(item),
            "preparation": preparation.map { .string($0) } ?? .null,
            "note": note.map { .string($0) } ?? .null,
            "optional": .bool(optional),
            "toTaste": .bool(toTaste),
            "originalText": .string(originalText),
        ])
    }
}

extension PlanDocument: SyncDocument {
    public var documentID: String { id }

    public func syncFields() -> [String: FieldValue] {
        [
            "schemaVersion": .int(Int64(schemaVersion)),
            "entries": .array(
                entries.map { entry in
                    .object([
                        "day": .string(entry.day),
                        "meal": .string(entry.meal),
                        "recipeID": .string(entry.recipeID),
                        "servings": .string("\(entry.servings)"),
                    ])
                }),
            "createdAt": .int(createdAt),
            "modifiedAt": .int(modifiedAt),
            "deletedAt": deletedAt.map { .int($0) } ?? .null,
        ]
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

extension ListDocument: SyncDocument {
    public var documentID: String { id }

    public func syncFields() -> [String: FieldValue] {
        [
            "schemaVersion": .int(Int64(schemaVersion)),
            "name": .string(name),
            "lines": .array(
                lines.map { line in
                    .object([
                        "text": .string(line.text),
                        "quantity": line.quantity.map { .string("\($0.amount)") } ?? .null,
                        "unitID": line.unitID.map { .string($0) } ?? .null,
                        "item": .string(line.item),
                        "aisle": line.aisle.map { .string($0) } ?? .null,
                        "recipeID": line.recipeID.map { .string($0) } ?? .null,
                        "checked": .bool(line.checked),
                        "movedToPantry": .bool(line.movedToPantry),
                    ])
                }),
            "createdAt": .int(createdAt),
            "modifiedAt": .int(modifiedAt),
            "deletedAt": deletedAt.map { .int($0) } ?? .null,
        ]
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

extension PantryDocument: SyncDocument {
    public var documentID: String { id }

    public func syncFields() -> [String: FieldValue] {
        [
            "schemaVersion": .int(Int64(schemaVersion)),
            "items": .array(
                items.map { item in
                    .object([
                        "name": .string(item.name),
                        "quantity": item.quantity.map { .string("\($0.amount)") } ?? .null,
                        "unitID": item.unitID.map { .string($0) } ?? .null,
                        "useBy": item.useBy.map { .int($0) } ?? .null,
                    ])
                }),
            "createdAt": .int(createdAt),
            "modifiedAt": .int(modifiedAt),
            "deletedAt": deletedAt.map { .int($0) } ?? .null,
        ]
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}
