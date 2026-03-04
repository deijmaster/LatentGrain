import Foundation
import Security
import Darwin

/// NSXPCListenerDelegate + XPC protocol implementation for the privileged helper.
final class HelperDelegate: NSObject, NSXPCListenerDelegate, LatentGrainXPCProtocol {
    private let expectedAppBundleID = "com.latentgrain.app"

    // MARK: - NSXPCListenerDelegate

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        #if DEBUG
        // Keep local development friction low.
        #else
        guard isCallerOurApp(connection: newConnection) else { return false }
        #endif

        newConnection.exportedInterface = NSXPCInterface(with: LatentGrainXPCProtocol.self)
        newConnection.exportedObject    = self
        newConnection.resume()
        return true
    }

    // MARK: - LatentGrainXPCProtocol

    func scanLocation(
        _ path: String,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    ) {
        guard FileManager.default.fileExists(atPath: path) else {
            reply(nil, HelperXPCError.invalidPath)
            return
        }

        do {
            let url      = URL(fileURLWithPath: path)
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let plistPaths = contents
                .filter { $0.pathExtension == "plist" }
                .map(\.path)
            reply(["paths": plistPaths], nil)
        } catch {
            reply(nil, HelperXPCError.scanFailed(error.localizedDescription))
        }
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }

    func disableItem(
        _ path: String,
        label: String,
        domain: String,
        userUID: Int,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    ) {
        let normalizedPath = (path as NSString).standardizingPath
        guard isActionablePath(normalizedPath), !label.isEmpty else {
            reply(nil, HelperXPCError.invalidRequest)
            return
        }

        do {
            let serviceTarget = try makeServiceTarget(label: label, domain: domain, userUID: userUID)
            try runLaunchctl(["disable", serviceTarget], allowFailure: false)
            reply(["status": "disabled"], nil)
        } catch {
            reply(nil, HelperXPCError.actionFailed(error.localizedDescription))
        }
    }

    func quarantineItem(
        _ path: String,
        label: String,
        domain: String,
        userUID: Int,
        quarantineRoot: String,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    ) {
        let normalizedPath = (path as NSString).standardizingPath
        let normalizedQuarantineRoot = (quarantineRoot as NSString).standardizingPath
        guard isActionablePath(normalizedPath),
              isValidQuarantineRoot(normalizedQuarantineRoot),
              !label.isEmpty else {
            reply(nil, HelperXPCError.invalidRequest)
            return
        }

        do {
            let bootoutDomain = try makeBootoutDomain(domain: domain, userUID: userUID)
            _ = try? runLaunchctl(["bootout", bootoutDomain, normalizedPath], allowFailure: true)

            try FileManager.default.createDirectory(
                atPath: normalizedQuarantineRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let destinationPath = uniqueQuarantinePath(
                for: normalizedPath,
                root: normalizedQuarantineRoot
            )
            try FileManager.default.moveItem(atPath: normalizedPath, toPath: destinationPath)
            try persistQuarantineMetadata(
                originalPath: normalizedPath,
                quarantinedPath: destinationPath,
                label: label
            )

            reply([
                "status": "quarantined",
                "quarantinePath": destinationPath
            ], nil)
        } catch {
            reply(nil, HelperXPCError.actionFailed(error.localizedDescription))
        }
    }

    func enableItem(
        _ path: String,
        label: String,
        domain: String,
        userUID: Int,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    ) {
        let normalizedPath = (path as NSString).standardizingPath
        guard isActionablePath(normalizedPath), !label.isEmpty else {
            reply(nil, HelperXPCError.invalidRequest)
            return
        }

        do {
            let serviceTarget = try makeServiceTarget(label: label, domain: domain, userUID: userUID)
            let bootoutDomain = try makeBootoutDomain(domain: domain, userUID: userUID)
            try runLaunchctl(["enable", serviceTarget], allowFailure: false)
            _ = try runLaunchctl(["bootstrap", bootoutDomain, normalizedPath], allowFailure: true)
            reply(["status": "enabled"], nil)
        } catch {
            reply(nil, HelperXPCError.actionFailed(error.localizedDescription))
        }
    }

    func restoreQuarantinedItem(
        originalPath: String,
        quarantinedPath: String,
        label: String,
        domain: String,
        userUID: Int,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    ) {
        let normalizedOriginal = (originalPath as NSString).standardizingPath
        let normalizedQuarantined = (quarantinedPath as NSString).standardizingPath
        guard isActionablePath(normalizedOriginal),
              isValidQuarantineItemPath(normalizedQuarantined),
              !label.isEmpty else {
            reply(nil, HelperXPCError.invalidRequest)
            return
        }

        do {
            let originalParent = (normalizedOriginal as NSString).deletingLastPathComponent
            if !FileManager.default.fileExists(atPath: originalParent) {
                try FileManager.default.createDirectory(atPath: originalParent, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: normalizedOriginal) {
                throw HelperXPCError.actionFailed("Original path already exists: \(normalizedOriginal)")
            }
            try FileManager.default.moveItem(atPath: normalizedQuarantined, toPath: normalizedOriginal)
            let bootoutDomain = try makeBootoutDomain(domain: domain, userUID: userUID)
            let serviceTarget = try makeServiceTarget(label: label, domain: domain, userUID: userUID)
            _ = try runLaunchctl(["enable", serviceTarget], allowFailure: true)
            _ = try runLaunchctl(["bootstrap", bootoutDomain, normalizedOriginal], allowFailure: true)
            reply(["status": "restored"], nil)
        } catch {
            reply(nil, HelperXPCError.actionFailed(error.localizedDescription))
        }
    }

    // MARK: - Launchd action helpers

    private func isActionablePath(_ path: String) -> Bool {
        guard path.hasSuffix(".plist") else { return false }
        if path.hasPrefix("/Library/LaunchDaemons/") { return true }
        if path.hasPrefix("/Library/LaunchAgents/") { return true }
        if path.hasPrefix("/Users/"), path.contains("/Library/LaunchAgents/") { return true }
        return false
    }

    private func isValidQuarantineRoot(_ path: String) -> Bool {
        path.hasPrefix("/Users/") && path.hasSuffix("/Library/Application Support/LatentGrain/Quarantine")
    }

    private func isValidQuarantineItemPath(_ path: String) -> Bool {
        path.hasPrefix("/Users/") &&
        path.contains("/Library/Application Support/LatentGrain/Quarantine/") &&
        path.hasSuffix(".plist")
    }

    private func makeBootoutDomain(domain: String, userUID: Int) throws -> String {
        switch domain {
        case "system":
            return "system"
        case "gui":
            return "gui/\(userUID)"
        default:
            throw HelperXPCError.invalidRequest
        }
    }

    private func makeServiceTarget(label: String, domain: String, userUID: Int) throws -> String {
        switch domain {
        case "system":
            return "system/\(label)"
        case "gui":
            return "gui/\(userUID)/\(label)"
        default:
            throw HelperXPCError.invalidRequest
        }
    }

    @discardableResult
    private func runLaunchctl(_ args: [String], allowFailure: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let output = stderr.isEmpty ? stdout : stderr

        if process.terminationStatus != 0 && !allowFailure {
            throw HelperXPCError.actionFailed(output.isEmpty ? "launchctl exit \(process.terminationStatus)" : output)
        }
        return output
    }

    private func uniqueQuarantinePath(for originalPath: String, root: String) -> String {
        let filename = (originalPath as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let candidate = "\(stem)-\(stamp)"
        return (root as NSString).appendingPathComponent(ext.isEmpty ? candidate : "\(candidate).\(ext)")
    }

    private func persistQuarantineMetadata(
        originalPath: String,
        quarantinedPath: String,
        label: String
    ) throws {
        let metadata: [String: String] = [
            "originalPath": originalPath,
            "quarantinedPath": quarantinedPath,
            "label": label,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let sidecarPath = quarantinedPath + ".json"
        try data.write(to: URL(fileURLWithPath: sidecarPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sidecarPath)
    }

    // MARK: - Caller verification

    private func isCallerOurApp(connection: NSXPCConnection) -> Bool {
        guard let callerCode = codeObjectForCaller(connection),
              let requirement = makeRequirement(bundleID: expectedAppBundleID, teamID: Self.ownTeamIdentifier()) else {
            return false
        }

        let status = SecCodeCheckValidity(callerCode, SecCSFlags(), requirement)
        return status == errSecSuccess
    }

    private static func ownTeamIdentifier() -> String? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func codeObjectForCaller(_ connection: NSXPCConnection) -> SecCode? {
        if let tokenData = auditTokenData(from: connection) {
            let attrs = [kSecGuestAttributeAudit: tokenData] as CFDictionary
            var guest: SecCode?
            let status = SecCodeCopyGuestWithAttributes(nil, attrs, SecCSFlags(), &guest)
            if status == errSecSuccess { return guest }
        }

        // Fallback for SDK/runtime combinations where audit token access is not surfaced.
        var pid = connection.processIdentifier
        let pidData = Data(bytes: &pid, count: MemoryLayout<pid_t>.size)
        let attrs = [kSecGuestAttributePid: pidData] as CFDictionary
        var guest: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attrs, SecCSFlags(), &guest)
        return status == errSecSuccess ? guest : nil
    }

    private func auditTokenData(from connection: NSXPCConnection) -> Data? {
        // `auditToken` isn't exposed uniformly across SDK overlays, so we fetch it
        // via KVC and support both Data and NSValue payload shapes.
        guard let token = connection.value(forKey: "auditToken") else { return nil }
        if let data = token as? Data, !data.isEmpty {
            return data
        }
        if let value = token as? NSValue {
            var audit = audit_token_t()
            value.getValue(&audit)
            return Data(bytes: &audit, count: MemoryLayout<audit_token_t>.size)
        }
        return nil
    }

    private func makeRequirement(bundleID: String, teamID: String?) -> SecRequirement? {
        // Production-signing path: require Apple anchor + matching Team ID.
        // Local ad-hoc builds have no TeamIdentifier, so fall back to bundle-id matching.
        let req: String
        if let teamID, !teamID.isEmpty {
            req = "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        } else {
            req = "identifier \"\(bundleID)\""
        }
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(req as CFString, SecCSFlags(), &requirement)
        guard status == errSecSuccess else { return nil }
        return requirement
    }
}

// MARK: - HelperXPCError

/// Errors sent across the XPC boundary (must be NSError-bridgeable).
enum HelperXPCError: Int, Error {
    case accessDenied = 1
    case invalidPath  = 2
    case scanFailed   = 3
    case invalidRequest = 4
    case actionFailed = 5

    static func scanFailed(_ message: String) -> NSError {
        NSError(
            domain: "com.latentgrain.helper",
            code: HelperXPCError.scanFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    static func actionFailed(_ message: String) -> NSError {
        NSError(
            domain: "com.latentgrain.helper",
            code: HelperXPCError.actionFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
