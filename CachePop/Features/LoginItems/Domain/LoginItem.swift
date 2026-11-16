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
