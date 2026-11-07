import Foundation

/// Where an app keeps files in ~/Library, for "Uninstall completely". Read-only and pure, so
/// tests can run it on a fixture home.
///
/// Every result sits *inside* one of the Library folders below, never one of those folders
/// itself, and never a vendor folder shared by several apps ("Application Support/Google").
nonisolated enum AppLeftovers {
    struct Candidate: Equatable, Sendable {
        let url: URL
        let category: String
    }

    /// Library folders searched, with the label shown for what's found there.
    static let folders: [(path: String, category: String)] = [
        ("Library/Application Support", "Application Support"),
        ("Library/Caches", "Caches"),
        ("Library/Preferences", "Preferences"),
        ("Library/Saved Application State", "Saved State"),
        ("Library/Containers", "Containers"),
        ("Library/Group Containers", "Group Containers"),
        ("Library/HTTPStorages", "HTTP Storage"),
        ("Library/WebKit", "WebKit Data"),
        ("Library/Logs", "Logs"),
        ("Library/LaunchAgents", "Login Item")
    ]

    /// Apps that keep their data under a vendor folder instead of their bundle identifier.
    /// A trailing "*" matches any name starting with what's before it (version numbers).
    static let vendorFolders: [String: [String]] = [
        "com.google.chrome": ["Library/Application Support/Google/Chrome", "Library/Caches/Google/Chrome"],
        "com.google.chrome.canary": ["Library/Application Support/Google/Chrome Canary", "Library/Caches/Google/Chrome Canary"],
        "com.brave.browser": ["Library/Application Support/BraveSoftware/Brave-Browser", "Library/Caches/BraveSoftware/Brave-Browser"],
        "com.microsoft.edgemac": ["Library/Application Support/Microsoft Edge", "Library/Caches/Microsoft Edge"],
        "org.mozilla.firefox": ["Library/Application Support/Firefox", "Library/Caches/Firefox"],
        "com.google.android.studio": [
            "Library/Application Support/Google/AndroidStudio*",
            "Library/Caches/Google/AndroidStudio*",
            "Library/Logs/Google/AndroidStudio*"
        ]
    ]

    /// Folder names several apps share. An app's own name never claims one of these.
    static let sharedVendorNames: Set<String> = [
        "google", "microsoft", "bravesoftware", "jetbrains", "adobe", "mozilla", "apple",
        "openai", "anthropic", "github", "cloudflare", "logs", "caches", "preferences"
    ]

    static func candidates(bundleID: String, name: String, home: URL, otherBundleIDs: Set<String>,
                           fileManager: FileManager = .default) -> [Candidate] {
        let id = bundleID.lowercased()
        var found: [Candidate] = []
        var seen = Set<String>()

        func add(_ url: URL, _ category: String) {
            let key = url.standardizedFileURL.path.lowercased()
            guard fileManager.fileExists(atPath: url.path), seen.insert(key).inserted else { return }
            found.append(Candidate(url: url, category: category))
        }

        for folder in folders {
            let base = home.appendingPathComponent(folder.path, isDirectory: true)
            let entries = fileManager.children(of: base)

            for entry in entries {
                let entryName = entry.lastPathComponent.lowercased()
                if !id.isEmpty, belongs(entryName, to: id, others: otherBundleIDs, inGroupContainers: folder.category == "Group Containers") {
                    add(entry, folder.category)
                }
            }

            // "Application Support/Obsidian", "Logs/CCleaner": the app's own name, unless that
            // name is a vendor folder other apps use too.
            let ownName = name.lowercased()
            if !ownName.isEmpty, !ownName.contains("/"), !sharedVendorNames.contains(ownName),
               ["Application Support", "Caches", "Logs"].contains(folder.category),
               let entry = entries.first(where: { $0.lastPathComponent.lowercased() == ownName }) {
                add(entry, folder.category)
            }
        }

        for pattern in vendorFolders[id] ?? [] {
            let category = folders.first { pattern.hasPrefix($0.path + "/") }?.category ?? "Application Support"
            if pattern.hasSuffix("*") {
                let prefixURL = home.appendingPathComponent(String(pattern.dropLast()))
                let parent = prefixURL.deletingLastPathComponent()
                let start = prefixURL.lastPathComponent.lowercased()
                for entry in fileManager.children(of: parent) where entry.lastPathComponent.lowercased().hasPrefix(start) {
                    add(entry, category)
                }
            } else {
                add(home.appendingPathComponent(pattern), category)
            }
        }
        return found
    }

    /// Whether a Library entry is this app's: its identifier exactly, with a file extension
    /// (".plist", ".savedState", ".binarycookies"), or with a further component for a helper
    /// or extension ("…ShipIt", "…Intents") — unless that longer identifier is another
    /// installed app. Group containers may carry a "group." or team-ID prefix.
    static func belongs(_ entryName: String, to bundleID: String, others: Set<String>, inGroupContainers: Bool) -> Bool {
        var names = [entryName]
        if inGroupContainers {
            if entryName.hasPrefix("group.") { names.append(String(entryName.dropFirst(6))) }
            if let dot = entryName.firstIndex(of: "."), entryName.distance(from: entryName.startIndex, to: dot) == 10 {
                names.append(String(entryName[entryName.index(after: dot)...]))
            }
        }
        // A one-part identifier is too vague to match on.
        guard bundleID.contains(".") else { return false }

        return names.contains { name in
            guard name == bundleID || name.hasPrefix(bundleID + ".") else { return false }
            let rest = name.dropFirst(bundleID.count)
            if rest.isEmpty { return true }
            // Another installed app with a longer identifier owns it.
            return !others.contains { other in
                other.count > bundleID.count && (name == other || name.hasPrefix(other + "."))
            }
        }
    }
}
