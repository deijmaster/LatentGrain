import Foundation

actor UpdateChecker {

    static let shared = UpdateChecker()

    private let apiURL = URL(string: "https://api.github.com/repos/deijmaster/LatentGrain/releases/latest")!

    /// Returns the latest release tag if it is newer than the running build, otherwise nil.
    func fetchLatestTagIfNewer() async -> String? {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String
        else { return nil }

        // Validate tag format — must be "v<digits>" or "<digits>" only.
        // Prevents a tampered API response from injecting anything into a URL.
        guard tag.range(of: #"^v?\d+$"#, options: .regularExpression) != nil else { return nil }

        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let remote  = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

        guard
            let remoteInt  = Int(remote),
            let currentInt = Int(current),
            remoteInt > currentInt
        else { return nil }

        return tag
    }
}
