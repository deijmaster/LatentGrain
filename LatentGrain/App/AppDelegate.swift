import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var scanViewModel = ScanViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.aperture",
                                   accessibilityDescription: "LatentGrain")
            button.image?.isTemplate = true
            button.action = #selector(toggleWindow)
            button.target = self
        }
    }

    @objc private func toggleWindow() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    // MARK: - Window

    private func showWindow() {
        if window == nil {
            window = makeWindow()
        }

        guard let window, let button = statusItem?.button else { return }

        // Position just below the status bar button
        if let screen = NSScreen.main {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
            let origin = NSPoint(
                x: buttonFrame.midX - window.frame.width / 2,
                y: buttonFrame.minY - window.frame.height - 4
            )
            let clamped = NSPoint(
                x: min(origin.x, screen.visibleFrame.maxX - window.frame.width),
                y: max(origin.y, screen.visibleFrame.minY)
            )
            window.setFrameOrigin(clamped)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let rootView = ScanView(viewModel: scanViewModel)
            .environmentObject(StorageService())

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        hostingController.view.autoresizingMask = [.width, .height]

        let win = NSWindow(contentViewController: hostingController)
        win.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 480, height: 500))
        win.minSize = NSSize(width: 480, height: 380)
        win.maxSize = NSSize(width: 480, height: 1200)
        win.backgroundColor = NSColor.windowBackgroundColor
        win.isReleasedWhenClosed = false
        win.delegate = self

        // Close button hides instead of terminating
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: win
        )

        return win
    }

    @objc func windowWillClose(_ notification: Notification) {
        // Nothing extra needed — isReleasedWhenClosed = false keeps it alive
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: sender.frame.width, height: frameSize.height)
    }
}
