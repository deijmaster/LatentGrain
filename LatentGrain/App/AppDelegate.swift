import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var scanViewModel = ScanViewModel()
    private var revealObserver: Any?
    private var iconObservers: Set<AnyCancellable> = []
    private var statusDotView: NSView?
    private var watchService: WatchService?
    private var watchObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupFocusObservers()
        setupIconObservers()
        setupWatchService()
        UNUserNotificationCenter.current().delegate = self
        Task { await checkForUpdate() }
    }

    private func checkForUpdate() async {
        guard let tag = await UpdateChecker.shared.fetchLatestTagIfNewer() else { return }
        scanViewModel.isUpdateAvailable = true
        scanViewModel.latestTag = tag
    }

    // MARK: - Watch service

    private func setupWatchService() {
        watchService = WatchService(storage: scanViewModel.storageService) { [weak self] diff in
            DispatchQueue.main.async {
                self?.scanViewModel.injectWatchDiff(diff)
                self?.showWindow()
            }
        }
        watchObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.syncWatchService() } }
        syncWatchService()
    }

    private func syncWatchService() {
        let enabled = UserDefaults.standard.bool(forKey: "autoScanEnabled")
        let premium = UserDefaults.standard.bool(forKey: "proMode")
        if enabled && premium { watchService?.start() } else { watchService?.stop() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        button.image = NSImage(systemSymbolName: "camera.aperture",
                               accessibilityDescription: "LatentGrain")
        button.image?.isTemplate = true
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        // Dot overlay — sits center-right of the icon, colour updated by updateStatusIcon()
        let dot = NSView(frame: NSRect(x: 12, y: 5, width: 7, height: 7))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        button.addSubview(dot)
        statusDotView = dot
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggleWindow()
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()

        // App info header
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let infoItem = NSMenuItem(title: "LatentGrain \(version) by deijmaster.", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        let humourItem = NSMenuItem(title: "yes, 40 years in tech made me do this.", action: nil, keyEquivalent: "")
        humourItem.isEnabled = false
        menu.addItem(humourItem)

        menu.addItem(.separator())

        // Open window
        let openItem = NSMenuItem(title: "Open LatentGrain", action: #selector(openWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        // GitHub
        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        menu.addItem(githubItem)

        menu.addItem(.separator())

        // Folders submenu
        let foldersItem = NSMenuItem(title: "Persistence Folders", action: nil, keyEquivalent: "")
        let foldersSubmenu = NSMenu()
        for location in PersistenceLocation.allCases {
            let item = NSMenuItem(
                title: location.displayName + (location.requiresElevation ? " (locked)" : ""),
                action: #selector(openFolder(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = location.resolvedPath
            foldersSubmenu.addItem(item)
        }
        foldersItem.submenu = foldersSubmenu
        menu.addItem(foldersItem)

        menu.addItem(.separator())

        // Pro Mode toggle
        let proModeOn = UserDefaults.standard.bool(forKey: "proMode")
        let proItem = NSMenuItem(title: "Pro Mode", action: #selector(toggleProMode), keyEquivalent: "p")
        proItem.target = self
        proItem.state = proModeOn ? .on : .off
        menu.addItem(proItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit LatentGrain", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Remove after showing so left click still works
    }

    @objc private func openWindow() {
        showWindow()
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/deijmaster/LatentGrain") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleProMode() {
        let current = UserDefaults.standard.bool(forKey: "proMode")
        UserDefaults.standard.set(!current, forKey: "proMode")
    }

    @objc private func openSettings() {
        showSettingsWindow(nil)
    }

    // Override SwiftUI's injected showSettingsWindow: so all settings routing
    // — whether from our menu item, ⌘,, or the SwiftUI responder chain —
    // goes through our own NSWindow instead of the Settings scene.
    @objc func showSettingsWindow(_ sender: Any?) {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: controller)
            win.title = "LatentGrain Settings"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 420, height: 420))
            win.isReleasedWhenClosed = false
            win.appearance = NSAppearance(named: .darkAqua)
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Window toggle

    @objc private func toggleWindow() {
        if let window, window.isVisible {
            window.orderOut(nil)
            updateStatusIcon()
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - window.frame.width - 16
            let y = screen.visibleFrame.maxY - window.frame.height - 16
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }
        updateStatusIcon()
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
        win.setContentSize(NSSize(width: 480, height: 460))
        win.minSize = NSSize(width: 480, height: 360)
        win.maxSize = NSSize(width: 480, height: 1200)
        win.backgroundColor = NSColor.windowBackgroundColor
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self

        // Expand window when results are revealed
        revealObserver = scanViewModel.$isDiffRevealed.sink { [weak win] revealed in
            guard let win else { return }
            let targetHeight: CGFloat = revealed ? 740 : 500
            var frame = win.frame
            let delta = targetHeight - frame.height
            frame.origin.y -= delta
            frame.size.height = targetHeight
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                win.animator().setFrame(frame, display: true)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: win
        )

        return win
    }

    @objc func windowWillClose(_ notification: Notification) {
        updateStatusIcon()
    }

    // MARK: - Focus fade

    private func setupFocusObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - Icon state

    private func setupIconObservers() {
        scanViewModel.$isScanning
            .combineLatest(scanViewModel.$beforeSnapshot, scanViewModel.$currentDiff)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &iconObservers)
    }

    private func updateStatusIcon() {
        guard let layer = statusDotView?.layer else { return }

        let isActive = scanViewModel.isScanning || (scanViewModel.beforeSnapshot != nil && scanViewModel.currentDiff == nil)
        let dotColor: NSColor = isActive ? .systemOrange : .systemGreen
        let windowOpen = window?.isVisible ?? false

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        if windowOpen {
            // Filled dot — window is open
            layer.backgroundColor = dotColor.cgColor
            layer.borderColor = dotColor.cgColor
            layer.borderWidth = 0
        } else {
            // Ring dot — app running, window closed
            layer.backgroundColor = CGColor.clear
            layer.borderColor = dotColor.cgColor
            layer.borderWidth = 1.5
        }
        CATransaction.commit()
    }

    @objc private func appDidResignActive() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0.82
        }
    }

    @objc private func appDidBecomeActive() {
        scanViewModel.recheckFDA()
        let newFDA = FDAService.isGranted
        if newFDA != watchService?.lastKnownFDAState {
            watchService?.restartWithCurrentFDAState()
        }
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1.0
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: sender.frame.width, height: frameSize.height)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {

    /// Called when the user taps the notification — show the window with the pending diff.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["action"] as? String == "showDiff" {
            if let diff = watchService?.pendingDiff {
                scanViewModel.injectWatchDiff(diff)
            }
            watchService?.clearPendingDiff()
            showWindow()
        }
        completionHandler()
    }

    /// Show banner + play sound even when the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
