import AppKit
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

/// The real Mac. Agents switch with `launchctl` in your own session (no password); daemons
/// ask macOS for an administrator password; apps go through System Events.
nonisolated struct LiveStartupControl: StartupControlling {
    var runner: any CommandRunning = ProcessCommandRunner()

    private static let launchctl = URL(fileURLWithPath: "/bin/launchctl")
    private static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
    private var session: String { "gui/\(getuid())" }

    func overrides() async -> LaunchOverrides {
        async let gui = launchctl(["print-disabled", session])
        async let system = launchctl(["print-disabled", "system"])
        return LaunchOverrides(gui: LaunchOverrides.parse(await gui?.stdout ?? ""),
                               system: LaunchOverrides.parse(await system?.stdout ?? ""))
    }

    func openAtLoginApps() async throws -> [OpenAtLoginApp] {
        let script = """
        tell application "System Events"
            set output to ""
            repeat with anItem in login items
                set output to output & (name of anItem) & tab & (path of anItem) & linefeed
            end repeat
            return output
        end tell
        """
        return OpenAtLoginApp.parse(try await systemEvents(script))
    }

    func set(_ item: LoginItem, on: Bool) async throws {
        switch item.kind {
        case .userAgent, .sharedAgent:
            guard let label = item.label, Self.isSafeLabel(label) else { throw StartupControlError.unsafe }
            let target = "\(session)/\(label)"
            guard let result = await launchctl([on ? "enable" : "disable", target]), result.succeeded else {
                throw StartupControlError.failed("launchctl couldn't turn \(item.title) \(on ? "on" : "off").")
            }
            // Start or stop it now too. "Already running" or "not running" doesn't matter.
            _ = await launchctl(on ? ["bootstrap", session, item.path] : ["bootout", target])

        case .daemon:
            guard let label = item.label, Self.isSafeLabel(label), Self.isSafePath(item.path),
                  item.path.hasPrefix("/Library/LaunchDaemons/") else { throw StartupControlError.unsafe }
            let command = on
                ? "/bin/launchctl enable system/\(label) && (/bin/launchctl bootstrap system '\(item.path)' 2>/dev/null; true)"
                : "/bin/launchctl disable system/\(label) && (/bin/launchctl bootout system/\(label) 2>/dev/null; true)"
            _ = try await AppleScriptRunner.run("do shell script \"\(command)\" with administrator privileges")

        case .openAtLogin:
            guard Self.isSafePath(item.path) else { throw StartupControlError.unsafe }
            let script = on
                ? "tell application \"System Events\" to make login item at end with properties {path:\"\(item.path)\", hidden:false}"
                : "tell application \"System Events\" to delete (every login item whose path is \"\(item.path)\")"
            _ = try await systemEvents(script)
        }
    }

    private func launchctl(_ arguments: [String]) async -> CommandOutput? {
        try? await runner.run(ToolCommand(executable: Self.launchctl, arguments: arguments), timeout: 15)
    }

    /// Talks to System Events through `osascript`, off the main thread. System Events can take
    /// seconds to start, and in-process AppleScript would hold the window still meanwhile.
    /// macOS still asks on CachePop's behalf, since CachePop starts `osascript`; the long
    /// timeout leaves time to answer that question the first time.
    private func systemEvents(_ script: String) async throws -> String {
        guard let output = try? await runner.run(ToolCommand(executable: Self.osascript, arguments: ["-e", script]), timeout: 120) else {
            throw StartupControlError.failed("")
        }
        guard output.succeeded else { throw StartupControlError.fromOsascript(output.stderr) }
        return output.stdout
    }

    /// launchd labels are reverse-DNS names; anything else is refused rather than escaped.
    static func isSafeLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    /// An absolute path without quotes, backslashes or line breaks, so it can sit inside the
    /// quoted strings above unchanged.
    static func isSafePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains { "\"'\\\n\r`$".contains($0) }
    }
}

/// Runs AppleScript in CachePop itself, so macOS names CachePop in the administrator password
/// prompt. NSAppleScript belongs on the main thread; reading Login Items uses `osascript` instead.
nonisolated enum AppleScriptRunner {
    @MainActor
    static func run(_ source: String) async throws -> String {
        guard let script = NSAppleScript(source: source) else { throw StartupControlError.failed("") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            switch code {
            case -128: throw StartupControlError.cancelled
            case -1743, -10004: throw StartupControlError.notAllowed
            default: throw StartupControlError.failed(error[NSAppleScript.errorMessage] as? String ?? "")
            }
        }
        return result.stringValue ?? ""
    }
}

/// Demo mode and the test host: remembers changes in memory and never touches the system.
nonisolated final class DemoStartupControl: StartupControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var state = LaunchOverrides()
    private var apps: [OpenAtLoginApp]

    init(apps: [OpenAtLoginApp] = []) {
        self.apps = apps
    }

    func overrides() async -> LaunchOverrides {
        lock.withLock { state }
    }

    func openAtLoginApps() async throws -> [OpenAtLoginApp] {
        lock.withLock { apps }
    }

    func set(_ item: LoginItem, on: Bool) async throws {
        try await Task.sleep(for: .milliseconds(150))
        lock.withLock {
            switch item.kind {
            case .userAgent, .sharedAgent: if let label = item.label { state.gui[label] = !on }
            case .daemon: if let label = item.label { state.system[label] = !on }
            case .openAtLogin:
                apps.removeAll { $0.path == item.path }
                if on { apps.append(OpenAtLoginApp(name: item.title, path: item.path)) }
            }
        }
    }
}
