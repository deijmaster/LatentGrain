import Foundation

/// Scans for macOS configuration profiles by shelling out to `/usr/bin/profiles`.
actor ProfileScanService {

    private let profilesBinary = "/usr/bin/profiles"
    private let processTimeout: TimeInterval = 10

    // MARK: - Public API

    /// Scan all installed configuration profiles and return them as `PersistenceItem`s.
    /// Also includes a sentinel enrollment-status item so MDM enrollment changes appear in diffs.
    func scanProfiles() async -> [PersistenceItem] {
        var items: [PersistenceItem] = []

        // 1. Scan installed profiles
        if let xmlData = await runProcess(arguments: ["show", "-output", "stdout-xml"]) {
            let profiles = ProfileParser.parseProfilesXML(xmlData)
            for profile in profiles {
                items.append(makeItem(from: profile))
            }
        }

        // 2. Add sentinel enrollment-status item
        if let enrollmentItem = await scanEnrollmentStatus() {
            items.append(enrollmentItem)
        }

        return items
    }

    /// Check MDM enrollment status.
    func checkEnrollmentStatus() async -> MDMEnrollmentStatus? {
        guard let data = await runProcess(arguments: ["status", "-type", "enrollment"]) else {
            return nil
        }
        return ProfileParser.parseEnrollmentOutput(data)
    }

    // MARK: - Private

    private func scanEnrollmentStatus() async -> PersistenceItem? {
        guard let status = await checkEnrollmentStatus(),
              status.isEnrolled else { return nil }

        let statusString = status.summary
        let statusData = Data(statusString.utf8)

        return PersistenceItem(
            id: UUID(),
            filename: "MDM Enrollment Status",
            fullPath: "configProfiles://mdm-enrollment-status",
            location: .configurationProfiles,
            modificationDate: Date(),
            fileSize: Int64(statusData.count),
            contentsHash: FileHasher.sha256(of: statusData),
            label: statusString,
            programPath: nil,
            runAtLoad: nil,
            keepAlive: nil,
            attribution: nil
        )
    }

    private func makeItem(from profile: ProfileInfo) -> PersistenceItem {
        PersistenceItem(
            id: UUID(),
            filename: profile.profileIdentifier,
            fullPath: "configProfiles://\(profile.profileIdentifier)",
            location: .configurationProfiles,
            modificationDate: profile.installDate ?? Date(),
            fileSize: Int64(profile.profileData.count),
            contentsHash: FileHasher.sha256(of: profile.profileData),
            label: profile.displayName,
            programPath: profile.organization,
            runAtLoad: profile.isMDMManaged ? true : nil,
            keepAlive: nil,
            attribution: nil
        )
    }

    /// Run `/usr/bin/profiles` with given arguments and return stdout data.
    /// Returns `nil` on timeout or non-zero exit.
    private func runProcess(arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: profilesBinary)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()   // Discard stderr

            // Timeout watchdog
            let workItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + processTimeout,
                execute: workItem
            )

            do {
                try process.run()
                process.waitUntilExit()
                workItem.cancel()

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            } catch {
                workItem.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}
