import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage("launchAtLogin")    private var launchAtLogin    = false
    @AppStorage("autoScanEnabled")  private var autoScanEnabled  = false
    @AppStorage("showMenuBarDot")   private var showMenuBarDot   = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("compactMode")      private var compactMode      = false
    @AppStorage("showAttribution")  private var showAttribution  = true
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
                Toggle("Show status dot in menu bar", isOn: Binding(
                    get: { showMenuBarDot },
                    set: { newValue in withAnimation(.easeInOut(duration: 0.2)) { showMenuBarDot = newValue } }
                ))
                .help("The coloured dot indicates scan activity. Turn off for a minimal menu bar.")

                if showMenuBarDot {
                    LabeledContent("Dot meaning") {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .stroke(Color.green, lineWidth: 1.2)
                                    .frame(width: 8, height: 8)
                                Text("Idle")
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Circle()
                                    .stroke(Color.orange, lineWidth: 1.2)
                                    .frame(width: 8, height: 8)
                                Text("Scanning or unread findings")
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Idle — popover open")
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("Findings present — popover open")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 12))
                    }
                    .transition(.opacity)
                }
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

                LabeledContent("Monitored Locations") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(PersistenceLocation.allCases, id: \.rawValue) { loc in
                            HStack(spacing: 6) {
                                Text(loc.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if loc.requiresElevation {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .help("Requires privileged helper")
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
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
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
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
}
