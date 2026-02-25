import Foundation

/// Protocol defining the XPC interface between the main app and the privileged helper.
/// Both targets must compile this file.
@objc protocol LatentGrainXPCProtocol {

    /// Scan a persistence location that requires elevated access.
    /// Reply contains a dictionary with key "paths" → [String], or an error.
    func scanLocation(
        _ path: String,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    )

    /// Returns the helper's version string for diagnostics.
    func getVersion(withReply reply: @escaping (String) -> Void)
}
