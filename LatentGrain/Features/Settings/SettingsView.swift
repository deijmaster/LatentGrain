import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {

    @AppStorage("launchAtLogin")    private var launchAtLogin    = false
    @AppStorage("autoScanEnabled")  private var autoScanEnabled  = false
    @AppStorage("showMenuBarDot")   private var showMenuBarDot   = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("compactMode")      private var compactMode      = false
    @AppStorage("showAttribution")  private var showAttribution  = true
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @State private var isFDAGranted: Bool = FDAService.isGranted

    var body: some View {
        Form {
            // MARK: General
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        applyLaunchAtLogin(enabled: newValue)
                    }
                ))
                Toggle("Show scan progress in icon", isOn: Binding(
                    get: { showMenuBarDot },
                    set: { newValue in withAnimation(.easeInOut(duration: 0.2)) { showMenuBarDot = newValue } }
                ))
                .help("The photo area of the menu bar icon fills as you move through the scan lifecycle. Turn off for a clean icon.")

                if showMenuBarDot {
                    LabeledContent("Fill states") {
                        VStack(alignment: .trailing, spacing: 7) {
                            // Armed: bottom third filled
                            HStack(spacing: 6) {
                                FillPreview(fraction: 1.0 / 3.0)
                                Text("Before shot taken")
                                    .foregroundStyle(.secondary)
                            }
                            // Scanning: ~60 % filled (breathing animates in the real icon)
                            HStack(spacing: 6) {
                                FillPreview(fraction: 0.60)
                                Text("Scanning — fill breathes")
                                    .foregroundStyle(.secondary)
                            }
                            // Unread: fully filled
                            HStack(spacing: 6) {
                                FillPreview(fraction: 1.0)
                                Text("Unread findings")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 12, design: .monospaced))
                    }
                    .transition(.opacity)
                }

                Toggle("Check for updates", isOn: $checkForUpdates)
                .help("Checks GitHub weekly for new releases")
            }

            // MARK: Advanced
            Section("Advanced") {
                Toggle("Auto-scan on App Install", isOn: $autoScanEnabled)
                .help("Watches persistence directories in the background and notifies you when something changes")

                Toggle("Show Notifications", isOn: $notificationsEnabled)
                .help("Post a system notification when auto-scan detects changes")

                Toggle("Compact Mode", isOn: $compactMode)
                .help("Replace conversation bubbles with a minimal status view")

                Toggle("Show App Attribution", isOn: $showAttribution)
                .help("Resolve which application owns each persistence item")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Persistence Sources")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ForEach(PersistenceLocation.allCases, id: \.rawValue) { loc in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(loc.displayName)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.primary)
                                    if loc.requiresElevation {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .help("Requires Full Disk Access or helper privileges")
                                    }
                                }
                                Text(loc.resolvedPath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 0)

                            Button {
                                openPersistenceSource(loc)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help("Open in Finder")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // MARK: Privacy
            Section("Privacy") {
                LabeledContent("Full Disk Access") {
                    if isFDAGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Granted")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.orange)
                            Text("Not granted")
                                .foregroundStyle(.secondary)
                            Button("Open Settings →") {
                                FDAService.openFDASettings()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                        .font(.system(size: 12))
                    }
                }
                .help("Needed to scan Background Task Management (/private/var/db/com.apple.backgroundtaskmanagement)")
            }

            // MARK: About
            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onAppear { isFDAGranted = FDAService.isGranted }
        // onAppear only fires when the window first becomes visible.
        // This covers the return-from-System-Settings case: window stays
        // open while the user grants FDA elsewhere, then the app regains
        // focus and the row updates immediately without a close/reopen.
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            isFDAGranted = FDAService.isGranted
        }
    }

    // MARK: - Helpers

    private func applyLaunchAtLogin(enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Surface the error but don't crash — settings will auto-revert next launch.
            print("[LatentGrain] Launch-at-login toggle failed: \(error)")
        }
    }

    private func openPersistenceSource(_ location: PersistenceLocation) {
        let path = location.resolvedPath
        if location.isSingleFile {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } else {
                let parent = (path as NSString).deletingLastPathComponent
                NSWorkspace.shared.open(URL(fileURLWithPath: parent))
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

// MARK: - FillPreview

/// Small polaroid-shaped preview showing a fill level — mirrors the real menu bar indicator.
private struct FillPreview: View {
    let fraction: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            // Faint background representing the empty photo area
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 9, height: 9)
            // Orange fill rising from the bottom
            Rectangle()
                .fill(Color.orange)
                .frame(width: 9, height: 9 * fraction)
        }
        .frame(width: 9, height: 9)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
        .clipped()
    }
}
