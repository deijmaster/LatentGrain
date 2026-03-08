# LatentGrain

> *The fine detail of what's hiding on your Mac.*

LatentGrain is a macOS menu-bar utility that **photographs your persistence layer** before and after you install anything, then shows you exactly what changed. Think of it as a darkroom for your Mac: shoot before, install, shoot after, develop — and the film reveals what's been hiding.

I got tired of staring at daemons and launch agents on my Macs, and yes, I love bananas — so I made this.

---

## Persistence location?

macOS apps can install small background programs that start automatically — even when the app itself is closed, and even after a reboot. These are called **launch agents**, **launch daemons**, and **login items**. They live in specific folders on your file system, and macOS registers them silently.

Most of the time this is fine. But sometimes you want to know exactly what an installer just added to your system.

That's what LatentGrain checks.

---

## How it works

### Manual mode — shoot before/after

1. **Shoot Before** — click the menu-bar icon and take a snapshot before installing anything. LatentGrain reads all persistence locations and stores a baseline.
2. **Install anything** — an app, a CLI tool, a system update, anything.
3. **Shoot After** — take a second snapshot.
4. **Develop** — two Polaroid-style cards animate from dark to revealed, followed by a full diff: exactly what was **added**, **removed**, or **modified**, with file names, binary paths, and flags like "runs at login" or "keeps running".

### Watch mode — automatic detection

Enable Watch Mode in Settings and LatentGrain monitors your persistence locations in real time using FSEvents. The moment a new agent installs itself — from an app update, a background installer, or anything else — you get a notification. No manual scanning needed.

---

## Features

| Feature | |
|---|---|
| Before/After manual scan | ✓ |
| All persistence locations | ✓ |
| Diff view (added/removed/modified) | ✓ |
| SHA-256 hash-based change detection | ✓ |
| "Runs at login" / "Keep alive" flags | ✓ |
| TCC database monitoring (permission tampering detection) | ✓ |
| Configuration Profiles scanning | ✓ |
| Color-coded location tags per finding | ✓ |
| Reveal in Finder for any item | ✓ |
| App attribution (resolve which app owns each item) | ✓ |
| Persistence Timeline | ✓ |
| Stats dashboard | ✓ |
| Control Zone (disable / quarantine items) | ✓ |
| Watch mode (real-time FSEvents monitoring) | ✓ |
| Instant notifications on change | ✓ |

**Other highlights:**
- **Persistence Timeline** — four-tab view: Timeline (full scan history), Sources (browser for each persistence location), Stats (infographic analytics dashboard), and Control Zone (manage disabled/quarantined items)
- **Stats dashboard** — KPI cards, 14-day activity chart, change-type and scan-origin breakdowns, per-location bar charts, and insight callouts (scan frequency, clean streak, hotspot location)
- **Liquid Glass design** — native macOS 26 Liquid Glass on timeline cards; graceful fallback on earlier versions
- Monochrome timeline spine — neutral dots keep the scan list readable without color noise
- Quick-access shortcuts to every persistence folder and all windows via the right-click menu
- First-launch onboarding that walks you through the one required permission (Full Disk Access)
- Clean, native Apple UI — Swift + SwiftUI, no Electron, no web views, no external dependencies

---

## Persistence locations monitored

| Location | What lives there | Access required |
|---|---|---|
| `~/Library/LaunchAgents` | Per-user background agents | None |
| `/Library/LaunchAgents` | System-wide background agents | None |
| `/Library/SystemExtensions` | Kernel/network extensions | None |
| `/Library/LaunchDaemons` | System daemons (run as root) | None |
| Background Task Management DB | Everything macOS silently registers | Full Disk Access |
| Configuration Profiles | MDM and configuration profiles | Full Disk Access |
| User TCC Database | Per-user privacy permissions | Full Disk Access |
| System TCC Database | System-wide privacy permissions | Full Disk Access |

> The Background Task Management database (`/private/var/db/com.apple.backgroundtaskmanagement`) is where macOS registers **all** persistent items — including ones that never appear in the other folders. The TCC databases (`com.apple.TCC/TCC.db`) track which apps have been granted privacy permissions — a known attack surface for permission tampering. Both are reasons Full Disk Access is requested.

---

## Download

### Pre-built app *(unsigned)*

