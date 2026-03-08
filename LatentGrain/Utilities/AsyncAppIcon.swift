import SwiftUI
import AppKit

// MARK: - AsyncAppIcon
//
// Loads an app icon off the main thread and caches it process-wide so that
// repeated scroll passes never re-hit the disk.
//
// Usage:
//   AsyncAppIcon(paths: resolveIconPaths(for: item), size: 16)
//   AsyncAppIcon(paths: [attribution.appBundlePath], size: 14)
//
// While the icon is loading a dim placeholder rect is shown at the same size
// so the layout doesn't shift when the image arrives.

struct AsyncAppIcon: View {

    // Candidate paths tried in order — first existing file wins
    let paths: [String]
    let size: CGFloat
    var cornerRadius: CGFloat = 4

    @State private var icon: NSImage?

    // Process-wide cache — keyed on the first (highest-priority) path
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: size, height: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: paths.first) { await load() }
    }

    private func load() async {
        guard let cacheKey = paths.first.map({ $0 as NSString }) else { return }
        if let cached = Self.cache.object(forKey: cacheKey) {
            icon = cached
            return
        }
        let pathsCopy = paths
        let result = await Task.detached(priority: .utility) {
            resolveIcon(from: pathsCopy)
        }.value
        Self.cache.setObject(result, forKey: cacheKey)
        icon = result
    }
}

// MARK: - Path resolution helpers

/// Returns ordered candidate paths for a persistence item's icon.
/// The caller passes this to AsyncAppIcon(paths:).
func resolveIconPaths(for item: PersistenceItem) -> [String] {
    var paths: [String] = []
    if let bundlePath = item.attribution?.appBundlePath {
        paths.append(bundlePath)
    }
    if let programPath = item.programPath {
        if let appBundle = appBundleContaining(programPath) {
            paths.append(appBundle)
        }
        paths.append(programPath)
    }
    paths.append(item.fullPath)
    return paths
}

/// Walks up the directory tree from a binary path to find its enclosing .app bundle.
func appBundleContaining(_ path: String) -> String? {
    var url = URL(fileURLWithPath: path)
    for _ in 0..<12 {
        if url.path == "/" { break }
        if url.path.hasSuffix(".app") { return url.path }
        url.deleteLastPathComponent()
    }
    return nil
}

// MARK: - Off-thread icon loading

/// Synchronously resolves an NSImage from the first existing path in the list.
/// Intended to run on a background thread via Task.detached.
private func resolveIcon(from paths: [String]) -> NSImage {
    let fm = FileManager.default
    for path in paths {
        if fm.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
    }
    return NSWorkspace.shared.icon(for: .data)
}
