# Quick References

## Apple Documentation (Local)
- [AppIntents Updates](apple/AppIntents-Updates.md)
- [Foundation Models - On-device LLM](apple/FoundationModels-Using-on-device-LLM-in-your-app.md)
- [Swift Concurrency Updates](apple/Swift-Concurrency-Updates.md) ← **Read this, you use actors**
- [Swift InlineArray/Span](apple/Swift-InlineArray-Span.md)
- [SwiftUI Liquid Glass Design](apple/SwiftUI-Implementing-Liquid-Glass-Design.md)
- [SwiftUI Toolbar Features](apple/SwiftUI-New-Toolbar-Features.md)

## External Resources

### XPC Services
- [Creating XPC Services](https://developer.apple.com/documentation/xpcservice)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- Implementation: `LatentGrainHelper/`

### File System Events
- [FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/)
- Implementation: `Services/WatchService.swift` (final class, not actor)

### Signing & Notarization
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- Commands: `codesign -s "Developer ID" --options runtime`, `xcrun notarytool submit/wait/staple`

### Entitlements
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- **Our decision:** Sandbox OFF (requires /Library access)

## Project-Specific Patterns

**Concurrency:**
- `actor` for Snapshot/Scan (thread-safe state)
- `final class` for Watch (FSEvents uses C callback on DispatchQueue)

**UI:**
- `.focusable(false)` on every button
- `NSApp.hide(nil)` before OS handoffs