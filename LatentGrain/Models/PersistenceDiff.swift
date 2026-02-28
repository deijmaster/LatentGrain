import Foundation

/// The result of comparing two `PersistenceSnapshot`s.
struct PersistenceDiff: Identifiable {
    let id: UUID
    let before: PersistenceSnapshot
    let after: PersistenceSnapshot
    let added: [PersistenceItem]
    let removed: [PersistenceItem]
    let modified: [(before: PersistenceItem, after: PersistenceItem)]

    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && modified.isEmpty
    }

    var totalChanges: Int {
        added.count + removed.count + modified.count
    }

    /// Raw values of locations that had any change — for persisting in `DiffRecord`.
    var affectedLocationValues: [String] {
        var locations = Set<PersistenceLocation>()
        for item in added { locations.insert(item.location) }
        for item in removed { locations.insert(item.location) }
        for pair in modified { locations.insert(pair.after.location) }
        return PersistenceLocation.allCases.filter { locations.contains($0) }.map(\.rawValue)
    }
}
