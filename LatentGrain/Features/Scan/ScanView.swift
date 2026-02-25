import SwiftUI
import AppKit

struct ScanView: View {

    @ObservedObject var viewModel: ScanViewModel
    @AppStorage("proMode") private var proMode = false
    @AppStorage("fdaBannerDismissed") private var fdaBannerDismissed = false

    private var showFDABanner: Bool {
        !viewModel.isFDAGranted && !fdaBannerDismissed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Grouped banners — only rendered when at least one is visible
            bannerSection

            if viewModel.currentDiff == nil {
                StepProgressView(currentStep: viewModel.beforeSnapshot == nil ? 1 : 2)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                Divider()
            }

            if let diff = viewModel.currentDiff {
                diffContent(diff)
            } else {
                scanControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.recheckFDA() }
        .onChange(of: viewModel.isFDAGranted) { granted in
            if granted { fdaBannerDismissed = false }
        }
    }


    // MARK: - Banner group

    @ViewBuilder
    private var bannerSection: some View {
        let showUpdate = viewModel.isUpdateAvailable && viewModel.latestTag != nil
        let showFDA    = showFDABanner
        let anyVisible = showUpdate || showFDA

        if anyVisible {
            VStack(spacing: 0) {
                if showUpdate, let tag = viewModel.latestTag {
                    UpdateBanner(tag: tag) { viewModel.isUpdateAvailable = false }
                }
                if showFDA {
                    if showUpdate { Divider().padding(.horizontal, 14) }
                    FDABanner { fdaBannerDismissed = true }
                }
            }
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }



    // MARK: - Diff layout

    private func diffContent(_ diff: PersistenceDiff) -> some View {
        VStack(spacing: 0) {
            DiffView(diff: diff, isRevealed: viewModel.isDiffRevealed) {
                viewModel.develop()
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button(action: { viewModel.reset() }) {
                    NavButton(label: "Reset & New Scan", direction: .forward)
                }
                .buttonStyle(.plain)
                .focusable(false)
                Spacer()
            }
            .padding(.vertical, 14)
        }
    }

    // MARK: - Scan controls

    private var scanControls: some View {
        VStack(spacing: 0) {
            // Status area
            if proMode {
                ProStatusView(snapshot: viewModel.beforeSnapshot, isScanning: viewModel.isScanning)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        if viewModel.isScanning {
                            Text("Scanning…")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(16)
                        } else if let before = viewModel.beforeSnapshot {
                            BeforeReadyView(snapshot: before)
                                .padding(.vertical, 12)
                        } else {
                            ReadyToShootView()
                                .padding(.vertical, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Action area — one primary action at a time
            VStack(spacing: 8) {
                    if viewModel.beforeSnapshot == nil || viewModel.isScanning {
                        CaptureBar(
                            primary: viewModel.isScanning ? "Scanning…" : "Shoot",
                            secondary: nil,
                            disabled: viewModel.isScanning
                        ) { Task { await viewModel.shootBefore() } } onSecondary: {}
                    } else {
                        CaptureBar(
                            primary: "Shoot",
                            secondary: "Re-shoot",
                            disabled: false
                        ) { Task { await viewModel.shootAfter() } } onSecondary: {
                            viewModel.reset()
                        }
                    }

                    if let error = viewModel.scanError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step progress

struct StepProgressView: View {
    let currentStep: Int  // 1, 2, or 3

    private let steps = ["Shoot", "Install App", "Shoot"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                let step = index + 1
                let isDone    = step < currentStep
                let isCurrent = step == currentStep

                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isCurrent ? Color.accentColor : isDone ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                            .frame(width: 28, height: 28)
                        if isDone {
                            Text("✓")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("\(step)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(isCurrent ? .white : .secondary)
                        }
                    }
                    Text(label)
                        .font(.system(size: 9, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(step < currentStep ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }
}

// MARK: - Status sub-views

// MARK: - Chat bubble primitives

struct ExpertBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .systemGray).opacity(0.25))
                .clipShape(BubbleShape(isFromUser: false))
            Spacer(minLength: 48)
        }
    }
}

struct UserBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 48)
            Text(text)
                .font(.callout)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                .clipShape(BubbleShape(isFromUser: true))
        }
    }
}

// iMessage-style bubble tail shape
struct BubbleShape: Shape {
    let isFromUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16
        let tailW: CGFloat = 6
        let tailH: CGFloat = 8

        var path = Path()

        if isFromUser {
            // Rounded rect with tail at bottom-right
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r - tailH))
            path.addLine(to: CGPoint(x: rect.maxX + tailW, y: rect.maxY - tailH))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 4))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: r, y: rect.maxY))
            path.addArc(center: CGPoint(x: r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Rounded rect with tail at bottom-left
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: r, y: rect.maxY))
            path.addArc(center: CGPoint(x: r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: r + tailH))
            path.addLine(to: CGPoint(x: -tailW, y: tailH))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Conversation scripts

