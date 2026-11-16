import AppKit
import Foundation

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
