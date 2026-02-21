import Foundation
import AppKit

/// Checks whether Full Disk Access has been granted to the app.
struct FDAService {
    /// Returns `true` when the app can read the Background Task Management directory,
    /// which requires Full Disk Access on macOS 13+.
    static var isGranted: Bool {
        FileManager.default.isReadableFile(
            atPath: "/private/var/db/com.apple.backgroundtaskmanagement"
        )
    }

    /// Opens System Settings to the Full Disk Access pane and simultaneously reveals
    /// the app in Finder so the user can drag it straight into the list — no navigation
    /// required. The app hides itself first so its floating window doesn't block either
    /// window. The user clicks the menu bar icon to return after granting access.
    static func openFDASettings() {
        // Step out of the way — floating window would otherwise sit above Finder/Settings
        NSApp.hide(nil)
        // Highlight the app in Finder so it's ready to drag into the FDA list
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        // Bring System Settings to the front over Finder
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
