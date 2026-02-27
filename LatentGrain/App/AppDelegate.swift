import AppKit
import SwiftUI
import Combine
import CoreServices
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var timelineWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var scanViewModel = ScanViewModel()
    private var revealCancellable: AnyCancellable?
    private var iconObservers: Set<AnyCancellable> = []
    private var appearanceObserver: NSKeyValueObservation?
    private var watchService: WatchService?
    private var watchObserver: Any?
    private var updateTimer: Timer?
    /// Tracks the FDA state as of the last `appDidBecomeActive` call so we only
    /// restart WatchService when it actually changes.  Kept here on @MainActor
    /// to avoid reading WatchService's internal state from a foreign thread.
    /// Initialized lazily on first access so it reflects the true state at the
    /// moment the app first becomes active, preventing a spurious restart on every
    /// cold launch when FDA is already granted.
    private lazy var lastKnownFDAState: Bool = FDAService.isGranted

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Register with LaunchServices so the app icon appears correctly in
        // System Settings > Privacy > Full Disk Access and in Notification Center.
        // Required for LSUIElement apps and dev builds running from non-standard paths.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        // Explicitly set the app icon — required for LSUIElement apps to show
        // the correct icon in Notification Center and System Settings (FDA list).
        // NSImage(named:) cannot load .appiconset entries — only .imageset — so we
        // ask the OS for the icon through LaunchServices which always resolves it.
        NSApp.applicationIconImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
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
            scheduleUpdateTimer()
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

        win.orderFrontRegardless()
        activateApp()
    }

    private func checkForUpdate() async {
        guard let tag = await UpdateChecker.shared.checkIfDue() else { return }
        scanViewModel.isUpdateAvailable = true
        scanViewModel.latestTag = tag
    }

    private func scheduleUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 7 * 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdate()
            }
        }
    }

    // MARK: - Watch service

    private func setupWatchService() {
        watchService = WatchService(storage: scanViewModel.storageService) { [weak self] diff in
            // Already on @MainActor — WatchService calls onDiff from Task { @MainActor }.
            // No DispatchQueue.main.async needed; keeping it synchronous ensures the popover
            // is shown before postNotification runs, so willPresent correctly suppresses
            // the banner when the user is already looking at the results.
            self?.scanViewModel.injectAndRevealWatchDiff(diff)
            self?.showPopover()
        }
        watchObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.syncWatchService() } }
        syncWatchService()
    }

    private func syncWatchService() {
        let enabled = UserDefaults.standard.bool(forKey: "autoScanEnabled")
        if enabled { watchService?.start() } else { watchService?.stop() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        // Redraw when system appearance flips (light ↔ dark menu bar).
        // KVO callback is nonisolated — hop to MainActor before touching UI state.
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: []) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateStatusIcon() }
        }

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
            ScanView(viewModel: scanViewModel)
                .environmentObject(scanViewModel.storageService)
        )
        let controller = NSHostingController(rootView: rootView)

        let pop = NSPopover()
        pop.contentViewController = controller
        // Open at full height if results are already revealed (e.g. notification tap or pending diff)
        pop.contentSize = NSSize(width: 380, height: scanViewModel.isDiffRevealed ? 700 : 440)
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
            Task { @MainActor [weak pop] in
                guard let pop, pop.isShown else { return }
                pop.contentSize = NSSize(width: 380, height: revealed ? 700 : 440)
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
            activateApp()
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
        openItem.image = NSImage(named: "MenuBarIcon")
        menu.addItem(openItem)

        let timelineItem = NSMenuItem(title: "Persistence Timeline", action: #selector(openTimeline), keyEquivalent: "t")
        timelineItem.target = self
        timelineItem.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)
        menu.addItem(timelineItem)

        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        githubItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(githubItem)

        menu.addItem(.separator())

        let foldersItem = NSMenuItem(title: "Persistence Folders", action: nil, keyEquivalent: "")
        foldersItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let foldersSubmenu = NSMenu()
        for location in PersistenceLocation.allCases {
            let item = NSMenuItem(
                title: location.displayName + (location.requiresElevation ? " (locked)" : ""),
                action: #selector(openFolder(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = location.resolvedPath
            item.image = NSImage(systemSymbolName: location.requiresElevation ? "lock.fill" : "folder", accessibilityDescription: nil)
            foldersSubmenu.addItem(item)
        }
        foldersItem.submenu = foldersSubmenu
        menu.addItem(foldersItem)

        if scanViewModel.isUpdateAvailable, let tag = scanViewModel.latestTag {
            menu.addItem(.separator())
            let updateItem = NSMenuItem(
                title: "Update Available (\(tag))",
                action: #selector(openReleasePage),
                keyEquivalent: ""
            )
            updateItem.target = self
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LatentGrain", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
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

    @objc private func openTimeline() { showTimelineWindow() }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/deijmaster/LatentGrain") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openReleasePage() {
        guard let tag = scanViewModel.latestTag,
              let url = URL(string: "https://github.com/deijmaster/LatentGrain/releases/tag/\(tag)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettings() { showSettingsWindow(nil) }

    // MARK: - Timeline window

    func showTimelineWindow() {
        if let existing = timelineWindow {
            existing.orderFrontRegardless()
            activateApp()
            return
        }

        let rootView = TimelineView()
            .environmentObject(scanViewModel.storageService)

        // Translucent background matching the popover aesthetic:
        // NSVisualEffectView as the container, hosting view embedded inside.
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        let controller = NSViewController()
        controller.view = visualEffect

        let win = NSWindow(contentViewController: controller)
        win.title = "Persistence Timeline"
        win.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 440, height: 640))
        win.minSize = NSSize(width: 400, height: 400)
        win.maxSize = NSSize(width: 520, height: 900)
        win.appearance = NSAppearance(named: .darkAqua)
        win.isReleasedWhenClosed = false
        win.center()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.timelineWindow = nil } }

        timelineWindow = win
        DispatchQueue.main.async {
            win.orderFrontRegardless()
            self.activateApp()
        }
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        if let existing = settingsWindow {
            existing.orderFrontRegardless()
            activateApp()
            return
        }
        let controller = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: controller)
        win.title = "LatentGrain Settings"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .darkAqua)
        win.center()
        settingsWindow = win
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.settingsWindow = nil } }
        // Defer past the current run loop cycle so the menu/popover that
        // triggered this action has fully torn down before we activate.
        DispatchQueue.main.async {
            win.orderFrontRegardless()
            self.activateApp()
        }
    }

    // MARK: - App activation helper

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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
            .combineLatest(scanViewModel.$isDiffRevealed, scanViewModel.$isUpdateAvailable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &iconObservers)

        // Redraw when the "Show status dot" toggle changes in Settings.
        // Wrapped in Task { @MainActor } — same pattern as watchObserver — so the icon
        // update is scheduled asynchronously and never runs inside a CA commit transaction.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateStatusIcon() } }
            .store(in: &iconObservers)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let isActive   = scanViewModel.isScanning
                      || (scanViewModel.beforeSnapshot != nil && scanViewModel.currentDiff == nil)
                      || scanViewModel.hasUnreadDiff
        let dotColor   = isActive ? NSColor.systemOrange : NSColor.systemGreen
        let popoverOpen = popover?.isShown ?? false

        button.image = makeMenuBarImage(dotColor: dotColor, filled: popoverOpen)
    }

    /// Renders the polaroid frame + status dot into a single 18×18pt image.
    /// Dot coordinates are in image space — no button-offset guesswork.
    private func makeMenuBarImage(dotColor: NSColor, filled: Bool) -> NSImage {
        let dim: CGFloat = 18
        let size = NSSize(width: dim, height: dim)
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext,
                  let base = NSImage(named: "MenuBarIcon"),
                  let mask = base.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }

            // Tint the polaroid frame to match the menu bar appearance
            let isDark = NSApp.effectiveAppearance
                .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let frameColor = isDark ? NSColor.white : NSColor.black

            // Clip to the icon's alpha channel, then flood-fill with the tint colour
            ctx.saveGState()
            ctx.clip(to: CGRect(origin: .zero, size: CGSize(width: dim, height: dim)),
                     mask: mask)
            ctx.setFillColor(frameColor.cgColor)
            ctx.fill([CGRect(origin: .zero, size: CGSize(width: dim, height: dim))])
            ctx.restoreGState()

            // Photo area centre in 18pt image coords (x from left, y from bottom):
            //   pad=1 → frame_h=16, frame_w=13 → fx=(18-13)/2=2.5, fy=1 (from top)
            //   margin_lr=1, margin_top=1, margin_bot=4 → photo 11×11, top-left at (3.5, 2)
            //   centre x = 3.5 + 5.5 = 9.0
            //   centre y (NSImage, from bottom) = 18 − 2 − 5.5 = 10.5
            // Respect the "Show status dot" preference — some users prefer a clean menu bar.
            guard UserDefaults.standard.object(forKey: "showMenuBarDot") as? Bool != false else {
                return true
            }

            let cx: CGFloat = 9.0
            let cy: CGFloat = 10.5
            let r:  CGFloat = 2.5   // dot radius

            if filled {
                ctx.setFillColor(dotColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r,
                                           width: r * 2, height: r * 2))
            } else {
                // Ring style when popover is closed
                ctx.setStrokeColor(dotColor.cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokeEllipse(in: CGRect(x: cx - r + 0.6, y: cy - r + 0.6,
                                             width: (r - 0.6) * 2, height: (r - 0.6) * 2))
            }

            return true
        }
    }

    @objc private func appDidBecomeActive() {
        scanViewModel.recheckFDA()
        // Reuse the value just fetched — avoid opening TCC.db a second time.
        let newFDA = scanViewModel.isFDAGranted
        guard newFDA != lastKnownFDAState else { return }
        lastKnownFDAState = newFDA
        // Only restart the FSEvents stream if auto-scan is supposed to be running.
        // Calling restartWithCurrentFDAState() unconditionally was starting the stream
        // even when the user had auto-scan disabled.
        let enabled = UserDefaults.standard.bool(forKey: "autoScanEnabled")
        if enabled {
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
                // Notification tap — reveal results immediately, no "Develop" step.
                scanViewModel.injectAndRevealWatchDiff(diff)
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
        // Suppress the banner if the popover is already open — user can already see the results.
        let options: UNNotificationPresentationOptions = popover?.isShown == true ? [] : [.banner, .sound]
        completionHandler(options)
    }
}
