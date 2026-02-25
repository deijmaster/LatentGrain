import Foundation

/// Relevant fields extracted from a LaunchAgent / LaunchDaemon plist.
struct PlistInfo {
    let label: String?
    let programPath: String?
    let runAtLoad: Bool?
    let keepAlive: Bool?
}

/// Parses macOS property list files to extract job configuration.
enum PlistParser {

    static func parse(at url: URL) -> PlistInfo {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any]
        else {
            return PlistInfo(label: nil, programPath: nil, runAtLoad: nil, keepAlive: nil)
        }

        let label = plist["Label"] as? String

        // Program path: prefer explicit "Program" key, fallback to ProgramArguments[0]
        let programPath: String?
        if let program = plist["Program"] as? String {
            programPath = program
        } else if let args = plist["ProgramArguments"] as? [String], let first = args.first {
            programPath = first
        } else {
            programPath = nil
        }

        let runAtLoad = plist["RunAtLoad"] as? Bool

        // KeepAlive may be a Bool or a dictionary of conditions
        let keepAlive: Bool?
        switch plist["KeepAlive"] {
        case let boolVal as Bool:
            keepAlive = boolVal
        case let dictVal as [String: Any]:
            keepAlive = !dictVal.isEmpty
        default:
            keepAlive = nil
        }

        return PlistInfo(
            label: label,
            programPath: programPath,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive
        )
    }
}
