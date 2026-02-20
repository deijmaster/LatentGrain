# LatentGrain

> *The fine detail of what's hiding on your Mac.*

A macOS menu-bar utility that snapshots your Mac's entire persistence state — LaunchAgents, LaunchDaemons, Login Items, System Extensions — before and after any app install, then shows you exactly what changed in a Polaroid-style before/after UI.

---

## Architecture

```
LatentGrain.app          ← SwiftUI menu-bar app (user-facing)
       ↕ XPC
LatentGrainHelper        ← Privileged XPC helper (reads /Library/LaunchDaemons)
       ↕
JSON store (~/Library/Application Support/LatentGrain/)
```

## Project Structure

```
LatentGrain/
├── LatentGrain/                    # Main app target
│   ├── App/
│   │   ├── LatentGrainApp.swift    # @main, MenuBarExtra scene
│   │   ├── AppDelegate.swift       # LSUIElement / Dock hide
│   │   └── Info.plist
│   ├── Features/
│   │   ├── Scan/
│   │   │   ├── ScanView.swift
│   │   │   └── ScanViewModel.swift
│   │   ├── Diff/
│   │   │   ├── DiffView.swift
│   │   │   ├── PolaroidCardView.swift
│   │   │   ├── DiffRowView.swift
│   │   │   └── DiffViewModel.swift
│   │   ├── History/
│   │   │   └── HistoryView.swift   (Premium gate)
│   │   └── Settings/
│   │       └── SettingsView.swift
│   ├── Models/
│   │   ├── PersistenceItem.swift
│   │   ├── PersistenceSnapshot.swift
│   │   └── PersistenceDiff.swift
│   ├── Services/
│   │   ├── ScanService.swift
│   │   ├── SnapshotService.swift
│   │   ├── DiffService.swift
│   │   ├── HelperService.swift
│   │   └── StorageService.swift
│   └── Utilities/
│       ├── FileHasher.swift
│       └── PlistParser.swift
│
├── LatentGrainHelper/
│   ├── HelperMain.swift
│   ├── HelperDelegate.swift
│   ├── XPCProtocol.swift           (shared with main target)
│   └── Info.plist
│
└── Tests/
    ├── DiffServiceTests.swift
    └── SnapshotServiceTests.swift
```

---

## Xcode Project Setup

> **Requirements:** Xcode 15+, macOS 13 SDK, Apple Developer account

### 1. Create the Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **macOS → App**
3. Product Name: `LatentGrain`
4. Bundle Identifier: `com.latentgrain.app`
5. Language: Swift, Interface: SwiftUI
6. **Uncheck** "Use Core Data" and "Include Tests" (we add tests manually)
7. Save into `/Users/deijmaster/LatentGrain/`

### 2. Add Source Files

Delete the auto-generated `ContentView.swift` and `LatentGrainApp.swift` stubs,
then drag all files from the `LatentGrain/` folder into the project navigator,
adding them to the `LatentGrain` target.

### 3. Main App Target Settings

| Setting | Value |
|---------|-------|
| Deployment Target | macOS 13.0 |
| App Sandbox | **OFF** |
| Info.plist Key `LSUIElement` | `YES` |

In **Signing & Capabilities**, add:
- No sandbox (remove it entirely for direct distribution)

### 4. Add LatentGrainHelper Target

1. **File → New → Target → macOS → XPC Service**
2. Product Name: `LatentGrainHelper`
3. Bundle Identifier: `com.latentgrain.helper`
4. Add these files to the helper target:
   - `LatentGrainHelper/HelperMain.swift`
   - `LatentGrainHelper/HelperDelegate.swift`
   - `LatentGrainHelper/XPCProtocol.swift`
5. Also add `XPCProtocol.swift` to the **main app target** (it's shared).

### 5. Add Test Target

1. **File → New → Target → macOS → Unit Testing Bundle**
2. Product Name: `LatentGrainTests`
3. Add `Tests/DiffServiceTests.swift` and `Tests/SnapshotServiceTests.swift`
4. Set **Host Application** to `LatentGrain`

### 6. Build & Run

```bash
# Build from command line
xcodebuild -scheme LatentGrain -configuration Debug build
```

Or press **⌘R** in Xcode.

---

## Monitored Persistence Locations

| Location | Access |
|----------|--------|
| `~/Library/LaunchAgents` | User — no elevation |
| `/Library/LaunchAgents` | User-readable |
| `/Library/SystemExtensions` | User-readable |
| `/Library/LaunchDaemons` | Requires privileged helper |
| `/private/var/db/com.apple.backgroundtaskmanagement/` | Requires Full Disk Access |

---

## Freemium Gates (Phase 4)

| Feature | Free | Premium |
|---------|------|---------|
| Single before/after scan | ✓ | ✓ |
| All persistence locations | ✓ | ✓ |
| Current diff view | ✓ | ✓ |
| Snapshot history | Last 1 | Unlimited |
| Export (PDF/JSON) | ✗ | ✓ |
| Auto-scan on install | ✗ | ✓ |
| Verbose plist detail | ✗ | ✓ |

---

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| No App Sandbox | Required to read `/Library` paths |
| `SMAppService` not `SMJobBless` | Modern helper API, macOS 13+ |
| XPC for helper IPC | Secure, Apple-recommended |
| JSON storage (not CoreData) | No `.xcdatamodel` needed; API is CoreData-compatible for easy migration |
| SHA-256 per-file | Detects modifications, not just add/remove |
| `actor` for scan services | Safe concurrent access from Swift `async` Tasks |
| No EndpointSecurity in v1 | Avoids entitlement approval friction; planned for v2 |

---

## UI / Design Rules

- **Polaroid metaphor** — dark "undeveloped" photo area → animates to revealed on "Develop" tap
- Monospaced font throughout for a technical-but-friendly feel
- Staggered row entrance animation (spring, 70 ms delay per row)
- Colors: green = added, red = removed, yellow = modified
- ⚠️ warning icon for `RunAtLoad` / `KeepAlive` items
- Empty state: *"Nothing changed — your Mac is clean 📷"* — friendly, not alarmist

---

## Implementation Phases

- [x] **Phase 1** — Core MVP (models, services, Polaroid UI, menu-bar app, tests)
- [ ] **Phase 2** — Privileged helper activation + Full Disk Access onboarding
- [ ] **Phase 3** — "Develop" animation polish, app icon, onboarding flow
- [ ] **Phase 4** — StoreKit 2, FeatureGateManager, export, auto-scan (FSEvents)
- [ ] **Phase 5** — Developer ID signing, notarytool notarization, DMG, website
