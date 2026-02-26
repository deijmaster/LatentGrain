import SwiftUI
import AppKit

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step = 0
    @State private var isFDAGranted = FDAService.isGranted
    @State private var skippedFDA = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0:
                    WelcomeStep()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                case 1:
                    HowItWorksStep()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                case 2:
                    AutoScanStep()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                case 3:
                    FDAStep(isFDAGranted: $isFDAGranted)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                case 4:
                    ReadyStep(onComplete: completeOnboarding)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 460, height: 460)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            isFDAGranted = FDAService.isGranted
        }
        // Auto-advance to the Ready step the moment FDA is granted — so when the app
        // un-hides after the user returns from System Settings, they see "You're set up!"
        // rather than landing back on the FDA step and having to tap Continue manually.
        .onChange(of: isFDAGranted) { granted in
            if granted && step == 3 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 4 }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if step == 3 && !isFDAGranted && !skippedFDA {
                Button("Skip for now") { skippedFDA = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12, design: .monospaced))
                    .focusable(false)
                    .padding(.bottom, 8)
            }

            Divider().opacity(0.3)

            ZStack {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 5, height: 5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
                    }
                }

                HStack {
                    if step > 0 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step -= 1 }
                        } label: {
                            NavButton(label: "Back", direction: .back)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    Spacer()
                    if step < 4 { ctaButton }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var ctaButton: some View {
        switch step {
        case 0:
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 1 }
            } label: { NavButton(label: "How it works", direction: .forward) }
            .buttonStyle(.plain).focusable(false)
        case 1:
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 2 }
            } label: { NavButton(label: "Watch mode", direction: .forward) }
            .buttonStyle(.plain).focusable(false)
        case 2:
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 3 }
            } label: { NavButton(label: "One permission", direction: .forward) }
            .buttonStyle(.plain).focusable(false)
        case 3:
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 4 }
            } label: {
                NavButton(label: "Continue", direction: .forward,
                          disabled: !(isFDAGranted || skippedFDA))
            }
            .buttonStyle(.plain).focusable(false)
            .disabled(!(isFDAGranted || skippedFDA))
        default:
            EmptyView()
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            // Real app icon — same polaroid the user sees in the menu bar
            // NSImage(named:) can't load .appiconset — use NSWorkspace icon lookup instead.
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

            Spacer().frame(height: 14)

            Text("Meet LatentGrain")
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Spacer().frame(height: 10)

            Text("macOS lets apps install background agents that run silently — even when the app is closed. LatentGrain photographs your persistence layer before and after installs, so you always know exactly what's running on your Mac.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer()
        }
        .padding(.top, 32)
        .padding(.horizontal, 32)
    }
}

// MARK: - Step 1: How it works

private struct HowItWorksStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("How it works")
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Spacer().frame(height: 16)

            VStack(spacing: 0) {
                OnboardingRow(
                    icon: "camera.shutter.button.fill",
                    label: "Shoot Before",
                    description: "Snapshot your Mac's current persistence state"
                )
                .padding(.horizontal, 14).padding(.vertical, 11)

                Divider().padding(.horizontal, 14)

                OnboardingRow(
                    icon: "arrow.down.circle.fill",
                    label: "Install anything",
                    description: "Install an app, a tool, or a system update"
                )
                .padding(.horizontal, 14).padding(.vertical, 11)

                Divider().padding(.horizontal, 14)

                OnboardingRow(
                    icon: "photo.fill",
                    label: "Develop",
                    description: "See exactly what background agents were added, removed, or modified"
                )
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .frame(maxWidth: 380)

            Spacer()
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 2: Auto-Scan & Notifications

private struct AutoScanStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Watch mode")
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Spacer().frame(height: 8)

            Text("LatentGrain can watch your Mac in real time and notify you the moment a background agent installs itself.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer().frame(height: 14)

            VStack(spacing: 0) {
                OnboardingRow(
                    icon: "eye.fill",
                    label: "Real-time monitoring",
                    description: "FSEvents watches your persistence locations continuously"
                )
                .padding(.horizontal, 14).padding(.vertical, 11)

                Divider().padding(.horizontal, 14)

                OnboardingRow(
                    icon: "bell.fill",
                    label: "Instant notifications",
                    description: "Alerted the moment a new agent appears — no manual scan needed"
                )
                .padding(.horizontal, 14).padding(.vertical, 11)

                Divider().padding(.horizontal, 14)

                OnboardingRow(
                    icon: "lock.shield.fill",
                    label: "Requires Full Disk Access",
                    description: "Enable Auto-Scan in Settings once Full Disk Access is granted"
                )
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .frame(maxWidth: 380)

            Spacer()
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 3: Full Disk Access

private struct FDAStep: View {
    @Binding var isFDAGranted: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("One permission needed")
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Spacer().frame(height: 10)

            Text("LatentGrain needs Full Disk Access to scan Background Task Management — where macOS silently registers persistent background agents.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer().frame(height: 16)

            if isFDAGranted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 15))
                    Text("Full Disk Access granted")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: 380)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.green.opacity(0.25), lineWidth: 0.5))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 15))
                    Text("Not yet granted")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Grant Access →") { FDAService.openFDASettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .focusable(false)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: 380)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
            }

            Spacer()
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
    }
}

// MARK: - Step 4: Ready

private struct ReadyStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Spacer().frame(height: 14)

            Text("You're set up.")
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Spacer().frame(height: 10)

            Text("Start by clicking 'Shoot Before', install an app, then 'Shoot After' — LatentGrain shows you exactly what changed.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer().frame(height: 20)

            Button { onComplete() } label: {
                NavButton(label: "Shoot First Snapshot", direction: .forward)
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()
        }
        .padding(.top, 32)
        .padding(.horizontal, 32)
    }
}

// MARK: - Shared row

private struct OnboardingRow: View {
    let icon: String
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}
