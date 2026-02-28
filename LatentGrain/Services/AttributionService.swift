import Foundation
import Security

/// Enriches persistence snapshots with parent-app attribution.
///
/// Four resolution strategies are tried in order (first match wins):
/// 1. Program path walk-up — walk upward from `programPath` to find a `.app` bundle
/// 2. Bundle ID prefix match — match item label against known app bundle IDs
/// 3. Installer receipts — scan `/var/db/receipts/*.plist` for matching install paths
/// 4. Code signature team ID — read signing info from program binary, match against known apps
actor AttributionService {

    // MARK: - App registry

    private struct AppRegistryEntry {
        let appName: String
        let bundleIdentifier: String
        let bundlePath: String
        let teamID: String?
    }

    /// Lazily built on first attribution pass. Keyed by bundle identifier.
    private var registry: [String: AppRegistryEntry]?
    /// Team ID → registry entry for reverse lookups.
    private var teamIDIndex: [String: AppRegistryEntry] = [:]

    // MARK: - Public API

    /// Returns a new snapshot with attribution populated on each item where resolvable.
    func attributeSnapshot(_ snapshot: PersistenceSnapshot) -> PersistenceSnapshot {
        if registry == nil { buildRegistry() }

        let attributed = snapshot.items.map { item -> PersistenceItem in
            if let attribution = resolve(item) {
                return item.withAttribution(attribution)
            }
            return item
        }

        return PersistenceSnapshot(
            id: snapshot.id,
            timestamp: snapshot.timestamp,
            label: snapshot.label,
            items: attributed,
            snapshotHash: snapshot.snapshotHash
        )
    }

    // MARK: - Resolution chain

    private func resolve(_ item: PersistenceItem) -> AppAttribution? {
        if let result = resolveByProgramPathWalkUp(item) { return result }
        if let result = resolveByBundleIDPrefix(item) { return result }
        if let result = resolveByInstallerReceipts(item) { return result }
        if let result = resolveByCodeSignature(item) { return result }
        return nil
    }

    // MARK: Strategy 1 — Program path walk-up

    /// Walk the `programPath` upward until we find a `.app` bundle containing an Info.plist.
    private func resolveByProgramPathWalkUp(_ item: PersistenceItem) -> AppAttribution? {
        guard let programPath = item.programPath else { return nil }
        var url = URL(fileURLWithPath: programPath)

        // Walk up at most 10 levels to avoid infinite loops on weird symlinks
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            guard url.path != "/" else { break }

            if url.pathExtension == "app" {
                return attributionFromAppBundle(at: url)
            }
        }
        return nil
    }

    // MARK: Strategy 2 — Bundle ID prefix match

    /// Parse the item's label as a reverse-domain identifier and match against known app bundle IDs.
    private func resolveByBundleIDPrefix(_ item: PersistenceItem) -> AppAttribution? {
        guard let label = item.label, !label.isEmpty else { return nil }
        guard let registry else { return nil }

        // Try progressively shorter prefixes of the label
        // e.g. "com.google.keystone.agent" → try "com.google.keystone.agent",
        //      "com.google.keystone", "com.google"
        let components = label.split(separator: ".")
        guard components.count >= 2 else { return nil }

        for length in stride(from: components.count, through: 2, by: -1) {
            let prefix = components.prefix(length).joined(separator: ".")
            if let entry = registry[prefix] {
                return makeAttribution(from: entry)
            }
        }

        // Also try matching labels where the app's bundle ID is a prefix of the label
        for (bundleID, entry) in registry {
            if label.hasPrefix(bundleID) {
                return makeAttribution(from: entry)
            }
        }

        return nil
    }

    // MARK: Strategy 3 — Installer receipts

    /// Scan `/var/db/receipts/*.plist` for receipts whose install prefix contains the program path.
    private func resolveByInstallerReceipts(_ item: PersistenceItem) -> AppAttribution? {
        guard let programPath = item.programPath else { return nil }
        let receiptsDir = "/var/db/receipts"

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: receiptsDir) else {
            return nil
        }

        for file in files where file.hasSuffix(".plist") {
            let plistURL = URL(fileURLWithPath: receiptsDir).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let installPrefix = plist["InstallPrefixPath"] as? String,
                  programPath.hasPrefix(installPrefix) else { continue }

            // Try to find the matching app from the receipt's package identifier
            if let pkgID = plist["PackageIdentifier"] as? String,
               let registry {
                // Receipt package IDs often match or are prefixes of app bundle IDs
                for (bundleID, entry) in registry {
                    if bundleID.hasPrefix(pkgID) || pkgID.hasPrefix(bundleID) {
                        return makeAttribution(from: entry)
                    }
                }
            }
        }
        return nil
    }

    // MARK: Strategy 4 — Code signature

    /// Read signing info from the program binary and match the team ID against known apps.
    private func resolveByCodeSignature(_ item: PersistenceItem) -> AppAttribution? {
        guard let programPath = item.programPath else { return nil }
        let url = URL(fileURLWithPath: programPath)

        guard let info = readSigningInfo(from: url) else { return nil }

        // Extract team ID from signing info
        if let teamID = info["teamid"] as? String, !teamID.isEmpty {
            if let entry = teamIDIndex[teamID] {
                return makeAttribution(from: entry)
            }
        }

        return nil
    }

    // MARK: - Registry building

    /// Scan /Applications and ~/Applications one level deep, reading Info.plist and code signature.
    private func buildRegistry() {
        var reg: [String: AppRegistryEntry] = [:]
        var teamIdx: [String: AppRegistryEntry] = [:]

        let searchPaths = [
            "/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        for searchPath in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: searchPath) else { continue }
            for name in contents where name.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: searchPath).appendingPathComponent(name)
                let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")

                guard let data = try? Data(contentsOf: infoPlistURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let bundleID = plist["CFBundleIdentifier"] as? String else { continue }

                let displayName = plist["CFBundleDisplayName"] as? String
                    ?? plist["CFBundleName"] as? String
                    ?? name.replacingOccurrences(of: ".app", with: "")

                let teamID = readTeamID(from: appURL)

                let entry = AppRegistryEntry(
                    appName: displayName,
                    bundleIdentifier: bundleID,
                    bundlePath: appURL.path,
                    teamID: teamID
                )
                reg[bundleID] = entry
                if let teamID { teamIdx[teamID] = entry }
            }
        }

        registry = reg
        teamIDIndex = teamIdx
    }

    /// Read the code-signing team ID from an app bundle.
    private func readTeamID(from appURL: URL) -> String? {
        readSigningInfo(from: appURL)?["teamid"] as? String
    }

    /// Shared helper — creates a SecStaticCode and copies its signing information dictionary.
    private func readSigningInfo(from url: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }

        var cfInfo: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &cfInfo) == errSecSuccess,
              let info = cfInfo as? [String: Any] else { return nil }

        return info
    }

    // MARK: - Helpers

    /// Build an `AppAttribution` from an `.app` bundle's Info.plist and code signature.
    private func attributionFromAppBundle(at appURL: URL) -> AppAttribution? {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let bundleID = plist["CFBundleIdentifier"] as? String
        let displayName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent

        let signingInfo = readSigningInfo(from: appURL)
        let teamID = signingInfo?["teamid"] as? String
        let signingIdentity = signingInfo?[kSecCodeInfoIdentifier as String] as? String

        return AppAttribution(
            appName: displayName,
            bundleIdentifier: bundleID,
            appBundlePath: appURL.path,
            signingTeamID: teamID,
            signingIdentity: signingIdentity
        )
    }

    private func makeAttribution(from entry: AppRegistryEntry) -> AppAttribution {
        AppAttribution(
            appName: entry.appName,
            bundleIdentifier: entry.bundleIdentifier,
            appBundlePath: entry.bundlePath,
            signingTeamID: entry.teamID,
            signingIdentity: nil
        )
    }
}
