import Foundation

/// Full persistence state of a Mac captured at a single point in time.
struct PersistenceSnapshot: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var label: String               // e.g. "Before Spotify install"
    let items: [PersistenceItem]
    let snapshotHash: String        // SHA-256 of all item hashes joined — quick equality check

    var itemCount: Int { items.count }

    /// Items grouped by their persistence location.
    var groupedByLocation: [PersistenceLocation: [PersistenceItem]] {
        Dictionary(grouping: items, by: \.location)
    }
}