typealias ChatLine = (expert: Bool, text: String)

enum ConversationScript {

    static let beforeScripts: [[ChatLine]] = [
        // The Matrix
        [
            (true,  "What if I told you your Mac already has dozens of processes running that you never knowingly installed?"),
            (false, "I'd say that sounds unlikely."),
            (true,  "Most people take the blue pill and never look. You opened LatentGrain — so here we are."),
            (false, "Ok. Show me how deep this goes."),
            (true,  "Hit Shoot. Install your app. Come back. I'll show you everything.")
        ],
        // Sherlock Holmes
        [
            (false, "I just want to install an app. Is it really that complicated?"),
            (true,  "Elementary. Apps install. Background processes follow. Most leave no obvious trace."),
            (false, "So how do you catch them?"),
            (true,  "The same way you catch anything — you observe the scene before the crime, and after. That's all this is."),
            (false, "Alright detective. Let's do it."),
            (true,  "Hit Shoot. The game is afoot.")
        ],
        // Jerry Maguire
        [
            (true,  "You want transparency? I'll give you transparency."),
            (false, "I just want to know what's on my Mac."),
            (true,  "Then let's make a deal. You hit Shoot, install your app, come back and hit Shoot."),
            (false, "And then?"),
            (true,  "And then I show you the agents. All of them.")
        ],
        [
            (true,  "Every time you install an app, it can quietly drop background processes on your Mac."),
            (false, "What kind of processes?"),
            (true,  "Agents that run at every login, daemons that keep running silently, extensions with deep system access. Most are harmless — but you should know they're there."),
            (false, "How do I find out what's been added?"),
            (true,  "Hit Shoot. Install your app. Come back and hit Shoot. I'll show you exactly what changed.")
        ],
        [
            (true,  "Apps don't always ask permission before making themselves at home on your Mac."),
            (false, "What do you mean?"),
            (true,  "Login agents, auto-updaters, helper daemons — they install quietly in the background. Legitimate, mostly. But worth knowing about."),
            (false, "So I should check before I install?"),
            (true,  "Exactly. Hit Shoot, install your app, then come back. I'll tell you everything it touched.")
        ],
        [
            (false, "I'm about to install an app. Should I be worried?"),
            (true,  "Not worried — just informed. Apps often leave more behind than just their icon in /Applications."),
            (false, "Like what?"),
            (true,  "Background helpers, update schedulers, crash reporters. Some run forever. Let's take a snapshot now so we can see what gets added."),
            (false, "Ok, how do we start?"),
            (true,  "Hit Shoot. Then install. Then come back here.")
        ],
        [
            (true,  "30 years in security and the question is always the same — do you know what's running on your machine?"),
            (false, "Honestly? No."),
            (true,  "Most people don't. That's why we're here. Hit Shoot and I'll show you your Mac's current state before anything changes."),
            (false, "And then I install the app?"),
            (true,  "Exactly. Then hit Shoot and we'll see exactly what it brought along.")
        ],
        [
            (true,  "Mac apps can install background processes without ever showing you a permission dialog."),
            (false, "Wait, seriously?"),
            (true,  "Completely normal behaviour — update agents, crash reporters, sync helpers. Apple allows it. But transparency matters."),
            (false, "How do I see what gets installed?"),
            (true,  "That's what I'm here for. Shoot, install your app, Shoot. Simple as that.")
        ]
    ]

