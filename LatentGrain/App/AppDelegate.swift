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
    private var displayLink: CADisplayLink?
    private var animationAngle: CGFloat = 0
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
            completeOnboarding()
        }
    }

    private func showOnboardingWindow() {
        let rootView = OnboardingView { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.orderOut(nil)
            self.onboardingWindow = nil
            self.completeOnboarding()
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
                self.completeOnboarding()
            }
        }

        win.orderFrontRegardless()
        activateApp()
    }

    private func completeOnboarding() {
        setupWatchService()
        scanViewModel.recheckFDA()
        scanViewModel.tryLoadPendingDiff()
        Task { await checkForUpdate() }
        scheduleUpdateTimer()
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
        watchService = WatchService(
            storage: scanViewModel.storageService,
            isUIVisible: { [weak self] in self?.popover?.isShown == true }
        ) { [weak self] diff in
            // Already on @MainActor — WatchService calls onDiff from Task { @MainActor }.
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
        pop.contentSize = NSSize(width: 440, height: scanViewModel.isDiffRevealed ? 700 : 440)
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
                pop.contentSize = NSSize(width: 440, height: revealed ? 700 : 440)
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

        let infoItem = NSMenuItem(title: "LatentGrain by deijmaster.", action: nil, keyEquivalent: "")
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
        win.setContentSize(NSSize(width: 1140, height: 740))
        win.minSize = NSSize(width: 980, height: 560)
        win.maxSize = NSSize(width: 1700, height: 1100)
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

    /// Four distinct visual states — each has its own shape vocabulary, not just a colour swap.
    private enum LifecycleState: Equatable {
        case idle       // No indicator — silence communicates "all clear"
        case armed      // Before snapshot taken, waiting for "after" — static open arc
        case scanning   // Active scan in progress — rotating arc driven by display link
        case unread     // Diff exists and has not been revealed — solid filled dot
    }

    private var lifecycleState: LifecycleState {
        if scanViewModel.isScanning                                          { return .scanning }
        if scanViewModel.hasUnreadDiff                                       { return .unread   }
        if scanViewModel.beforeSnapshot != nil, scanViewModel.currentDiff == nil { return .armed }
        return .idle
    }

    private func setupIconObservers() {
        scanViewModel.$isScanning
            .combineLatest(scanViewModel.$beforeSnapshot, scanViewModel.$currentDiff)
            .combineLatest(scanViewModel.$isDiffRevealed, scanViewModel.$isUpdateAvailable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &iconObservers)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateStatusIcon() } }
            .store(in: &iconObservers)
    }

    // MARK: Display link (only active while scanning)

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = NSScreen.main?.displayLink(target: self, selector: #selector(displayLinkTick(_:)))
        // 24-30 fps is plenty for an 18 pt icon — saves battery vs ProMotion.
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        link?.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkTick(_ link: CADisplayLink) {
        // Drive fill breathing from absolute time — no drift accumulation.
        // 0.35 cycles/sec ≈ 2.9 s per breath: calm, not frantic.
        animationAngle = CGFloat(link.targetTimestamp) * 2 * .pi * 0.35
        statusItem?.button?.image = makeMenuBarImage(state: .scanning)
    }

    // MARK: Icon update

    private func updateStatusIcon() {
        let state = lifecycleState

        if state == .scanning {
            startDisplayLink()
            return  // display link drives redraws for this state
        }

        stopDisplayLink()
        guard let button = statusItem?.button else { return }
        button.image = makeMenuBarImage(state: state)
    }

    /// Renders the polaroid icon with a rising fill inside the photo area.
    /// Drawing order matters: fill first (under the transparent photo area),
    /// then the frame mask on top — the photo area is transparent in the icon
    /// so the frame never paints over the fill.
    ///
    /// Photo area geometry in 18×18 pt NSImage space (y-up, origin bottom-left):
    ///   x: 3.5 → 14.5  (width 11 pt)
    ///   y: 5.0 → 16.0  (height 11 pt — 4 pt bottom margin = polaroid white strip)
    private func makeMenuBarImage(state: LifecycleState) -> NSImage {
        let angle         = animationAngle
        let showIndicator = UserDefaults.standard.object(forKey: "showMenuBarDot") as? Bool != false
        let dim: CGFloat  = 18

        return NSImage(size: NSSize(width: dim, height: dim), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext,
                  let base = NSImage(named: "MenuBarIcon"),
                  let mask = base.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }

            let isDark = NSApp.effectiveAppearance
                .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let frameColor = isDark ? NSColor.white : NSColor.black

            // Compute what fraction of the photo area to fill
            let fillFraction: CGFloat
            switch (state, showIndicator) {
            case (_, false), (.idle, _):
                fillFraction = 0
            case (.armed, _):
                // Bottom third filled — "baseline snapshot loaded, waiting for after"
                fillFraction = 1.0 / 3.0
            case (.scanning, _):
                // Breathe between 30 % and 90 % — honest "working" signal, no false progress
                fillFraction = 0.30 + 0.60 * (0.5 + 0.5 * sin(angle))
            case (.unread, _):
                // Fully filled — "something is ready to develop"
                fillFraction = 1.0
            }

            // 1. Fill rises from the bottom of the photo area upward
            if fillFraction > 0 {
                let fillRect = CGRect(x: 3.5,
                                     y: 5.0,
                                     width:  11.0,
                                     height: 11.0 * fillFraction)
                ctx.setFillColor(NSColor.systemOrange.cgColor)
                ctx.fill([fillRect])
            }

            // 2. Draw polaroid frame on top, clipped to icon alpha channel.
            //    The photo area is transparent in the mask so the frame flood-fill
            //    never covers the orange fill drawn above.
            ctx.saveGState()
            ctx.clip(to: CGRect(origin: .zero, size: CGSize(width: dim, height: dim)), mask: mask)
            ctx.setFillColor(frameColor.cgColor)
            ctx.fill([CGRect(origin: .zero, size: CGSize(width: dim, height: dim))])
            ctx.restoreGState()

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
