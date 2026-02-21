import SwiftUI
import AppKit

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step = 0
    @State private var isFDAGranted = FDAService.isGranted
    @State private var skippedFDA = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Total steps: 0 Welcome · 1 How it works · 2 Auto-scan · 3 FDA · 4 Ready
    private let totalSteps = 5

    var body: some View {
        ZStack(alignment: .bottom) {
            // Step content
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

            // Navigation footer
            VStack(spacing: 8) {
                // CTA button (steps 0–3 only; step 4 has its own inline CTA)
                if step < 4 {
                    ctaButton
                }

                // "Skip for now" lives here — directly in scope, no binding needed,
                // no z-order ambiguity with the step content ZStack below.
                if step == 3 && !isFDAGranted && !skippedFDA {
                    Button("Skip for now") {
                        skippedFDA = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12, design: .monospaced))
                    .focusable(false)
                }

                // Dot indicator
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.primary : Color.primary.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 460, height: 460)
        .overlay(alignment: .topLeading) {
            if step > 0 {
                Button("← Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        step -= 1
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13, design: .monospaced))
                .padding(.top, 20)
                .padding(.leading, 20)
                .focusable(false)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            isFDAGranted = FDAService.isGranted
        }
    }

    @ViewBuilder
    private var ctaButton: some View {
        switch step {
        case 0:
            Button("How it works →") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 1 }
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)

        case 1:
            Button("Watch mode →") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 2 }
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)

        case 2:
            Button("One permission needed →") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 3 }
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)

        case 3:
            Button("Continue →") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = 4 }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!(isFDAGranted || skippedFDA))
            .focusable(false)

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
            // Icon zone — 48pt icon + 16pt gap = 64pt, matching the blank zone in non-icon steps
            Image(systemName: "camera.aperture")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Spacer().frame(height: 16)

            Text("Meet LatentGrain")
                .font(.system(size: 22, weight: .bold, design: .monospaced))

            Spacer().frame(height: 12)

            Text("macOS lets apps install background agents that run silently — even when the app is closed. LatentGrain photographs your persistence layer before and after installs, so you always know exactly what's running on your Mac.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }
}

// MARK: - Step 1: How it works

private struct HowItWorksStep: View {
    var body: some View {
        VStack(spacing: 0) {
            // Blank zone — 64pt matches icon(48) + gap(16) in icon steps
            Spacer().frame(height: 64)

            Text("How it works")
                .font(.system(size: 22, weight: .bold, design: .monospaced))

            Spacer().frame(height: 20)

            VStack(spacing: 16) {
                OnboardingRow(
                    icon: "camera.shutter.button.fill",
                    label: "Shoot Before",
                    description: "Snapshot your Mac's current persistence state"
                )
                OnboardingRow(
                    icon: "arrow.down.circle.fill",
                    label: "Install anything",
                    description: "Install an app, a tool, or a system update"
                )
                OnboardingRow(
                    icon: "photo.fill",
                    label: "Develop",
                    description: "See exactly what background agents were added, removed, or modified"
                )
            }
            .frame(maxWidth: 360)

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }
}

// MARK: - Step 2: Auto-Scan & Notifications

private struct AutoScanStep: View {
    var body: some View {
        VStack(spacing: 0) {
            // Blank zone — 64pt matches icon(48) + gap(16) in icon steps
            Spacer().frame(height: 64)

            Text("Watch mode")
                .font(.system(size: 22, weight: .bold, design: .monospaced))

            Spacer().frame(height: 10)

            Text("LatentGrain can watch your Mac in real time and notify you the moment a background agent installs itself.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer().frame(height: 20)

            VStack(spacing: 10) {
                OnboardingRow(
                    icon: "eye.fill",
                    label: "Real-time monitoring",
                    description: "FSEvents watches your persistence locations continuously"
                )
                OnboardingRow(
                    icon: "bell.fill",
                    label: "Instant notifications",
                    description: "Alerted the moment a new agent appears — no manual scan"
                )
                OnboardingRow(
                    icon: "lock.shield.fill",
                    label: "Requires Full Disk Access + Pro",
                    description: "Enable Auto-Scan in Settings once permissions are in place"
                )
            }
            .frame(maxWidth: 360)

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }
}

// MARK: - Step 3: Full Disk Access

private struct FDAStep: View {
    @Binding var isFDAGranted: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Blank zone — 64pt matches icon(48) + gap(16) in icon steps
            Spacer().frame(height: 64)

            Text("One permission needed")
                .font(.system(size: 22, weight: .bold, design: .monospaced))

            Spacer().frame(height: 12)

            Text("LatentGrain needs Full Disk Access to scan Background Task Management — where macOS silently registers persistent background agents.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer().frame(height: 20)

            // Dynamic status row — re-probed on didBecomeActive
            if isFDAGranted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                    Text("Full Disk Access granted")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 16))
                    Text("Not yet granted")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Grant Access →") {
                        FDAService.openFDASettings()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12, design: .monospaced))
                    .focusable(false)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 340)
            }

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }
}

// MARK: - Step 4: Ready

private struct ReadyStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Icon zone — 48pt icon + 16pt gap = 64pt, matching the blank zone in non-icon steps
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Spacer().frame(height: 16)

            Text("You're set up.")
                .font(.system(size: 22, weight: .bold, design: .monospaced))

            Spacer().frame(height: 12)

            Text("Start by clicking 'Shoot Before', install an app, then 'Shoot After' — LatentGrain shows you exactly what changed.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            Spacer().frame(height: 24)

            Button("Shoot First Snapshot →") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 14, design: .monospaced))
            .focusable(false)

            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }
}

// MARK: - Shared row

private struct OnboardingRow: View {
    let icon: String
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(description)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}
