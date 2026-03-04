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

    /// Resolves the XPC proxy and hands it to `body`, eliminating boilerplate
    /// connection setup from every remote call site.
    private func withProxy<T>(
        _ body: @escaping (LatentGrainXPCProtocol, CheckedContinuation<T, Error>) -> Void
    ) async throws -> T {
        ensureConnected()
        guard let conn = connection else { throw HelperError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let proxy = proxy as? LatentGrainXPCProtocol else {
                continuation.resume(throwing: HelperError.notConnected)
                return
            }
            body(proxy, continuation)
        }
    }

    /// Void-returning variant — Swift cannot infer `T = Void` from the call site.
    private func withProxyVoid(
        _ body: @escaping (LatentGrainXPCProtocol, CheckedContinuation<Void, Error>) -> Void
    ) async throws {
        ensureConnected()
        guard let conn = connection else { throw HelperError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let proxy = proxy as? LatentGrainXPCProtocol else {
                continuation.resume(throwing: HelperError.notConnected)
                return
            }
            body(proxy, continuation)
        }
    }


    func scanDaemons() async throws -> [String] {
        try await withProxy { proxy, continuation in
            proxy.scanLocation(PersistenceLocation.systemLaunchDaemons.resolvedPath) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?["paths"] as? [String] ?? []) }
            }
        }
    }

    func disableItem(path: String, label: String, domain: String, userUID: Int) async throws {
        try await withProxyVoid { proxy, continuation in
            proxy.disableItem(path, label: label, domain: domain, userUID: userUID) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
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
        try await withProxy { proxy, continuation in
            proxy.quarantineItem(
                path,
                label: label,
                domain: domain,
                userUID: userUID,
                quarantineRoot: quarantineRoot
            ) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?["quarantinePath"] as? String) }
            }
        }
    }

    func enableItem(path: String, label: String, domain: String, userUID: Int) async throws {
        try await withProxyVoid { proxy, continuation in
            proxy.enableItem(path, label: label, domain: domain, userUID: userUID) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
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
        try await withProxyVoid { proxy, continuation in
            proxy.restoreQuarantinedItem(
                originalPath: originalPath,
                quarantinedPath: quarantinedPath,
                label: label,
                domain: domain,
                userUID: userUID
            ) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
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
