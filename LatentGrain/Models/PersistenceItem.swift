import Foundation

// MARK: - PersistenceLocation

enum PersistenceLocation: String, Codable, CaseIterable, Hashable {
    case userLaunchAgents       = "~/Library/LaunchAgents"
    case systemLaunchAgents     = "/Library/LaunchAgents"
    case systemLaunchDaemons    = "/Library/LaunchDaemons"
    case systemExtensions       = "/Library/SystemExtensions"
    case backgroundTaskMgmt     = "/private/var/db/com.apple.backgroundtaskmanagement"
    case configurationProfiles  = "/var/db/ConfigurationProfiles"
    case userTCC                = "~/Library/Application Support/com.apple.TCC/TCC.db"
    case systemTCC              = "/Library/Application Support/com.apple.TCC/TCC.db"

    var displayName: String {
        switch self {
        case .userLaunchAgents:        return "User Launch Agents"
        case .systemLaunchAgents:      return "System Launch Agents"
        case .systemLaunchDaemons:     return "System Launch Daemons"
        case .systemExtensions:        return "System Extensions"
        case .backgroundTaskMgmt:      return "Background Task Mgmt"
        case .configurationProfiles:   return "Configuration Profiles"
        case .userTCC:                 return "User TCC Database"
        case .systemTCC:               return "System TCC Database"
        }
    }

    var shortName: String {
        switch self {
        case .userLaunchAgents:        return "User Agents"
        case .systemLaunchAgents:      return "Sys Agents"
        case .systemLaunchDaemons:     return "Sys Daemons"
        case .systemExtensions:        return "Extensions"
        case .backgroundTaskMgmt:      return "BTM"
        case .configurationProfiles:   return "Profiles"
        case .userTCC:                 return "User TCC"
        case .systemTCC:               return "Sys TCC"
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
        case .userTCC:
            return FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
                .path
        default:
            return rawValue
        }
    }

    /// Whether this location is a single file rather than a directory of files.
    var isSingleFile: Bool {
        switch self {
        case .userTCC, .systemTCC: return true
        default: return false
        }
    }

    /// Path suitable for FSEvents monitoring. Returns the parent directory for
    /// single-file locations since FSEvents requires a directory path.
    var watchPath: String {
        if isSingleFile {
            return (resolvedPath as NSString).deletingLastPathComponent
        }
        return resolvedPath
    }

    /// Whether reading this location requires elevation / Full Disk Access.
    /// Note: /Library/LaunchDaemons is world-readable (755) — no elevation needed to scan it.
    /// BTM and ConfigurationProfiles FSEvents require Full Disk Access.
    /// The `profiles` CLI scan itself works without FDA.
    var requiresElevation: Bool {
        switch self {
        case .backgroundTaskMgmt, .configurationProfiles,
             .userTCC, .systemTCC: return true
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
    let attribution: AppAttribution?

    // Equality is path + hash so we can detect modifications.
    static func == (lhs: PersistenceItem, rhs: PersistenceItem) -> Bool {
        lhs.fullPath == rhs.fullPath && lhs.contentsHash == rhs.contentsHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fullPath)
    }

    /// Returns a copy with attribution populated.
    func withAttribution(_ attribution: AppAttribution) -> PersistenceItem {
        PersistenceItem(
            id: id,
            filename: filename,
            fullPath: fullPath,
            location: location,
            modificationDate: modificationDate,
            fileSize: fileSize,
            contentsHash: contentsHash,
            label: label,
            programPath: programPath,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            attribution: attribution
        )
    }
}
