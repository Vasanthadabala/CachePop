import AppKit
import Foundation

/// Something that starts on its own: a launch agent or daemon, or an app.
nonisolated struct LoginItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        /// ~/Library/LaunchAgents: starts when you log in.
        case userAgent
        /// /Library/LaunchAgents: starts in every user's session.
        case sharedAgent
        /// /Library/LaunchDaemons: starts with the Mac, for everyone.
        case daemon
        /// Listed under Open at Login in System Settings.
        case openAtLogin
    }

    /// Whether an agent really starts by itself, which decides if Login Items shows it.
    enum Role: Sendable {
        /// Runs at login or startup, stays running, or wakes on a schedule. Worth a switch.
        case startsOnItsOwn
        /// Only starts when its app asks for it (a Mach service or socket). Turning it off
        /// saves nothing at login and can break the app.
        case onDemand
        /// A daemon an app keeps running for it to work at all (a VPN's network service).
        case appService
        /// A file with nothing to run (Google leaves empty ones behind).
        case empty
    }

    let title: String
    /// The plist for agents and daemons, or the app bundle for apps.
    let path: String
    let kind: Kind
    /// launchd's name for it. nil for apps, and for plists that run nothing.
    var label: String?
    /// The app an agent belongs to, for its icon and name.
    var appPath: String?
    var isOn = true
    var role: Role = .startsOnItsOwn

    var id: String { path }
    var isAgent: Bool { kind == .userAgent || kind == .sharedAgent || kind == .daemon }
    /// Daemons belong to the whole Mac, so switching one asks for an administrator password.
    var needsAdmin: Bool { kind == .daemon }
    var canToggle: Bool { isAgent ? label != nil : kind == .openAtLogin }
    /// What Login Items lists: things that start on their own and can be stopped.
    var isListed: Bool { role == .startsOnItsOwn && canToggle }

    var typeLabel: String {
        switch kind {
        case .userAgent:     "Launch agent"
        case .sharedAgent:   "Launch agent · all users"
        case .daemon:        "Launch daemon"
        case .openAtLogin:   "Opens at login"
        }
    }

    /// The icon to show: the owning app's, else the plist's.
    var iconPath: String { appPath ?? path }
}

/// Lists third-party startup items. Read-only; `StartupControlling` makes the changes.
nonisolated enum LoginItemsScanner {
    /// Launch agents and daemons, with whether each is on. `overrides` is launchd's on/off
    /// record (`launchctl print-disabled`), which wins over the plist's own `Disabled` key.
    static func agents(home: URL, overrides: LaunchOverrides) -> [LoginItem] {
        launchItems(in: home.appendingPathComponent("Library/LaunchAgents"), kind: .userAgent, overrides: overrides.gui)
            + launchItems(in: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .sharedAgent, overrides: overrides.gui)
            + launchItems(in: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .daemon, overrides: overrides.system)
    }

    static func launchItems(in folder: URL, kind: LoginItem.Kind, overrides: [String: Bool] = [:]) -> [LoginItem] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                let name = url.deletingPathExtension().lastPathComponent
                let info = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
                let label = (info["Label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard !isApple(name), !isApple(label ?? "") else { return nil }

                let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
                let runsSomething = label != nil && program != nil
                let isDisabled = label.flatMap { overrides[$0] } ?? (info["Disabled"] as? Bool ?? false)
                let appPath = program.flatMap(appBundle(containing:))
                return LoginItem(
                    title: displayName(for: url, fallback: name),
                    path: url.path,
                    kind: kind,
                    label: runsSomething ? label : nil,
                    appPath: appPath,
                    isOn: runsSomething && !isDisabled,
                    role: runsSomething ? role(of: info, kind: kind, program: program ?? "") : .empty
                )
            }
    }

    /// Reads a launchd plist's start conditions.
    static func role(of info: [String: Any], kind: LoginItem.Kind, program: String) -> LoginItem.Role {
        let runAtLoad = info["RunAtLoad"] as? Bool == true
        let keepAlive = info["KeepAlive"] as? Bool == true || info["KeepAlive"] is [String: Any]
        let scheduled = info["StartInterval"] != nil || info["StartCalendarInterval"] != nil
        // A daemon kept running from inside an app (or its privileged helper) is that app's
        // engine: WARP's network service, Docker's vmnetd.
        let belongsToApp = appBundle(containing: program) != nil || program.hasPrefix("/Library/PrivilegedHelperTools/")
        if kind == .daemon, keepAlive, belongsToApp { return .appService }
        return runAtLoad || keepAlive || scheduled ? .startsOnItsOwn : .onDemand
    }

    static func isApple(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return lower.hasPrefix("com.apple.") || lower.hasPrefix("apple.")
    }

    /// "/Applications/Cloudflare WARP.app/Contents/MacOS/daemon" → "/Applications/Cloudflare WARP.app".
    static func appBundle(containing program: String) -> String? {
        guard let range = program.range(of: ".app/") else { return nil }
        return String(program[..<range.lowerBound]) + ".app"
    }

    /// "com.google.keystone.agent" → "Google Keystone Agent", unless the plist names a program
    /// inside an app bundle, in which case the app's name is clearer.
    static func displayName(for plist: URL, fallback: String) -> String {
        if let info = NSDictionary(contentsOf: plist) as? [String: Any] {
            let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
            if let program, let app = appBundle(containing: program) {
                return URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
            }
        }
        let parts = fallback.split(separator: ".").map(String.init).filter { !["com", "org", "net", "io", "plist"].contains($0.lowercased()) }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
