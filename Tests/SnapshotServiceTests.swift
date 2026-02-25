import XCTest
@testable import LatentGrain

final class SnapshotServiceTests: XCTestCase {

    // MARK: - Setup / teardown

    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LatentGrainTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - FileHasher tests

    func testHashIsConsistentForSameContent() {
        let hash1 = FileHasher.sha256(of: Data("hello world".utf8))
        let hash2 = FileHasher.sha256(of: Data("hello world".utf8))
        XCTAssertEqual(hash1, hash2)
    }

    func testHashDiffersForDifferentContent() {
        let hash1 = FileHasher.sha256(of: Data("content_A".utf8))
        let hash2 = FileHasher.sha256(of: Data("content_B".utf8))
        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashOfFileMatchesHashOfSameData() throws {
        let content = "plist bytes"
        let url     = tempDir.appendingPathComponent("test.plist")
        try content.write(to: url, atomically: true, encoding: .utf8)

        let fileHash = FileHasher.sha256(of: url)
        let dataHash = FileHasher.sha256(of: Data(content.utf8))
        XCTAssertEqual(fileHash, dataHash)
    }

    func testHashReturnsNilForMissingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/file.plist")
        XCTAssertNil(FileHasher.sha256(of: missing))
    }

    // MARK: - PlistParser tests

    func testParserExtractsLabel() throws {
        let url = try writePlist("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.example.agent</string>
            <key>RunAtLoad</key><true/>
        </dict></plist>
        """, name: "label_test.plist")

        let info = PlistParser.parse(at: url)
        XCTAssertEqual(info.label, "com.example.agent")
        XCTAssertEqual(info.runAtLoad, true)
    }

    func testParserExtractsProgramArguments() throws {
        let url = try writePlist("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.example.args</string>
            <key>ProgramArguments</key>
            <array><string>/usr/bin/myapp</string><string>--flag</string></array>
        </dict></plist>
        """, name: "args_test.plist")

        let info = PlistParser.parse(at: url)
        XCTAssertEqual(info.programPath, "/usr/bin/myapp")
    }

    func testParserExtractsProgramKey() throws {
        let url = try writePlist("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.example.program</string>
            <key>Program</key><string>/usr/local/bin/daemon</string>
        </dict></plist>
        """, name: "program_test.plist")

        let info = PlistParser.parse(at: url)
        XCTAssertEqual(info.programPath, "/usr/local/bin/daemon")
    }

    func testParserExtractsKeepAliveBool() throws {
        let url = try writePlist("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>Label</key><string>com.example.ka</string>
            <key>KeepAlive</key><true/>
        </dict></plist>
        """, name: "keepalive_test.plist")

        let info = PlistParser.parse(at: url)
        XCTAssertEqual(info.keepAlive, true)
    }

    func testParserHandlesMalformedPlist() throws {
        let url = tempDir.appendingPathComponent("bad.plist")
        try "this is not a plist".write(to: url, atomically: true, encoding: .utf8)

        let info = PlistParser.parse(at: url)
        XCTAssertNil(info.label)
        XCTAssertNil(info.programPath)
    }

    // MARK: - PersistenceLocation tests

    func testUserLaunchAgentsPathContainsLibrary() {
        let path = PersistenceLocation.userLaunchAgents.resolvedPath
        XCTAssertTrue(path.contains("Library/LaunchAgents"))
        XCTAssertFalse(path.hasPrefix("~"))
    }

    func testSystemLocationsRequireElevation() {
        XCTAssertTrue(PersistenceLocation.systemLaunchDaemons.requiresElevation)
        XCTAssertTrue(PersistenceLocation.backgroundTaskMgmt.requiresElevation)
    }

    func testUserLocationsDoNotRequireElevation() {
        XCTAssertFalse(PersistenceLocation.userLaunchAgents.requiresElevation)
        XCTAssertFalse(PersistenceLocation.systemLaunchAgents.requiresElevation)
        XCTAssertFalse(PersistenceLocation.systemExtensions.requiresElevation)
    }

    // MARK: - Helpers

    @discardableResult
    private func writePlist(_ content: String, name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
