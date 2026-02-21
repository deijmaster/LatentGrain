import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage("launchAtLogin")    private var launchAtLogin    = false
    @AppStorage("autoScanEnabled")  private var autoScanEnabled  = false
    @AppStorage("proMode")          private var proMode          = false

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
                Toggle("Pro Mode", isOn: $proMode)
                    .help("Skip the guided chat — just the step indicator and action buttons.")
            }

            // MARK: Scanning
            Section("Scanning") {
                Toggle(isOn: $autoScanEnabled) {
                    HStack(spacing: 6) {
                        Text("Auto-scan on App Install")
                        Text("PREMIUM")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
                .disabled(!proMode)
                .onChange(of: autoScanEnabled) { if $0 && !proMode { autoScanEnabled = false } }
                .help("Watches persistence directories in the background and notifies you when something changes — Premium feature")

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
                    if FDAService.isGranted {
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
                LabeledContent("Website") {
                    Link("latentgrain.app", destination: URL(string: "https://latentgrain.app")!)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
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
