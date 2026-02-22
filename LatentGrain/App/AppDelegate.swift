import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var scanViewModel = ScanViewModel()
    private var revealCancellable: AnyCancellable?
    private var iconObservers: Set<AnyCancellable> = []
    private var statusDotView: NSView?
    private var watchService: WatchService?
    private var watchObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupFocusObserver()
        setupIconObservers()
        UNUserNotificationCenter.current().delegate = self

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow()
        } else {
            setupWatchService()
            scanViewModel.recheckFDA()
            scanViewModel.tryLoadPendingDiff()
            Task { await checkForUpdate() }
        }
    }

    private func showOnboardingWindow() {
        let rootView = OnboardingView { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.orderOut(nil)
            self.onboardingWindow = nil
            self.setupWatchService()
            self.scanViewModel.recheckFDA()
            self.scanViewModel.tryLoadPendingDiff()
            Task { await self.checkForUpdate() }
            self.showPopover()
        }
        let controller = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: controller)
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 460, height: 460))
        win.minSize = NSSize(width: 460, height: 460)
        win.maxSize = NSSize(width: 460, height: 460)
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWindow = win

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                self.onboardingWindow = nil
                self.setupWatchService()
                self.scanViewModel.recheckFDA()
                self.scanViewModel.tryLoadPendingDiff()
            }
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
                self?.showPopover()
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

        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        button.image = icon
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        // Dot position is computed dynamically once the button has been laid out,
        // so it stays centred in the photo frame regardless of menu bar height.
        DispatchQueue.main.async { [weak self] in
            self?.addDotOverlay(to: button)
        }
    }

    private func addDotOverlay(to button: NSButton) {
        let buttonSize = button.bounds.size
        guard buttonSize.width > 0, buttonSize.height > 0 else { return }

        // The MenuBarIcon image is always rendered at 18×18pt, centred in the button.
        let imageSize: CGFloat = 18
        let imgX = (buttonSize.width  - imageSize) / 2
        let imgY = (buttonSize.height - imageSize) / 2

        // Photo area centre within the 18pt image (from the generation script geometry):
        //   pad=1 → frame_h=16, frame_w=13, fx=2, fy=1
        //   margin_lr=1, margin_top=1, margin_bot=4 → photo 11×11 at image (3, 2) top-left
        //   centre in image coords (x from left, y from bottom of 18pt image):
        //     x = 3 + 5.5 = 8.5
        //     y = (18 - 2 - 5.5) = 10.5   ← NSView y grows upward
        let photoCentreInImageX: CGFloat = 8.5
        let photoCentreInImageY: CGFloat = 10.5

        let dotSize: CGFloat = 5
        let cx = imgX + photoCentreInImageX
        let cy = imgY + photoCentreInImageY

        let dot = NSView(frame: NSRect(
            x: cx - dotSize / 2,
            y: cy - dotSize / 2,
            width:  dotSize,
            height: dotSize
        ))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        button.addSubview(dot)
        statusDotView = dot
        updateStatusIcon()
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func makePopover() -> NSPopover {
        let rootView = AnyView(
            ScanView(viewModel: scanViewModel, onOpenHistory: { [weak self] in self?.showHistoryWindow() })
                .environmentObject(scanViewModel.storageService)
        )
        let controller = NSHostingController(rootView: rootView)

        let pop = NSPopover()
        pop.contentViewController = controller
        pop.contentSize = NSSize(width: 380, height: 440)
        pop.behavior = .transient
        pop.animates = true
        pop.appearance = NSAppearance(named: .darkAqua)
        pop.delegate = self

        // Resize when diff is revealed.
        // Deferred via async so SwiftUI renders the new isRevealed state first,
        // then the popover container expands around the already-rendered content.
        // Without the defer, NSPopover resizes synchronously mid-runloop, interrupting
        // SwiftUI's pending update — the view re-lays out at the new size but with
        // the old (unrevealed) state still rendered, requiring a second tap.
        revealCancellable = scanViewModel.$isDiffRevealed.sink { [weak pop] revealed in
            DispatchQueue.main.async {
                pop?.contentSize = NSSize(width: 380, height: revealed ? 700 : 440)
            }
        }

        return pop
    }

    private func showPopover() {
        if popover == nil {
            popover = makePopover()
        }
        guard let button = statusItem?.button, let pop = popover else { return }
        if !pop.isShown {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        updateStatusIcon()
    }

    private func togglePopover() {
        if let pop = popover, pop.isShown {
            pop.performClose(nil)
        } else {
            showPopover()
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let infoItem = NSMenuItem(title: "LatentGrain \(version) by deijmaster.", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        let humourItem = NSMenuItem(title: "yes, 40 years in tech made me do this.", action: nil, keyEquivalent: "")
        humourItem.isEnabled = false
        menu.addItem(humourItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open LatentGrain", action: #selector(openWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let recordCount = scanViewModel.storageService.diffRecords.count
        let historyTitle = recordCount > 0
            ? "Detection History (\(recordCount) detection\(recordCount == 1 ? "" : "s"))"
            : "Detection History"
        let historyItem = NSMenuItem(title: historyTitle, action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        menu.addItem(githubItem)

        menu.addItem(.separator())

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

        let proModeOn = UserDefaults.standard.bool(forKey: "proMode")
        let proItem = NSMenuItem(title: "Pro Mode", action: #selector(toggleProMode), keyEquivalent: "p")
        proItem.target = self
        proItem.state = proModeOn ? .on : .off
        menu.addItem(proItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LatentGrain", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openWindow() { showPopover() }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openHistory() { showHistoryWindow() }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/deijmaster/LatentGrain") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleProMode() {
        let current = UserDefaults.standard.bool(forKey: "proMode")
        UserDefaults.standard.set(!current, forKey: "proMode")
    }

    @objc private func openSettings() { showSettingsWindow(nil) }

    // MARK: - History window

    func showHistoryWindow() {
        if let existing = historyWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = HistoryView(onClose: { [weak self] in
            self?.historyWindow?.close()
        })
        .environmentObject(scanViewModel.storageService)

        let controller = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: controller)
        win.title = "Detection History"
        win.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 480, height: 560))
        win.minSize = NSSize(width: 420, height: 400)
        win.maxSize = NSSize(width: 600, height: 900)
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        positionHistoryWindow(win)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.historyWindow = nil }
        }

        historyWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Position history window beside where the popover appears (near the status bar button).
    private func positionHistoryWindow(_ win: NSWindow) {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            win.center()
            return
        }

        let buttonScreenFrame = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let gap: CGFloat = 16
        let hf  = win.frame
        let vis = screen.visibleFrame

        // Hang below the menu bar, aligned to the button
        let y      = vis.maxY - hf.height - 16
        let leftX  = buttonScreenFrame.minX - hf.width - gap
        let rightX = buttonScreenFrame.maxX + gap

        if leftX >= vis.minX {
            win.setFrameOrigin(NSPoint(x: leftX, y: y))
        } else if rightX + hf.width <= vis.maxX {
            win.setFrameOrigin(NSPoint(x: rightX, y: y))
        } else {
            win.center()
        }
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        let controller = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: controller)
        win.title = "LatentGrain Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 420, height: 420))
        win.isReleasedWhenClosed = true
        win.appearance = NSAppearance(named: .darkAqua)
        settingsWindow = win
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Focus observer

    private func setupFocusObserver() {
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
            .combineLatest(scanViewModel.$isDiffRevealed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &iconObservers)
    }

    private func updateStatusIcon() {
        guard let layer = statusDotView?.layer else { return }

        let isActive = scanViewModel.isScanning
            || (scanViewModel.beforeSnapshot != nil && scanViewModel.currentDiff == nil)
            || scanViewModel.hasUnreadDiff
        let dotColor: NSColor = isActive ? .systemOrange : .systemGreen
        let popoverOpen = popover?.isShown ?? false

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        if popoverOpen {
            layer.backgroundColor = dotColor.cgColor
            layer.borderColor     = dotColor.cgColor
            layer.borderWidth     = 0
        } else {
            layer.backgroundColor = CGColor.clear
            layer.borderColor     = dotColor.cgColor
            layer.borderWidth     = 1.5
        }
        CATransaction.commit()
    }

    @objc private func appDidBecomeActive() {
        scanViewModel.recheckFDA()
        let newFDA = FDAService.isGranted
        if newFDA != watchService?.lastKnownFDAState {
            watchService?.restartWithCurrentFDAState()
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        updateStatusIcon()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {

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
            showPopover()
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
