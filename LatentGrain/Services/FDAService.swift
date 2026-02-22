import Foundation
import AppKit

/// Checks whether Full Disk Access has been granted to the app.
struct FDAService {
    /// Returns `true` when Full Disk Access has been granted.
    ///
    /// Uses `/Library/Application Support/com.apple.TCC/TCC.db` as the probe — it is
    /// present on every macOS 10.15+ installation and is definitively FDA-protected.
    /// The BTM directory was unreliable because it may not exist on Macs with no
    /// registered background tasks, producing false negatives.
    ///
    /// We open a FileHandle (no data is read) — standard macOS pattern for FDA detection.
    static var isGranted: Bool {
        let handle = FileHandle(
            forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db"
        )
        handle?.closeFile()
        return handle != nil
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
