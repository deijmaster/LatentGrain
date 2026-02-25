import Foundation

/// Lightweight, persisted summary of a completed diff — one entry per auto or manual scan pair.
/// Full diff details are reconstructed on demand from the referenced snapshots.
struct DiffRecord: Codable, Identifiable {
    let id: UUID
    let beforeSnapshotID: UUID
    let afterSnapshotID: UUID
    let timestamp: Date
    let addedCount: Int
    let removedCount: Int
    let modifiedCount: Int
    let source: String   // "Manual" or "Auto"

    var totalChanges: Int { addedCount + removedCount + modifiedCount }
    var isEmpty: Bool    { totalChanges == 0 }
}
