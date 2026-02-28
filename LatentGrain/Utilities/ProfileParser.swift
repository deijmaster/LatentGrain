import Foundation

/// Information extracted from a single configuration profile.
struct ProfileInfo {
    let profileIdentifier: String
    let displayName: String
    let organization: String?
    let installDate: Date?
    let profileType: String?
    let payloadTypes: [String]
    let profileData: Data          // Raw bytes for hashing
    let isMDMManaged: Bool
}

/// MDM enrollment status parsed from `profiles status -type enrollment`.
struct MDMEnrollmentStatus {
    let isEnrolled: Bool
    let enrolledViaDEP: Bool
    let isUserApproved: Bool

    /// Synthetic summary for display.
    var summary: String {
        if !isEnrolled { return "Not enrolled" }
        var parts = ["MDM enrolled"]
        if enrolledViaDEP { parts.append("via DEP") }
        if isUserApproved { parts.append("(User Approved)") }
        return parts.joined(separator: " ")
    }
}

/// Parses output from the macOS `profiles` CLI tool.
enum ProfileParser {

    // MARK: - Profile XML parsing

    /// Parse the XML plist output of `profiles show -output stdout-xml`.
    /// Returns an array of `ProfileInfo` — one per installed configuration profile.
    static func parseProfilesXML(_ data: Data) -> [ProfileInfo] {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any]
        else { return [] }

        // Computer-level profiles live under the `_computerlevel` key.
        // User-level profiles may appear under the username key.
        var allProfiles: [[String: Any]] = []

        for (_, value) in plist {
            if let profiles = value as? [[String: Any]] {
                allProfiles.append(contentsOf: profiles)
            }
        }

        return allProfiles.compactMap { dict -> ProfileInfo? in
            guard let identifier = dict["ProfileIdentifier"] as? String else { return nil }

            let displayName = dict["ProfileDisplayName"] as? String
                ?? dict["ProfileIdentifier"] as? String
                ?? identifier

            let organization = dict["ProfileOrganization"] as? String

            let installDate = dict["ProfileInstallDate"] as? Date

            let profileType = dict["ProfileType"] as? String

            // Collect payload types from ProfileItems array
            var payloadTypes: [String] = []
            if let items = dict["ProfileItems"] as? [[String: Any]] {
                for item in items {
                    if let payloadType = item["PayloadType"] as? String {
                        payloadTypes.append(payloadType)
                    }
                }
            }

            // Serialize this profile dict back to data for hashing
            let profileData = (try? PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .xml,
                options: 0
            )) ?? Data()

            // A profile is MDM-managed if it contains an MDM payload
            let isMDMManaged = payloadTypes.contains("com.apple.mdm")
                || payloadTypes.contains { $0.lowercased().contains("mdm") }

            return ProfileInfo(
                profileIdentifier: identifier,
                displayName: displayName,
                organization: organization,
                installDate: installDate,
                profileType: profileType,
                payloadTypes: payloadTypes,
                profileData: profileData,
                isMDMManaged: isMDMManaged
            )
        }
    }

    // MARK: - Enrollment status parsing

    /// Parse the text output of `profiles status -type enrollment`.
    /// Example output:
    /// ```
    /// Enrolled via DEP: No
    /// MDM enrollment: Yes (User Approved)
    /// ```
    static func parseEnrollmentOutput(_ data: Data) -> MDMEnrollmentStatus {
        let text = String(data: data, encoding: .utf8) ?? ""

        let enrolledViaDEP = text.contains("Enrolled via DEP: Yes")

        let mdmLine = text.split(separator: "\n")
            .first { $0.contains("MDM enrollment") }
            .map(String.init) ?? ""

        let isEnrolled = mdmLine.contains("Yes")
        let isUserApproved = mdmLine.contains("User Approved")

        return MDMEnrollmentStatus(
            isEnrolled: isEnrolled,
            enrolledViaDEP: enrolledViaDEP,
            isUserApproved: isUserApproved
        )
    }
}
