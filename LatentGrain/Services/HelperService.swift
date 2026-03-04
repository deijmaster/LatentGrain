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

    private func ensureConnected() {
        if connection == nil { connect() }
    }

    func scanDaemons() async throws -> [String] {
        ensureConnected()
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

    func disableItem(path: String, label: String, domain: String, userUID: Int) async throws {
        ensureConnected()
        guard let conn = connection else {
            throw HelperError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? LatentGrainXPCProtocol

            proxy?.disableItem(path, label: label, domain: domain, userUID: userUID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func quarantineItem(
        path: String,
        label: String,
        domain: String,
        userUID: Int,
        quarantineRoot: String
    ) async throws -> String? {
        ensureConnected()
        guard let conn = connection else {
            throw HelperError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? LatentGrainXPCProtocol

            proxy?.quarantineItem(
                path,
                label: label,
                domain: domain,
                userUID: userUID,
                quarantineRoot: quarantineRoot
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?["quarantinePath"] as? String)
                }
            }
        }
    }

    func enableItem(path: String, label: String, domain: String, userUID: Int) async throws {
        ensureConnected()
        guard let conn = connection else {
            throw HelperError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? LatentGrainXPCProtocol

            proxy?.enableItem(path, label: label, domain: domain, userUID: userUID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func restoreQuarantinedItem(
        originalPath: String,
        quarantinedPath: String,
        label: String,
        domain: String,
        userUID: Int
    ) async throws {
        ensureConnected()
        guard let conn = connection else {
            throw HelperError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as? LatentGrainXPCProtocol

            proxy?.restoreQuarantinedItem(
                originalPath: originalPath,
                quarantinedPath: quarantinedPath,
                label: label,
                domain: domain,
                userUID: userUID
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
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
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:        return "Privileged helper is not running."
        case .accessDenied:        return "Access denied to privileged location."
        case .invalidPath:         return "The requested path does not exist."
        case .scanFailed(let msg): return "Scan failed: \(msg)"
        case .actionFailed(let msg): return "Action failed: \(msg)"
        }
    }
}
