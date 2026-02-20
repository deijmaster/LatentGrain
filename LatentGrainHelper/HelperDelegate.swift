import Foundation

/// NSXPCListenerDelegate + XPC protocol implementation for the privileged helper.
final class HelperDelegate: NSObject, NSXPCListenerDelegate, LatentGrainXPCProtocol {

    // MARK: - NSXPCListenerDelegate

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // TODO (Phase 2): validate auditing token / code-signing identity of caller.
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
