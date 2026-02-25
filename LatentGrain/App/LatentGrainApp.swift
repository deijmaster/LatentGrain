import SwiftUI

@main
struct LatentGrainApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene is required to satisfy the Scene protocol, but SettingsView is
        // managed entirely by AppDelegate.showSettingsWindow — a manual NSWindow with
        // explicit darkAqua appearance and sizing. Having SettingsView() here AND in the
        // AppDelegate window created two competing NSHostingViews sharing the same SwiftUI
        // view renderer graph, causing NSHostingView dealloc corruption (SIGSEGV/SIGABRT
        // in _NSWindowTransformAnimation and DisplayList.ViewUpdater.ViewCache).
        // EmptyView() satisfies the compiler. The scene's window is never shown because
        // NSApp.setActivationPolicy(.accessory) removes the menu bar (no Cmd+, shortcut).
        Settings {
            EmptyView()
        }
    }
}
