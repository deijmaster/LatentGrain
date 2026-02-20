import Foundation

/// Communicates with the `LatentGrainHelper` XPC privileged helper.
/// In Phase 1 the helper is a stub; full SMAppService integration is Phase 2.
class HelperService {

    private static let helperBundleID = "com.latentgrain.helper"

    private var connection: NSXPCConnection?

    var isConnected: Bool { connection != nil }

    // MARK: - Lifecycle

    func connect() {
        guard connection == nil else { return }
        let conn = NSXPCConnection(serviceName: Self.helperBundleID)
        conn.remoteObjectInterface = NSXPCInterface(with: LatentGrainXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        self.connection = conn
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Remote calls

    func scanDaemons() async throws -> [String] {
        guard let conn = connection else {
            throw HelperError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? LatentGrainXPCProtocol

            proxy?.scanLocation(PersistenceLocation.systemLaunchDaemons.resolvedPath) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?["paths"] as? [String] ?? [])
                }
            }
        }
    }
}

// MARK: - HelperError

enum HelperError: LocalizedError {
    case notConnected
    case accessDenied
    case invalidPath
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:        return "Privileged helper is not running."
        case .accessDenied:        return "Access denied to privileged location."
        case .invalidPath:         return "The requested path does not exist."
        case .scanFailed(let msg): return "Scan failed: \(msg)"
        }
    }
}
