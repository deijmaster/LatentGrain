import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage("launchAtLogin")    private var launchAtLogin    = false
    @AppStorage("autoScanEnabled")  private var autoScanEnabled  = false

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
            }

            // MARK: Scanning
            Section("Scanning") {
                Toggle("Auto-scan on App Install  (Premium)", isOn: .constant(false))
                    .disabled(true)
                    .help("Detects persistence changes automatically — Premium feature")

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
                Button("Request Full Disk Access…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
                    NSWorkspace.shared.open(url)
                }
                .help("Needed to scan /Library/LaunchDaemons and Background Task Management")
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
