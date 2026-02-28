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
    /// Raw values of `PersistenceLocation`s that had changes (added/removed/modified).
    /// Empty for records created before this field was added.
    var affectedLocations: [String]

    var totalChanges: Int { addedCount + removedCount + modifiedCount }
    var isEmpty: Bool    { totalChanges == 0 }

    /// Resolved locations for display, preserving `allCases` order.
    var resolvedLocations: [PersistenceLocation] {
        let set = Set(affectedLocations)
        return PersistenceLocation.allCases.filter { set.contains($0.rawValue) }
    }

    // Backward-compat: records saved before this field existed decode to [].
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        beforeSnapshotID  = try c.decode(UUID.self,   forKey: .beforeSnapshotID)
        afterSnapshotID   = try c.decode(UUID.self,   forKey: .afterSnapshotID)
        timestamp         = try c.decode(Date.self,   forKey: .timestamp)
        addedCount        = try c.decode(Int.self,    forKey: .addedCount)
        removedCount      = try c.decode(Int.self,    forKey: .removedCount)
        modifiedCount     = try c.decode(Int.self,    forKey: .modifiedCount)
        source            = try c.decode(String.self, forKey: .source)
        affectedLocations = (try? c.decode([String].self, forKey: .affectedLocations)) ?? []
    }

    init(id: UUID, beforeSnapshotID: UUID, afterSnapshotID: UUID, timestamp: Date,
         addedCount: Int, removedCount: Int, modifiedCount: Int, source: String,
         affectedLocations: [String] = []) {
        self.id                = id
        self.beforeSnapshotID  = beforeSnapshotID
        self.afterSnapshotID   = afterSnapshotID
        self.timestamp         = timestamp
        self.addedCount        = addedCount
        self.removedCount      = removedCount
        self.modifiedCount     = modifiedCount
        self.source            = source
        self.affectedLocations = affectedLocations
    }
}
