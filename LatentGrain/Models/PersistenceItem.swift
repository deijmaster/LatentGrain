import Foundation

// MARK: - PersistenceLocation

enum PersistenceLocation: String, Codable, CaseIterable, Hashable {
    case userLaunchAgents       = "~/Library/LaunchAgents"
    case systemLaunchAgents     = "/Library/LaunchAgents"
    case systemLaunchDaemons    = "/Library/LaunchDaemons"
    case systemExtensions       = "/Library/SystemExtensions"
    case backgroundTaskMgmt     = "/private/var/db/com.apple.backgroundtaskmanagement"

    var displayName: String {
        switch self {
        case .userLaunchAgents:    return "User Launch Agents"
        case .systemLaunchAgents:  return "System Launch Agents"
        case .systemLaunchDaemons: return "System Launch Daemons"
        case .systemExtensions:    return "System Extensions"
        case .backgroundTaskMgmt:  return "Background Task Mgmt"
        }
    }

    /// Absolute filesystem path, resolving `~` for user-level locations.
    var resolvedPath: String {
        switch self {
        case .userLaunchAgents:
            return FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents")
                .path
        default:
            return rawValue
        }
    }

    /// Whether reading this location requires elevation / Full Disk Access.
    /// Note: /Library/LaunchDaemons is world-readable (755) — no elevation needed to scan it.
    /// Only /private/var/db/com.apple.backgroundtaskmanagement requires Full Disk Access.
    var requiresElevation: Bool {
        switch self {
        case .backgroundTaskMgmt: return true
        default: return false
        }
    }
}

// MARK: - PersistenceItem

/// Represents a single plist file (or entry) found in a persistence location.
struct PersistenceItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let filename: String
    let fullPath: String
    let location: PersistenceLocation
    let modificationDate: Date
    let fileSize: Int64
    let contentsHash: String        // SHA-256 of plist bytes
    let label: String?              // "Label" key from plist
    let programPath: String?        // "Program" or ProgramArguments[0]
    let runAtLoad: Bool?
    let keepAlive: Bool?

    // Equality is path + hash so we can detect modifications.
    static func == (lhs: PersistenceItem, rhs: PersistenceItem) -> Bool {
        lhs.fullPath == rhs.fullPath && lhs.contentsHash == rhs.contentsHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fullPath)
    }
}
