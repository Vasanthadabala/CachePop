import Foundation

/// The last line of defence before anything is removed.
///
/// Every file the cleaner deletes or trashes must sit strictly inside one of a short list of
/// known cache locations under the home folder, and never inside a protected one (documents,
/// Mail, keychains, Photos…). Paths are canonicalised first, so a symlink or `..` can't smuggle
/// a deletion out of a cache folder.
/// Reviewed generated app bundles have a separate Trash-only exception for custom build paths.
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
        // Crash reports Xcode copied from devices (DeviceLogs since Xcode 15).
        Root(relativePath: "Library/Developer/Xcode/DeviceLogs", allowsPermanentDelete: true),
        Root(relativePath: "Library/Developer/Xcode/iOS Device Logs", allowsPermanentDelete: true),
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
        // Models downloaded to run on this Mac.
        Root(relativePath: ".ollama/models", allowsPermanentDelete: true),
        Root(relativePath: ".lmstudio/models", allowsPermanentDelete: true),
        // Login items whose program is gone. Trash only, so they can be put back.
        Root(relativePath: "Library/LaunchAgents", allowsPermanentDelete: false),
        // User-visible files are only ever moved to the Trash, never deleted outright.
        Root(relativePath: "Downloads", allowsPermanentDelete: false)
    ]

    /// Folders inside protected places that may still be cleaned, strictly inside.
    static let protectedFolderExceptions: [Root] = [
        // Copies Mail made of attachments you opened; the messages keep the originals.
        Root(relativePath: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", allowsPermanentDelete: true)
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

    /// Android Studio's system directory mixes disposable caches with recovery history.
    /// Unknown children, plugins and LocalHistory are deliberately absent.
    static let androidStudioCacheFolderNames: Set<String> = [
        "caches", "index", "tmp", "compiler", "compile-server", "global-model-cache",
        "lint", "gmaven.index", "sdk_index"
    ]

    /// Returns nil when `target` may be removed in `mode`, otherwise the reason it may not.
    static func violation(for target: URL, mode: Mode, home: URL, appBuildBundleID: String? = nil) -> String? {
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

        // Only a reviewed app-build item may use this exception. Ordinary cleanup operations
        // still stay inside the known home-folder roots. Never allow permanent deletion here.
        if let appBuildBundleID {
            guard mode == .trash, AppBuildScanner.isDisposableBuild(target, expectedBundleID: appBuildBundleID) else {
                return "\(name) is no longer a disposable app build. Scan again before cleaning it."
            }
            return nil
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

        if mode == .delete {
            let google = "library/caches/google"
            if relativeLower == google || relativeLower == "library/caches/jetbrains" {
                return "Shared IDE and vendor cache folders are never removed as a whole."
            }
            let parts = relativeLower.split(separator: "/").map(String.init)
            if parts.count >= 4, parts.prefix(3).joined(separator: "/") == google,
               parts[3].hasPrefix("androidstudio"),
               (parts.count < 5 || !androidStudioCacheFolderNames.contains(parts[4])) {
                return "Android Studio's Local History, settings and plugins are kept."
            }
            if parts.count >= 4, parts.prefix(3).joined(separator: "/") == "library/caches/jetbrains",
               (IDECachePolicy.product(for: parts[3]) == nil || parts.count < 5 || !androidStudioCacheFolderNames.contains(parts[4])) {
                return "IDE Local History, settings, plugins and unknown data are kept."
            }
            // Do not follow a cache parent redirected after scanning, even into another
            // otherwise eligible cache. The selected app may differ from the new owner.
            let requestedHome = home.standardizedFileURL.path
            let requested = standardized.path
            if requested.lowercased().hasPrefix(requestedHome.lowercased() + "/") {
                let expected = realHome + requested.dropFirst(requestedHome.count)
                if fullPath.lowercased() != expected.lowercased() {
                    return "The cache location changed. Scan again before cleaning it."
                }
            }
        }

        for fragment in protectedNameFragments where (relativeLower + "/").contains(fragment) {
            return "\(name) looks like personal data or source code."
        }

        // Exactly the history and cookie files of known browsers, nothing else in their folders.
        if BrowserDataScanner.isBrowserDataFile(relativeLower: relativeLower) {
            return nil
        }

        if let exception = protectedFolderExceptions.first(where: { relativeLower.hasPrefix($0.relativePath.lowercased() + "/") }) {
            return mode == .delete && !exception.allowsPermanentDelete ? "\(name) is only ever moved to the Trash." : nil
        }

        if let allowedMode = appSupportException(relativeLower: relativeLower) {
            let supportParts = relative.split(separator: "/").dropFirst(2).map(String.init)
            if let layout = nestedWebCacheLayout(supportParts.map { $0.lowercased() }) {
                let root = URL(fileURLWithPath: realHome).appendingPathComponent(
                    "Library/Application Support/" + supportParts.prefix(layout.rootLength).joined(separator: "/")
                )
                let markers = Set(FileManager.default.children(of: root).map { $0.lastPathComponent.lowercased() })
                guard codeEditorFolderNames.contains(root.lastPathComponent.lowercased()) || !markers.isDisjoint(with: chromiumMarkers) else {
                    return "Couldn't confirm this app's web cache. Scan again before cleaning it."
                }
                if layout.hasProfile {
                    let profile = root.appendingPathComponent(supportParts[layout.rootLength])
                    guard FileManager.default.fileExists(atPath: profile.appendingPathComponent("Preferences").path) else {
                        return "This browser profile changed. Scan again before cleaning it."
                    }
                }
            }
            return mode == .delete && allowedMode == .trash ? "\(name) is only ever moved to the Trash." : nil
        }

        let containerParts = relativeLower.split(separator: "/").map(String.init)
        if containerParts.count >= 7, containerParts[0] == "library", containerParts[1] == "containers",
           isThirdPartyContainer(containerParts[2]), Array(containerParts[3...5]) == ["data", "library", "caches"] {
            return nil
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
        "cache", "code cache", "gpucache", "gpupersistentcache", "dawngraphitecache", "dawnwebgpucache",
        "graphitedawncache", "shadercache", "grshadercache"
    ]

    /// VS Code-based editors' Application Support folders, and their extra cache folders.
    static let codeEditorFolderNames: Set<String> = [
        "code", "code - insiders", "cursor", "windsurf", "antigravity", "vscodium", "kiro", "trae", "void"
    ]
    static let codeEditorCacheFolderNames: Set<String> = ["cacheddata", "cachedextensionvsixs", "cachedprofilesdata"]

    static let chromiumVendorPaths: Set<String> = [
        "google/chrome", "google/chrome canary", "bravesoftware/brave-browser", "arc/user data"
    ]

    static let chromiumMarkers: Set<String> = [
        "local storage", "local state", "network persistent state", "preferences", "session storage"
    ]

    static func isChromiumProfile(_ name: String) -> Bool {
        ["default", "guest profile", "system profile"].contains(name)
            || name.range(of: "^profile [0-9]+$", options: .regularExpression) != nil
    }

    static func isThirdPartyContainer(_ id: String) -> Bool {
        id.split(separator: ".").count >= 3 && !id.hasPrefix("com.apple.") && !id.contains("/")
    }

    private static func nestedWebCacheLayout(_ parts: [String]) -> (rootLength: Int, hasProfile: Bool)? {
        for rootLength in [1, 2] where parts.count > rootLength {
            if rootLength == 2, !chromiumVendorPaths.contains(parts.prefix(2).joined(separator: "/")) { continue }
            let tail = Array(parts.dropFirst(rootLength))
            if rootLength == 2, tail.count >= 2, appWebCacheFolderNames.contains(tail[0]) { return (rootLength, false) }
            if tail.count >= 3, isChromiumProfile(tail[0]), appWebCacheFolderNames.contains(tail[1]) { return (rootLength, true) }
        }
        return nil
    }

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
        if nestedWebCacheLayout(parts) != nil { return .delete }
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
