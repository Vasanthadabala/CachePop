import Foundation

/// The last line of defence before anything is removed.
///
/// Every file the cleaner deletes or trashes must sit strictly inside one of a short list of
/// known cache locations under the home folder, and never inside a protected one (documents,
/// Mail, keychains, Photos…). Paths are canonicalised first, so a symlink or `..` can't smuggle
/// a deletion out of a cache folder.
nonisolated enum PathSafety {
    nonisolated enum Mode: Sendable {
        case delete
        case trash
    }

    nonisolated struct Root: Sendable {
        let relativePath: String
        let allowsPermanentDelete: Bool
    }

    /// The only places CachePop removes files from, relative to the home folder.
    static let roots: [Root] = [
        Root(relativePath: "Library/Developer/Xcode/DerivedData", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/iOS DeviceSupport", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/tvOS DeviceSupport", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/visionOS DeviceSupport", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/xrOS DeviceSupport", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/macOS DeviceSupport", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/DocumentationCache", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/Archives", allowsPermanentDelete: false),
        Root(relativePath: "Library/Developer/CoreSimulator/Caches", allowsPermanentDelete: true),
        Root(relativePath: "Library/Caches", allowsPermanentDelete: true),
        Root(relativePath: "Library/Logs", allowsPermanentDelete: true),
        Root(relativePath: ".npm", allowsPermanentDelete: true),
        Root(relativePath: ".gradle/caches", allowsPermanentDelete: true),
        Root(relativePath: ".gradle/wrapper/dists", allowsPermanentDelete: true),
        Root(relativePath: ".cache", allowsPermanentDelete: true),
        Root(relativePath: ".cocoapods/repos", allowsPermanentDelete: true),
        Root(relativePath: ".m2/repository", allowsPermanentDelete: true),
        Root(relativePath: ".cargo/registry/cache", allowsPermanentDelete: true),
        Root(relativePath: ".bun/install/cache", allowsPermanentDelete: true),
        Root(relativePath: ".android/cache", allowsPermanentDelete: true),
        Root(relativePath: ".pub-cache", allowsPermanentDelete: true),
        // Codex's caches only; the rest of ~/.codex (conversations, images) is never touched.
        Root(relativePath: ".codex/cache", allowsPermanentDelete: true),
        Root(relativePath: ".codex/.tmp", allowsPermanentDelete: true),
        Root(relativePath: ".codex/plugins/cache", allowsPermanentDelete: true),
        // Coding tools' data for projects that are gone: conversations, so Trash only.
        Root(relativePath: ".claude/projects", allowsPermanentDelete: false),
        Root(relativePath: ".codex/sessions", allowsPermanentDelete: false),
        Root(relativePath: ".Trash", allowsPermanentDelete: true),
        // Android emulators and the system images they boot from.
        Root(relativePath: ".android/avd", allowsPermanentDelete: true),
        Root(relativePath: "Library/Android/sdk/system-images", allowsPermanentDelete: true),
        // iOS and iPadOS restore files Finder downloaded.
        Root(relativePath: "Library/iTunes/iPhone Software Updates", allowsPermanentDelete: true),
        Root(relativePath: "Library/iTunes/iPad Software Updates", allowsPermanentDelete: true),
        Root(relativePath: "Library/iTunes/iPod Software Updates", allowsPermanentDelete: true),
        // User-visible files are only ever moved to the Trash, never deleted outright.
        Root(relativePath: "Downloads", allowsPermanentDelete: false)
    ]

    /// Inside protected folders, exactly one level down: places that hold one app's or one
    /// device's data each. These may only ever be moved to the Trash, and only entries that
    /// look like an app identifier (never Apple's own).
    static let trashOnlyAppDataRoots: [String] = [
        "Library/Application Support", "Library/Containers", "Library/Group Containers",
        "Library/Preferences", "Library/Saved Application State", "Library/HTTPStorages",
        "Library/WebKit"
    ]

    /// Device backups Finder made, one folder per device. Trash only.
    static let deviceBackupsRoot = "Library/Application Support/MobileSync/Backup"

    /// Never touched, even if a cache root somehow pointed inside them.
    static let protectedPaths: [String] = [
        "Documents", "Desktop", "Pictures", "Movies", "Music", "Public",
        "Library/Mail", "Library/Keychains", "Library/Messages", "Library/Photos",
        "Library/Mobile Documents", "Library/CloudStorage", "Library/Application Support",
        "Library/Containers", "Library/Group Containers", "Library/Preferences",
        "Library/Safari", "Library/Cookies", "Library/Accounts",
        ".ssh", ".gnupg", ".config"
    ]

    /// Source and personal-data markers. A path containing one of these is refused even inside
    /// a cache root — a stray project checkout in `~/.cache` must not be deleted.
    static let protectedNameFragments: [String] = [
        ".photoslibrary/", ".keychain/", ".keychain-db/", ".git/"
    ]

    /// Returns nil when `target` may be removed in `mode`, otherwise the reason it may not.
    static func violation(for target: URL, mode: Mode, home: URL) -> String? {
        // `standardizedFileURL` drops ".." without following links, but the cleaner removes
        // `target` itself, which the system resolves through them: "cache/link/../x" would be
        // checked as "cache/x" yet remove "<link's target>/../x". Refuse such paths outright.
        guard !target.pathComponents.contains("..") else {
            return "Refused an unusual path: \(target.path)"
        }
        let standardized = target.standardizedFileURL
        let name = standardized.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else {
            return "Refused an unusual path: \(target.path)"
        }

        guard let realHome = canonicalPath(home),
              let parent = canonicalPath(standardized.deletingLastPathComponent()) else {
            return "\(target.path) no longer exists."
        }

        let fullPath = parent.hasSuffix("/") ? parent + name : parent + "/" + name
        let homePrefix = realHome.lowercased() + "/"
        guard fullPath.lowercased().hasPrefix(homePrefix) else {
            return "\(target.path) is outside your home folder."
        }

        let relative = String(fullPath.dropFirst(homePrefix.count))
        let relativeLower = relative.lowercased()

        for fragment in protectedNameFragments where (relativeLower + "/").contains(fragment) {
            return "\(name) looks like personal data or source code."
        }

        if let allowedMode = appSupportException(relativeLower: relativeLower) {
            return mode == .delete && allowedMode == .trash ? "\(name) is only ever moved to the Trash." : nil
        }

        if let allowed = trashOnlyException(relativeLower: relativeLower, name: name) {
            guard allowed else { return "\(name) belongs to macOS and is never cleaned." }
            return mode == .trash ? nil : "\(name) is only ever moved to the Trash."
        }

        for protected in protectedPaths {
            let protectedLower = protected.lowercased()
            if relativeLower == protectedLower || relativeLower.hasPrefix(protectedLower + "/") {
                return "\(protected) is protected and never cleaned."
            }
        }

        guard let root = roots.first(where: { relativeLower.hasPrefix($0.relativePath.lowercased() + "/") }) else {
            return "\(name) isn't in a location CachePop cleans."
        }

        if mode == .delete, !root.allowsPermanentDelete {
            return "Files in \(root.relativePath) are only ever moved to the Trash."
        }

        return nil
    }

    /// Chromium's cache folders, which web-technology apps (Claude, VS Code, Slack…) keep in
    /// their Application Support folder. Lowercased.
    static let appWebCacheFolderNames: Set<String> = [
        "cache", "code cache", "gpucache", "dawngraphitecache", "dawnwebgpucache",
        "graphitedawncache", "shadercache", "grshadercache"
    ]

    /// VS Code-based editors' Application Support folders, and their extra cache folders.
    static let codeEditorFolderNames: Set<String> = [
        "code", "code - insiders", "cursor", "windsurf", "antigravity", "vscodium", "kiro", "trae", "void"
    ]
    static let codeEditorCacheFolderNames: Set<String> = ["cacheddata", "cachedextensionvsixs", "cachedprofilesdata"]

    /// The few places inside Application Support CachePop may clean, and how:
    /// - inside an app's web cache folder ("Claude/Cache/…"): delete;
    /// - one editor workspace entry ("Code/User/workspaceStorage/<id>"): Trash only;
    /// - inside Google's update downloads ("Google/GoogleUpdater/crx_cache/…"): delete.
    /// nil when none applies. Apple's own folders never qualify.
    static func appSupportException(relativeLower: String) -> Mode? {
        let prefix = "library/application support/"
        guard relativeLower.hasPrefix(prefix) else { return nil }
        let parts = relativeLower.dropFirst(prefix.count).split(separator: "/").map(String.init)
        guard let app = parts.first, !app.hasPrefix("com.apple"), !app.hasPrefix("apple") else { return nil }

        if parts.count >= 3, appWebCacheFolderNames.contains(parts[1]) { return .delete }
        if parts.count >= 3, codeEditorFolderNames.contains(app), codeEditorCacheFolderNames.contains(parts[1]) { return .delete }
        if parts.count == 4, codeEditorFolderNames.contains(app), parts[1] == "user", parts[2] == "workspacestorage" { return .trash }
        if parts.count >= 4, app == "google", parts[1] == "googleupdater", parts[2] == "crx_cache" { return .delete }
        return nil
    }

    /// nil when `relativeLower` isn't directly inside a trash-only root; otherwise whether the
    /// entry may be moved to the Trash.
    private static func trashOnlyException(relativeLower: String, name: String) -> Bool? {
        let backups = deviceBackupsRoot.lowercased() + "/"
        if relativeLower.hasPrefix(backups) {
            return !relativeLower.dropFirst(backups.count).contains("/")
        }
        for root in trashOnlyAppDataRoots {
            let prefix = root.lowercased() + "/"
            guard relativeLower.hasPrefix(prefix), !relativeLower.dropFirst(prefix.count).contains("/") else { continue }
            return looksLikeThirdPartyIdentifier(name)
        }
        return nil
    }

    /// "com.figma.Desktop", "ABCDE12345.com.foo.shared", "com.foo.app.plist" — but not Apple's
    /// own entries or plain names such as "AddressBook".
    static func looksLikeThirdPartyIdentifier(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), lower.contains("."), !lower.contains("com.apple."),
              !lower.hasPrefix("apple"), !lower.hasPrefix("systemgroup.") else { return false }
        return lower.split(separator: ".").count >= 3
    }

    /// `realpath(3)`: resolves symlinks and `..`, and keeps `/private` prefixes consistent.
    static func canonicalPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
