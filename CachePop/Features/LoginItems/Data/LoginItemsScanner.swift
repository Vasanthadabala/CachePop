import AppKit
import Foundation

/// Lists third-party startup items. Read-only; `StartupControlling` makes the changes.
nonisolated enum LoginItemsScanner {
    /// Launch agents and daemons, with whether each is on. `overrides` is launchd's on/off
    /// record (`launchctl print-disabled`), which wins over the plist's own `Disabled` key.
    static func agents(home: URL, overrides: LaunchOverrides, includeSystemItems: Bool = true) -> [LoginItem] {
        guard !Task.isCancelled else { return [] }
        let user = launchItems(in: home.appendingPathComponent("Library/LaunchAgents"), kind: .userAgent, overrides: overrides.gui)
        guard includeSystemItems else { return user }
        return user + launchItems(in: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .sharedAgent, overrides: overrides.gui)
            + launchItems(in: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .daemon, overrides: overrides.system)
    }

    static func launchItems(in folder: URL, kind: LoginItem.Kind, overrides: [String: Bool] = [:]) -> [LoginItem] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                guard !Task.isCancelled else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                let info = MetadataReader.propertyList(from: url) ?? [:]
                let label = (info["Label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                guard !isApple(name), !isApple(label ?? "") else { return nil }

                let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
                let runsSomething = label != nil && program != nil
                let isDisabled = label.flatMap { overrides[$0] } ?? (info["Disabled"] as? Bool ?? false)
                let appPath = program.flatMap(appBundle(containing:))
                return LoginItem(
                    title: displayName(for: url, fallback: name, info: info),
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
    static func displayName(for plist: URL, fallback: String, info: [String: Any]? = nil) -> String {
        if let info = info ?? MetadataReader.propertyList(from: plist) {
            let program = info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
            if let program, let app = appBundle(containing: program) {
                return URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
            }
        }
        let parts = fallback.split(separator: ".").map(String.init).filter { !["com", "org", "net", "io", "plist"].contains($0.lowercased()) }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