Pre-built DMG releases are available on the [Releases page](https://github.com/deijmaster/LatentGrain/releases).

Because LatentGrain is not yet notarized by Apple, macOS Gatekeeper will block the first launch. To open it:

1. Mount the DMG and drag LatentGrain to Applications as usual
2. **Right-click** LatentGrain.app → **Open** → click **Open** in the dialog

You only need to do this once. After that it opens normally.

> Alternatively, from Terminal: `xattr -cr /Applications/LatentGrain.app`

### Build from source

This project uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to manage the `.xcodeproj`.

```bash
# Install xcodegen if you don't have it
brew install xcodegen

# Clone and build
git clone https://github.com/deijmaster/LatentGrain.git
cd LatentGrain
xcodegen generate
open LatentGrain.xcodeproj
```

Press **⌘R** in Xcode to build and run.

> **Note:** App Sandbox is disabled — required to read system-level persistence paths. This app is for direct distribution only, not the Mac App Store.

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ to build from source

---

## Architecture

```
LatentGrain.app              ← SwiftUI menu-bar app (@MainActor)
       ↕ XPC
LatentGrainHelper            ← Privileged XPC helper
       ↕
~/Library/Application Support/LatentGrain/   ← JSON snapshot store
```

| Layer | Details |
|---|---|
| UI | SwiftUI, macOS 13+ |
| Concurrency | Swift `actor` for scan services, `@MainActor` view models |
| Real-time monitoring | FSEvents (WatchService) with 2.5s + 1.5s debounce |
| Storage | JSON files — no CoreData, no external dependencies |
| Change detection | SHA-256 per-file hash via CryptoKit |
| Helper IPC | XPC Service |
| Launch at Login | `SMAppService` |

---

## Changelog

### v5
- **Stats tab** — new infographic analytics view inside the persistence timeline. Shows KPI tiles (total scans, changes found, items monitored, active actions), a 14-day activity bar chart with a change-intensity heatmap overlay, stacked proportion bars for change types (added/removed/modified) and scan origin (auto/manual), per-location horizontal bar charts for both events and current item counts, and three insight cards (scan frequency, clean streak, hotspot location). Colors match the existing per-location badge palette for consistency.
- **Monochrome timeline dots** — removed the per-event color coding from the left-pane spine dots (green/blue/red/orange). The neutral white dots reduce visual noise and let the card content carry the meaning.
- **Window fade helpers moved to shared theme** — `windowEndFade`, `windowStartFade`, and `windowEdgeFades` are now defined in `TimelineTheme.swift` instead of buried in `TimelineView.swift`, making them properly reusable across feature files.

### v4
- **TCC database monitoring** — tracks user and system TCC databases (`com.apple.TCC/TCC.db`) for permission changes, a known attack surface (CVE-2022-26712). Opens Privacy & Security settings on tap.
- **Configuration Profiles scanning** — detects MDM and configuration profile changes via `profiles` CLI
- **Color-coded location tags** — each persistence location has its own color (blue for User Agents, indigo for System Agents, purple for Daemons, teal for Extensions, orange for BTM, pink for Profiles, yellow/red for TCC). Visible on timeline cards and diff item rows.
- **Redesigned timeline cards** — top row shows location pills + detection method (AUTO/SCAN) + timestamp; bottom row shows change counts. Clearer visual hierarchy.
- **Improved detail view cards** — badges moved above filename for full-width details, larger fonts, more breathing room between lines

### v3
- **New app icon** — redesigned icon set with all required macOS sizes (@1x and @2x)
- **Full Disk Access stability fixes** — three bugs in the FDA state tracking that caused crashes or unexpected behaviour when granting access or switching apps:
  - `lastKnownFDAState` was initialised to `false`, triggering a spurious FSEvents stream restart on every cold launch when FDA was already granted
  - `restartWithCurrentFDAState()` ignored the `autoScanEnabled` gate, starting the stream even when Watch mode was off
  - Notification permission was re-requested from a background queue on every FDA state change instead of once on first start

## Roadmap

- [x] Core scan + diff engine, Polaroid UI, menu-bar app, unit tests
- [x] Full Disk Access detection, BTM scanning, FDA onboarding, Settings
- [x] Real-time FSEvents Watch mode, notifications
- [x] First-launch onboarding (5-step), frictionless FDA flow
- [x] Persistence Timeline (vertical spine, Liquid Glass), redesigned app icon
- [x] TCC monitoring, color-coded location tags, improved detail cards
- [x] Stats dashboard, Control Zone, monochrome timeline spine
- [ ] Developer ID signing + notarization

---
## Creating a release DMG

No Apple Developer account is required to build a distributable DMG. The result is unsigned — see the Gatekeeper note above.

```bash
# 1. Build a release archive in Xcode
#    Product → Archive → Distribute App → Copy App → export to a folder

# 2. Install create-dmg
brew install create-dmg

# 3. Package
create-dmg \
  --volname "LatentGrain" \
  --window-size 540 380 \
  --icon-size 128 \
  --app-drop-link 380 180 \
  "LatentGrain.dmg" \
  "path/to/exported/LatentGrain.app"

# 4. Upload LatentGrain.dmg as an asset on a GitHub Release
```

## Project structure

```
LatentGrain/
├── LatentGrain/
│   ├── App/                    AppDelegate, LatentGrainApp
│   ├── Features/
│   │   ├── Scan/               ScanView, ScanViewModel
│   │   ├── Diff/               DiffView, PolaroidCardView, ItemRow
│   │   ├── Timeline/           TimelineView, StatsView, DiffDetailView, TimelineTheme
│   │   ├── Onboarding/         OnboardingView (5-step first-launch flow)
│   │   └── Settings/           SettingsView
│   ├── Models/                 PersistenceItem, Snapshot, Diff, DiffRecord
│   ├── Services/               ScanService, DiffService, StorageService,
│   │                           WatchService, FDAService, HelperService
│   └── Utilities/              FileHasher, PlistParser
├── LatentGrainHelper/          Privileged XPC helper
├── Tests/                      DiffService + SnapshotService unit tests
└── project.yml                 xcodegen spec
```

---

Made with love in Montreal.

Inspired by [Patrick Wardle](https://objective-see.org) and the work he does at Objective-See — BlockBlock, KnockKnock, LuLu, and the rest. The fact that world-class macOS security tooling exists and is free is because of people like him. This app wouldn't exist without that inspiration.

Source available, non-commercial — © 2026 deijmaster. Personal use and forks welcome. Commercial use requires written permission. See [LICENSE](LICENSE).

*Built with Swift + SwiftUI. No Electron was harmed in the making of this app.*

