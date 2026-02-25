import Foundation
import CryptoKit

/// Utility for computing SHA-256 hashes of files and raw data.
enum FileHasher {

    /// Returns the lowercase hex SHA-256 of a file's contents, or `nil` on read failure.
    static func sha256(of fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return sha256(of: data)
    }

    /// Returns the lowercase hex SHA-256 of raw bytes.
    static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
