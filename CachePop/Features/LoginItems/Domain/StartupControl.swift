import Foundation

/// launchd's on/off record for each label (`launchctl print-disabled`): true means off.
/// `gui` is your login session (launch agents); `system` is the whole Mac (daemons).
nonisolated struct LaunchOverrides: Sendable, Equatable {
    var gui: [String: Bool] = [:]
    var system: [String: Bool] = [:]

    /// Parses lines like `"com.example.agent" => disabled` (older macOS: `=> true`).
    static func parse(_ output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !label.isEmpty else { continue }
            switch value {
            case "disabled", "true": result[label] = true
            case "enabled", "false": result[label] = false
            default: continue
            }
        }
        return result
    }
}


/// An app in System Settings › General › Login Items › Open at Login.
nonisolated struct OpenAtLoginApp: Sendable, Equatable {
    let name: String
    let path: String

    /// Parses the list script's output: one "name<TAB>path" per line.
    static func parse(_ output: String) -> [OpenAtLoginApp] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[1].hasPrefix("/"), parts[1] != "missing value" else { return nil }
            return OpenAtLoginApp(name: parts[0], path: parts[1].hasSuffix("/") ? String(parts[1].dropLast()) : parts[1])
        }
    }
}


nonisolated enum StartupControlError: LocalizedError, Equatable {
    /// The user said no to CachePop controlling System Events.
    case notAllowed
    /// The administrator password prompt was cancelled.
    case cancelled
    case failed(String)
    /// A label or path with characters CachePop won't pass to a shell.
    case unsafe

    /// What `osascript` reported, e.g. "execution error: Not authorized to send Apple events to
    /// System Events. (-1743)".
    static func fromOsascript(_ stderr: String) -> StartupControlError {
        let code = stderr.range(of: #"\((-?\d+)\)\s*$"#, options: .regularExpression)
            .flatMap { Int(stderr[$0].trimmingCharacters(in: CharacterSet(charactersIn: "() \n"))) }
        switch code {
        case -128: return .cancelled
        case -1743, -10004: return .notAllowed
        default:
            let message = stderr.components(separatedBy: "execution error: ").last?
                .replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failed(message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAllowed: "CachePop isn't allowed to change Login Items. Allow it in Privacy & Security › Automation."
        case .cancelled: "Cancelled."
        case .failed(let message): message.isEmpty ? "macOS refused the change." : message
        case .unsafe: "Its name has characters CachePop won't pass to the system."
        }
    }
}


/// Reads and changes what starts with the Mac. The live one changes the real system; demo
/// mode and tests use `DemoStartupControl`.
nonisolated protocol StartupControlling: Sendable {
    func overrides() async -> LaunchOverrides
    /// The Open at Login apps. Throws `.notAllowed` when the user declined Automation access.
    func openAtLoginApps() async throws -> [OpenAtLoginApp]
    /// Turns an item on or off now and from the next login or startup on.
    func set(_ item: LoginItem, on: Bool) async throws
}
