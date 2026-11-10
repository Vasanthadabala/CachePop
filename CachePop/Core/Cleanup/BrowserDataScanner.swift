import Foundation

/// History and cookies in Safari, Chromium browsers and Firefox. Never preselected: clearing
/// history can't be undone, and clearing cookies signs you out of websites. Each browser is
/// skipped while it's open, since it rewrites these files as it runs.
nonisolated enum BrowserDataScanner {
    nonisolated struct Chromium: Sendable {
        let name: String
        /// Under ~/Library/Application Support.
        let folder: String
        let bundleIDPrefixes: [String]
        let executable: String
    }

    static let chromiumBrowsers: [Chromium] = [
        Chromium(name: "Chrome", folder: "Google/Chrome", bundleIDPrefixes: ["com.google.chrome"], executable: "Google Chrome"),
        Chromium(name: "Brave", folder: "BraveSoftware/Brave-Browser", bundleIDPrefixes: ["com.brave.browser"], executable: "Brave Browser"),
        Chromium(name: "Edge", folder: "Microsoft Edge", bundleIDPrefixes: ["com.microsoft.edgemac"], executable: "Microsoft Edge"),
        Chromium(name: "Arc", folder: "Arc/User Data", bundleIDPrefixes: ["company.thebrowser.browser"], executable: "Arc"),
        Chromium(name: "Vivaldi", folder: "Vivaldi", bundleIDPrefixes: ["com.vivaldi.vivaldi"], executable: "Vivaldi"),
        Chromium(name: "Chromium", folder: "Chromium", bundleIDPrefixes: ["org.chromium.chromium"], executable: "Chromium")
    ]

    /// Inside each profile: visits, typed addresses and the address bar's suggestions from them.
    static let chromiumHistoryFiles = [
        "History", "History-journal", "Visited Links", "Top Sites", "Top Sites-journal",
        "Shortcuts", "Shortcuts-journal", "Network Action Predictor", "Network Action Predictor-journal"
    ]
    static let chromiumCookieFiles = [
        "Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal",
        "Extension Cookies", "Extension Cookies-journal"
    ]

    /// Inside ~/Library/Safari.
    static let safariHistoryFiles = ["History.db", "History.db-shm", "History.db-wal", "History.db-lock"]
    /// Relative to home: the sandboxed location since macOS 14, then the older one.
    static let safariCookieFiles = [
        "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        "Library/Cookies/Cookies.binarycookies"
    ]

    static let firefoxProfiles = "Library/Application Support/Firefox/Profiles"
    static let firefoxCookieFiles = ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm"]
    static let sqlite = URL(fileURLWithPath: "/usr/bin/sqlite3")

    /// Clears visits from Firefox's places database but keeps bookmarks and keywords, which live
    /// in the same file. One transaction, so a failure changes nothing.
    static let firefoxClearHistorySQL = [
        "BEGIN;",
        "DELETE FROM moz_historyvisits;",
        "DELETE FROM moz_inputhistory;",
        "DELETE FROM moz_places WHERE foreign_count = 0;",
        "UPDATE moz_places SET visit_count = 0, last_visit_date = NULL;",
        "DELETE FROM moz_annos WHERE place_id NOT IN (SELECT id FROM moz_places);",
        "DELETE FROM moz_origins WHERE id NOT IN (SELECT origin_id FROM moz_places);",
        "COMMIT;",
        "VACUUM;"
    ].joined(separator: " ")

    static func scan(_ context: ScanContext) -> CleanupGroup {
        var items = safari(context)
        for browser in chromiumBrowsers {
            items += chromium(browser, context)
        }
        items += firefox(context)
        return CleanupGroup(kind: .browsers, items: items)
    }

    // MARK: Safari

    static let safariCheck = InUseCheck.runningApp(bundleIDPrefixes: ["com.apple.safari"], executableNames: ["Safari"], name: "Safari")

    static func safari(_ context: ScanContext) -> [CleanupItem] {
        var items: [CleanupItem] = []
        let library = context.env.path("Library/Safari")

        if context.exists(library) {
            if (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) == nil {
                items.append(blockedForFullDiskAccess(id: "browsers.safari.history", title: "Safari history", kind: .history, browser: "Safari"))
            } else {
                let files = safariHistoryFiles.map { library.appendingPathComponent($0) }.filter(context.exists)
                if let item = makeItem(id: "browsers.safari.history", browser: "Safari", kind: .history, files: files, profiles: 1,
                                       check: safariCheck, context: context,
                                       note: "If Safari syncs with iCloud, your other devices can bring history back.") {
                    items.append(item)
                }
            }
        }

        let container = context.env.path("Library/Containers/com.apple.Safari/Data/Library/Cookies")
        if context.exists(container), (try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) == nil {
            items.append(blockedForFullDiskAccess(id: "browsers.safari.cookies", title: "Safari cookies", kind: .cookies, browser: "Safari"))
        } else {
            let files = safariCookieFiles.map { context.env.home.appendingPathComponent($0) }.filter(context.exists)
            if let item = makeItem(id: "browsers.safari.cookies", browser: "Safari", kind: .cookies, files: files, profiles: 1,
                                   check: safariCheck, context: context) {
                items.append(item)
            }
        }
        return items
    }

    // MARK: Chromium

    /// Profiles are the folders holding a Preferences file: Default, Profile 1, Guest Profile…
    static func chromiumProfiles(in folder: URL) -> [URL] {
        FileManager.default.children(of: folder).filter { profile in
            FileManager.default.isDirectory(profile)
                && FileManager.default.fileExists(atPath: profile.appendingPathComponent("Preferences").path)
        }
    }

    static func chromium(_ browser: Chromium, _ context: ScanContext) -> [CleanupItem] {
        let folder = context.env.path("Library/Application Support/\(browser.folder)")
        let id = browser.name.lowercased()
        if context.exists(folder), (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) == nil {
            return [
                blockedForFullDiskAccess(id: "browsers.\(id).history", title: "\(browser.name) history", kind: .history, browser: browser.name),
                blockedForFullDiskAccess(id: "browsers.\(id).cookies", title: "\(browser.name) cookies", kind: .cookies, browser: browser.name)
            ]
        }
        let profiles = chromiumProfiles(in: folder)
        guard !profiles.isEmpty else { return [] }

        let check = InUseCheck.runningApp(bundleIDPrefixes: browser.bundleIDPrefixes, executableNames: [browser.executable], name: browser.name)
        func files(_ names: [String]) -> [URL] {
            profiles.flatMap { profile in names.map { profile.appendingPathComponent($0) } }.filter(context.exists)
        }
        return [
            makeItem(id: "browsers.\(id).history", browser: browser.name, kind: .history,
                     files: files(chromiumHistoryFiles), profiles: profiles.count, check: check, context: context),
            makeItem(id: "browsers.\(id).cookies", browser: browser.name, kind: .cookies,
                     files: files(chromiumCookieFiles), profiles: profiles.count, check: check, context: context)
        ].compactMap { $0 }
    }

    // MARK: Firefox

    static let firefoxCheck = InUseCheck.runningApp(bundleIDPrefixes: ["org.mozilla.firefox"], executableNames: ["firefox"], name: "Firefox")

    static func firefox(_ context: ScanContext) -> [CleanupItem] {
        let profiles = FileManager.default.children(of: context.env.path(firefoxProfiles))
            .filter { FileManager.default.isDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !profiles.isEmpty else { return [] }

        var items: [CleanupItem] = []
        let blocked = inUseReason(for: firefoxCheck, processes: context.processes)

        // History shares its database with bookmarks, so it's cleared inside the database,
        // one profile per row.
        let withHistory = profiles.filter { context.exists($0.appendingPathComponent("places.sqlite")) }
        for profile in withHistory {
            let places = profile.appendingPathComponent("places.sqlite")
            let size = DirectorySizer.size(of: places)
            let name = firefoxProfileName(profile.lastPathComponent)
            items.append(CleanupItem(
                id: "browsers.firefox.history.\(profile.lastPathComponent)",
                group: .browsers,
                title: "Firefox history",
                explanation: Kind.history.explanation,
                detail: withHistory.count > 1 ? "Profile \(name)" : nil,
                sizeBytes: size.bytes,
                sizeIsUpperBound: true,
                actions: [CleanupAction(
                    id: "clear",
                    title: "Clear",
                    operation: .command(ToolCommand(executable: sqlite, arguments: ["-bail", places.path, firefoxClearHistorySQL])),
                    regeneration: .permanent,
                    explanation: "Clears visits from Firefox's history. Bookmarks stay."
                )],
                isRecommended: false,
                blockedReason: blocked,
                inUseCheck: firefoxCheck
            ))
        }

        let cookies = profiles.flatMap { profile in firefoxCookieFiles.map { profile.appendingPathComponent($0) } }.filter(context.exists)
        if let item = makeItem(id: "browsers.firefox.cookies", browser: "Firefox", kind: .cookies, files: cookies,
                               profiles: profiles.filter { context.exists($0.appendingPathComponent("cookies.sqlite")) }.count,
                               check: firefoxCheck, context: context) {
            items.append(item)
        }
        return items
    }

    /// "abcd1234.default-release" → "default-release".
    static func firefoxProfileName(_ folder: String) -> String {
        guard let dot = folder.firstIndex(of: ".") else { return folder }
        return String(folder[folder.index(after: dot)...])
    }

    // MARK: Items

    nonisolated enum Kind {
        case history, cookies

        var explanation: String {
            switch self {
            case .history: "Sites you've visited and what you typed in the address bar. Bookmarks and saved passwords aren't touched."
            case .cookies: "What websites store to remember you, such as being signed in."
            }
        }
    }

    static func makeItem(id: String, browser: String, kind: Kind, files: [URL], profiles: Int,
                         check: InUseCheck, context: ScanContext, note: String? = nil) -> CleanupItem? {
        guard !files.isEmpty else { return nil }
        let size = DirectorySizer.size(ofAll: files)
        guard size.bytes > 0 else { return nil }
        return CleanupItem(
            id: id,
            group: .browsers,
            title: "\(browser) \(kind == .history ? "history" : "cookies")",
            explanation: kind.explanation,
            detail: profiles > 1 ? "\(profiles) profiles" : nil,
            sizeBytes: size.bytes,
            actions: [CleanupAction(
                id: "delete",
                title: "Clear",
                operation: .delete(files),
                regeneration: .permanent,
                explanation: kind == .history
                    ? "Cleared. \(browser) starts a new history."
                    : "Cleared. You'll need to sign in to websites in \(browser) again."
            )],
            isRecommended: false,
            warning: kind == .cookies ? "Signs you out of websites in \(browser)." : nil,
            note: note,
            blockedReason: inUseReason(for: check, processes: context.processes),
            inUseCheck: check
        )
    }

    static func blockedForFullDiskAccess(id: String, title: String, kind: Kind, browser: String) -> CleanupItem {
        CleanupItem(
            id: id,
            group: .browsers,
            title: title,
            explanation: kind.explanation,
            sizeBytes: 0,
            actions: [CleanupAction(id: "delete", title: "Clear", operation: .delete([]), regeneration: .permanent,
                                    explanation: "Cleared.")],
            isRecommended: false,
            blockedReason: "CachePop needs Full Disk Access to see \(browser)'s \(kind == .history ? "history" : "cookies").",
            needsFullDiskAccess: true
        )
    }

    // MARK: Path safety

    /// True when `relativeLower` (home-relative, lowercased) is exactly one of the history or
    /// cookie files above. Nothing else in a browser's folders qualifies.
    static func isBrowserDataFile(relativeLower: String) -> Bool {
        if safariHistoryFiles.contains(where: { relativeLower == "library/safari/" + $0.lowercased() }) { return true }
        if safariCookieFiles.contains(where: { relativeLower == $0.lowercased() }) { return true }

        let support = "library/application support/"
        guard relativeLower.hasPrefix(support) else { return false }
        let rest = relativeLower.dropFirst(support.count)

        for browser in chromiumBrowsers {
            let prefix = browser.folder.lowercased() + "/"
            guard rest.hasPrefix(prefix) else { continue }
            let inBrowser = rest.dropFirst(prefix.count)
            guard let slash = inBrowser.firstIndex(of: "/") else { return false }
            let file = inBrowser[inBrowser.index(after: slash)...]
            return (chromiumHistoryFiles + chromiumCookieFiles).contains { $0.lowercased() == file }
        }

        let firefox = "firefox/profiles/"
        if rest.hasPrefix(firefox) {
            let parts = rest.dropFirst(firefox.count).split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && firefoxCookieFiles.contains(String(parts[1]))
        }
        return false
    }
}
