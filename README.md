# LatentGrain

> *The fine detail of what's hiding on your Mac.*

I got tired of looking at my deamons and launch agents and love bananas - so I made this.

LatentGrain is a macOS menu-bar utility that snapshots your Mac's entire persistence state — LaunchAgents, LaunchDaemons, Login Items, System Extensions — before and after any app install, then shows you exactly what changed in a Polaroid-style before/after UI.

---

## How it works

1. **Shoot Before** — take a snapshot of all persistence locations before installing an app
2. Install your app
3. **Shoot After** — take a second snapshot
4. **Develop** — two Polaroid cards reveal what was there before and after, followed by a full diff of exactly what changed

No alarmism. No bloat. Just the facts.

> **Privacy note:** On launch, LatentGrain makes a single request to the GitHub Releases API to check for updates. No personal data is sent — it is a plain unauthenticated GET to a public endpoint. Your IP address is visible to GitHub as with any HTTPS request. No other network requests are ever made.

---

## Features

- Scans all major macOS persistence locations
- Detects **added**, **removed**, and **modified** items (via SHA-256 file hashing)
- Highlights items that run at login or are configured to stay alive
- Reveal in Finder for any item with one click
- Quick-access shortcuts to every persistence folder in the toolbar
- Vertically resizable window — scroll through long diffs comfortably
- Clean, Apple-native UI — no Electron, no web views

---

## Persistence locations monitored

| Location | Access |
|---|---|
| `~/Library/LaunchAgents` | User — no elevation needed |
| `/Library/LaunchAgents` | User-readable |
| `/Library/SystemExtensions` | User-readable |
| `/Library/LaunchDaemons` | Privileged helper *(Phase 2)* |
| Background Task Management DB | Full Disk Access *(Phase 2)* |

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (to build from source)

---

## Building from source

This project uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to manage the `.xcodeproj`.

```bash
# Install xcodegen if you don't have it
brew install xcodegen

# Clone and build
git clone https://github.com/YOUR_USERNAME/LatentGrain.git
cd LatentGrain
xcodegen generate
open LatentGrain.xcodeproj
```

Then press **⌘R** in Xcode to build and run.

> **Note:** The app requires **App Sandbox disabled** to read system-level persistence paths. It is intended for direct distribution, not the Mac App Store.

---

## Architecture

```
LatentGrain.app              ← SwiftUI menu-bar app
       ↕ XPC
LatentGrainHelper            ← Privileged XPC helper (Phase 2)
       ↕
~/Library/Application Support/LatentGrain/   ← JSON snapshot store
```

| Layer | Details |
|---|---|
| UI | SwiftUI, macOS 13+ |
| Concurrency | Swift `actor` for scan services, `@MainActor` view models |
| Storage | JSON files (no external dependencies) |
| Hashing | SHA-256 via CryptoKit |
| Helper IPC | XPC Service |
| Launch at Login | `SMAppService` |

---

## Roadmap

- [x] **Phase 1** — Core MVP: scan, diff, Polaroid UI, menu-bar app
- [ ] **Phase 2** — Privileged helper for `/Library/LaunchDaemons` + Full Disk Access onboarding
- [ ] **Phase 3** — App icon, onboarding flow, animation polish
- [ ] **Phase 4** — Snapshot history, export (PDF/JSON), auto-scan on install *(freemium)*
- [ ] **Phase 5** — Developer ID signing, notarization, DMG distribution

---

## Project structure

```
LatentGrain/
├── LatentGrain/
│   ├── App/                    AppDelegate, LatentGrainApp
│   ├── Features/
│   │   ├── Scan/               ScanView, ScanViewModel
│   │   ├── Diff/               DiffView, PolaroidCardView
│   │   ├── History/            HistoryView (premium gate)
│   │   └── Settings/           SettingsView
│   ├── Models/                 PersistenceItem, Snapshot, Diff
│   ├── Services/               ScanService, DiffService, StorageService
│   └── Utilities/              FileHasher, PlistParser
├── LatentGrainHelper/          Privileged XPC helper
├── Tests/                      DiffService + SnapshotService unit tests
└── project.yml                 xcodegen spec
```

---

## Releasing *(Phase 5)*

Requires an [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year) and a **Developer ID Application** certificate.

```bash
# 1. Archive
#    Xcode → Product → Archive → Distribute App → Developer ID → export LatentGrain.app

# 2. Package into a DMG (use create-dmg or Xcode Organizer)
brew install create-dmg
create-dmg \
  --volname "LatentGrain" \
  --window-size 540 380 \
  --icon-size 128 \
  --app-drop-link 380 180 \
  "LatentGrain.dmg" \
  "path/to/exported/LatentGrain.app"

# 3. Notarize
xcrun notarytool submit LatentGrain.dmg \
  --apple-id "you@email.com" \
  --team-id "YOURTEAMID" \
  --keychain-profile "notarytool-profile" \
  --wait

# 4. Staple the notarization ticket so it works offline
xcrun stapler staple LatentGrain.dmg

# 5. Verify
spctl -a -v LatentGrain.app
```

> **Keychain profile** — store your credentials once so you never type them again:
> ```bash
> xcrun notarytool store-credentials "notarytool-profile" \
>   --apple-id "you@email.com" \
>   --team-id "YOURTEAMID" \
>   --password "app-specific-password"
> ```
> Generate the app-specific password at [appleid.apple.com](https://appleid.apple.com).

---

## License

Source available, non-commercial — © 2026 deijmaster. Personal use and forks welcome. Commercial use requires written permission. See [LICENSE](LICENSE).

---

*Built with Swift + SwiftUI. No Electron was harmed in the making of this app.*
