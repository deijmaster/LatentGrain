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
}
