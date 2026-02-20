import SwiftUI

@main
struct LatentGrainApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (Cmd-,)
        Settings {
            SettingsView()
        }
    }
}
