import Foundation

/// NSXPCListenerDelegate + XPC protocol implementation for the privileged helper.
final class HelperDelegate: NSObject, NSXPCListenerDelegate, LatentGrainXPCProtocol {

    // MARK: - NSXPCListenerDelegate

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // SECURITY: Verify the connecting process is our signed main app before
        // accepting the connection. Without this, any process on the machine could
        // talk to this helper and use it to enumerate /Library/LaunchDaemons.
        //
        // Phase 2 implementation:
        //   1. Grab the caller's audit token via newConnection.auditToken
        //   2. Call SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData], [], &code)
        //   3. Build a SecRequirement: identifier "com.latentgrain.app"
        //      and anchor apple generic
        //      and certificate leaf[subject.CN] = "<your Developer ID CN>"
        //   4. Call SecCodeCheckValidity(code, [], requirement) — reject if != errSecSuccess
        //
        // DO NOT remove this comment or ship Phase 2 without completing the above.
        #if DEBUG
        // Allow unsigned builds during development only
        #else
        // TODO (Phase 2 — MUST FIX before shipping helper): validate caller identity.
        // Uncomment the guard below once Phase 2 validation is wired up:
        // guard isCallerOurApp(connection: newConnection) else { return false }
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
}

// MARK: - HelperXPCError

/// Errors sent across the XPC boundary (must be NSError-bridgeable).
enum HelperXPCError: Int, Error {
    case accessDenied = 1
    case invalidPath  = 2
    case scanFailed   = 3

    static func scanFailed(_ message: String) -> NSError {
        NSError(
            domain: "com.latentgrain.helper",
            code: HelperXPCError.scanFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
