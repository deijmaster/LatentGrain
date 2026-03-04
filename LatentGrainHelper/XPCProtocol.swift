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

    /// Disables a launchd service by label without moving its plist.
    func disableItem(
        _ path: String,
        label: String,
        domain: String,
        userUID: Int,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    )

    /// Boots out then moves a plist into a quarantine directory.
    func quarantineItem(
        _ path: String,
        label: String,
        domain: String,
        userUID: Int,
        quarantineRoot: String,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    )

    /// Reverses `disableItem` by enabling and attempting to bootstrap.
    func enableItem(
        _ path: String,
        label: String,
        domain: String,
        userUID: Int,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    )

    /// Reverses `quarantineItem` by moving the plist back and bootstrapping it.
    func restoreQuarantinedItem(
        originalPath: String,
        quarantinedPath: String,
        label: String,
        domain: String,
        userUID: Int,
        withReply reply: @escaping ([String: Any]?, Error?) -> Void
    )
}