    static let afterScripts: [[ChatLine]] = [
        // Godfather
        [
            (true,  "I'm going to make you an offer you can't refuse — complete visibility into what that app is about to do."),
            (false, "I'm listening."),
            (true,  "We have {count} items on record. Your Mac's family, so to speak. Now go install. When you return, we'll know if anyone new showed up uninvited."),
            (false, "And if something shady got installed?"),
            (true,  "Then we'll know exactly who to talk to.")
        ],
        // Jaws
        [
            (true,  "{count} items. Honestly? You're going to need a bigger scan after this install."),
            (false, "Should I be nervous?"),
            (true,  "Just informed. Go install your app — most of what we'll find is perfectly normal. But some of it might surprise you."),
            (false, "Ok. Going in."),
            (true,  "I'll be right here. Hit Shoot when you surface.")
        ],
        // Apocalypse Now
        [
            (true,  "{count} background items. I love the smell of a clean Mac before an install."),
            (false, "Is it about to get messy?"),
            (true,  "Depends on the app. Some are surgical. Some bring the whole battalion."),
            (false, "That's slightly alarming."),
            (true,  "Knowledge is the antidote. Go install. Come back. We'll debrief.")
        ],
        [
            (true,  "Found {count} background items already running on your Mac."),
            (false, "Is that a lot?"),
            (true,  "Every Mac is different. What matters is what gets added next — that's what we're watching for."),
            (false, "Ok, going to install now."),
            (true,  "Take your time. Hit Shoot when you're back.")
        ],
        [
            (true,  "Snapshot taken — {count} items catalogued."),
            (false, "What exactly did you find?"),
            (true,  "LaunchAgents, LaunchDaemons, system extensions — everything that can run in the background. It's all on record now."),
            (false, "Good. Installing the app now."),
            (true,  "Go ahead. I'll be here. Hit Shoot when you're done.")
        ],
        [
            (false, "Ok so you found {count} things. Should I be concerned?"),
            (true,  "Not at all. This is just your baseline — what was already here before. We need it to measure what changes next."),
            (false, "Makes sense. Installing now."),
            (true,  "Perfect. Come back and hit Shoot. That's when it gets interesting.")
        ],
        [
            (true,  "{count} items on record. Your Mac's fingerprint before the install."),
            (false, "Fingerprint?"),
            (true,  "Every Mac has a unique set of background processes. Knowing yours means we can spot anything new immediately."),
            (false, "Smart. Ok, installing now."),
            (true,  "See you on the other side. Hit Shoot when ready.")
        ],
        [
            (true,  "Good. {count} items logged. The before picture is clear."),
            (false, "Now I install?"),
            (true,  "Now you install. Take as long as you need — the snapshot doesn't expire."),
            (false, "What if the app installs quietly in the background?"),
            (true,  "That's exactly what we're looking for. Hit Shoot and nothing gets past us.")
        ]
    ]
}

// MARK: - Pro Mode status view

struct ProStatusView: View {
    let snapshot: PersistenceSnapshot?
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            if isScanning {
                Text("Scanning…")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let snapshot {
                Text("\(snapshot.itemCount) items catalogued")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("Ready — hit Shoot when your app is installed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready to snapshot.")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("Hit Shoot before you install anything.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Status sub-views

struct ReadyToShootView: View {
    @State private var script: [ChatLine] = []
    @AppStorage("proMode") private var proMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(script.enumerated()), id: \.offset) { _, line in
                if line.expert {
                    ExpertBubble(text: line.text)
                } else {
                    UserBubble(text: line.text)
                }
            }
            if !proMode {
                ExpertBubble(text: "Been here before? You can skip all this — enable Pro Mode in Settings.")
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .onAppear {
            script = ConversationScript.beforeScripts.randomElement() ?? ConversationScript.beforeScripts[0]
        }
    }
}

struct BeforeReadyView: View {
    let snapshot: PersistenceSnapshot
    @State private var script: [ChatLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(script.enumerated()), id: \.offset) { _, line in
                if line.expert {
                    ExpertBubble(text: line.text)
                } else {
                    UserBubble(text: line.text)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .onAppear {
            let raw = ConversationScript.afterScripts.randomElement() ?? ConversationScript.afterScripts[0]
            script = raw.map { line in
                (line.expert, line.text.replacingOccurrences(of: "{count}", with: "\(snapshot.itemCount)"))
            }
        }
    }
}

// MARK: - Capture Bar

struct CaptureBar: View {
    let primary: String
    let secondary: String?
    let disabled: Bool
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    init(primary: String, secondary: String?, disabled: Bool, _ onPrimary: @escaping () -> Void, onSecondary: @escaping () -> Void) {
        self.primary = primary
        self.secondary = secondary
        self.disabled = disabled
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            HStack {
                if let secondary {
                    Button(action: onSecondary) {
                        NavButton(label: secondary, direction: .back)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                Spacer()

                Button(action: onPrimary) {
                    NavButton(label: primary, direction: .forward, disabled: disabled)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(disabled)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
        }
    }
}

struct NavButton: View {
    enum Direction { case back, forward }

    let label: String
    let direction: Direction
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if direction == .back {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.25 : 1.0))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.25 : 1.0))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(direction == .forward && !disabled ? 0.1 : 0.05))
        .clipShape(Capsule())
    }
}

// MARK: - Update Banner

struct UpdateBanner: View {
    let tag: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)

            Text("Version \(tag) available")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            Button("Download") { openReleasePage() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
                .buttonStyle(.plain)
                .focusable(false)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openReleasePage() {
        guard let url = URL(string: "https://github.com/deijmaster/LatentGrain/releases/tag/\(tag)") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - FDA Banner

struct FDABanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Background Task Management not scanned")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Grant access — we'll open Settings and highlight the app in Finder so you can drag it straight in.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant Access →") { openPrivacySettings() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .buttonStyle(.plain)
                .focusable(false)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openPrivacySettings() {
        FDAService.openFDASettings()
    }
}
