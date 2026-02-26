import Foundation

/// Identifies which application owns a persistence item (launch agent, daemon, etc.).
struct AppAttribution: Codable, Equatable, Hashable {
    let appName: String            // "Docker Desktop"
    let bundleIdentifier: String?  // "com.docker.docker"
    let appBundlePath: String      // "/Applications/Docker.app"
    let signingTeamID: String?     // "9BNSXJN65R"
    let signingIdentity: String?   // "Developer ID Application: Docker Inc"
}
