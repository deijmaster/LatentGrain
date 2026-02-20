import XCTest
@testable import LatentGrain

final class DiffServiceTests: XCTestCase {

    private let sut = DiffService()

    // MARK: - Helpers

    private func item(
        path: String,
        hash: String = "abc123",
        location: PersistenceLocation = .userLaunchAgents
    ) -> PersistenceItem {
        PersistenceItem(
            id: UUID(),
            filename: URL(fileURLWithPath: path).lastPathComponent,
            fullPath: path,
            location: location,
            modificationDate: Date(),
            fileSize: 1024,
            contentsHash: hash,
            label: nil,
            programPath: nil,
            runAtLoad: nil,
            keepAlive: nil
        )
    }

    private func snapshot(_ items: [PersistenceItem], label: String = "Test") -> PersistenceSnapshot {
        PersistenceSnapshot(
            id: UUID(),
            timestamp: Date(),
            label: label,
            items: items,
            snapshotHash: "testhash"
        )
    }

    // MARK: - Tests

    func testEmptyDiff_whenSnapshotsIdentical() {
        let items  = [item(path: "/a/b.plist")]
        let before = snapshot(items)
        let after  = snapshot(items)

        let diff = sut.diff(before: before, after: after)

        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff.added.count,    0)
        XCTAssertEqual(diff.removed.count,  0)
        XCTAssertEqual(diff.modified.count, 0)
    }

    func testDetectsAddedItem() {
        let existing = item(path: "/path/existing.plist")
        let new      = item(path: "/path/new.plist")

        let diff = sut.diff(
            before: snapshot([existing]),
            after:  snapshot([existing, new])
        )

        XCTAssertFalse(diff.isEmpty)
        XCTAssertEqual(diff.added.count, 1)
        XCTAssertEqual(diff.added.first?.fullPath, "/path/new.plist")
        XCTAssertEqual(diff.removed.count,  0)
        XCTAssertEqual(diff.modified.count, 0)
    }

    func testDetectsRemovedItem() {
        let a = item(path: "/path/a.plist")
        let b = item(path: "/path/b.plist")

        let diff = sut.diff(
            before: snapshot([a, b]),
            after:  snapshot([a])
        )

        XCTAssertEqual(diff.removed.count, 1)
        XCTAssertEqual(diff.removed.first?.fullPath, "/path/b.plist")
        XCTAssertEqual(diff.added.count,    0)
        XCTAssertEqual(diff.modified.count, 0)
    }

    func testDetectsModifiedItem() {
        let path     = "/path/modified.plist"
        let original = item(path: path, hash: "hash_before")
        let updated  = item(path: path, hash: "hash_after")

        let diff = sut.diff(
            before: snapshot([original]),
            after:  snapshot([updated])
        )

        XCTAssertEqual(diff.modified.count, 1)
        XCTAssertEqual(diff.modified.first?.before.contentsHash, "hash_before")
        XCTAssertEqual(diff.modified.first?.after.contentsHash,  "hash_after")
        XCTAssertEqual(diff.added.count,   0)
        XCTAssertEqual(diff.removed.count, 0)
    }

    func testUnchangedItemNotReported() {
        let same = item(path: "/path/same.plist", hash: "same_hash")

        let diff = sut.diff(
            before: snapshot([same]),
            after:  snapshot([same])
        )

        XCTAssertTrue(diff.isEmpty)
    }

    func testTotalChanges_allThreeTypes() {
        let unchanged       = item(path: "/path/unchanged.plist", hash: "x")
        let added           = item(path: "/path/added.plist",     hash: "y")
        let removed         = item(path: "/path/removed.plist",   hash: "z")
        let beforeModified  = item(path: "/path/modified.plist",  hash: "before")
        let afterModified   = item(path: "/path/modified.plist",  hash: "after")

        let diff = sut.diff(
            before: snapshot([unchanged, removed, beforeModified]),
            after:  snapshot([unchanged, added,   afterModified])
        )

        XCTAssertEqual(diff.added.count,    1)
        XCTAssertEqual(diff.removed.count,  1)
        XCTAssertEqual(diff.modified.count, 1)
        XCTAssertEqual(diff.totalChanges,   3)
    }

    func testAddedItemsSortedByPath() {
        let z = item(path: "/z.plist")
        let a = item(path: "/a.plist")

        let diff = sut.diff(
            before: snapshot([]),
            after:  snapshot([z, a])
        )

        XCTAssertEqual(diff.added.map(\.fullPath), ["/a.plist", "/z.plist"])
    }

    func testMultipleLocations() {
        let agent  = item(path: "/path/agent.plist",  location: .userLaunchAgents)
        let daemon = item(path: "/path/daemon.plist", location: .systemLaunchDaemons)

        let diff = sut.diff(
            before: snapshot([]),
            after:  snapshot([agent, daemon])
        )

        XCTAssertEqual(diff.added.count, 2)
        XCTAssertTrue(diff.added.contains(where: { $0.location == .userLaunchAgents    }))
        XCTAssertTrue(diff.added.contains(where: { $0.location == .systemLaunchDaemons }))
    }
}
