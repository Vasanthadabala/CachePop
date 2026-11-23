import Foundation

/// Searches only platform cache directories and positively identified Chromium profiles.
/// It never recursively searches arbitrary user data for folders merely named "cache".
nonisolated enum AppCacheDiscovery {
    struct WebApp {
        let owner: String
        let folders: [URL]
    }

    static func sandboxCaches(_ context: ScanContext) -> [URL] {
        let installed = context.env.apps.installedBundleIDs()
        guard !installed.isEmpty else { return [] }
        return FileManager.default.children(of: context.env.path("Library/Containers")).compactMap { container in
            let id = container.lastPathComponent.lowercased()
            guard PathSafety.isThirdPartyContainer(id),
                  installed.contains(where: { id == $0 || id.hasPrefix($0 + ".") }), isRealDirectory(container) else { return nil }
            let caches = container.appendingPathComponent("Data/Library/Caches")
            return isRealDirectory(caches) ? caches : nil
        }
    }

    static func webApps(home: URL, excluding ownName: String) -> [WebApp] {
        let support = home.appendingPathComponent("Library/Application Support")
        var apps: [WebApp] = []
        for root in FileManager.default.children(of: support) where isRealDirectory(root) {
            let name = root.lastPathComponent.lowercased()
            guard !name.hasPrefix("com.apple"), !name.hasPrefix("apple"), name != ownName else { continue }
            var roots = [root]
            // Only known browser vendor roots, never an arbitrary subtree of app data.
            roots += PathSafety.chromiumVendorPaths.compactMap { relative in
                guard relative.hasPrefix(name + "/") else { return nil }
                let suffix = String(relative.dropFirst(name.count + 1))
                return FileManager.default.children(of: root).first { $0.lastPathComponent.lowercased() == suffix }
            }
            for app in roots where isRealDirectory(app) {
                let entries = FileManager.default.children(of: app)
                let isEditor = PathSafety.codeEditorFolderNames.contains(app.lastPathComponent.lowercased())
                let markers = Set(entries.map { $0.lastPathComponent.lowercased() })
                let isChromium = !markers.isDisjoint(with: PathSafety.chromiumMarkers)
                guard isEditor || isChromium else { continue }
                let cacheNames = PathSafety.appWebCacheFolderNames.union(isEditor ? PathSafety.codeEditorCacheFolderNames : [])
                var folders = entries.filter { cacheNames.contains($0.lastPathComponent.lowercased()) && isRealDirectory($0) }
                // A profile must have Chromium's Preferences marker. Service Worker,
                // IndexedDB, local storage and offline databases are deliberately excluded.
                for profile in entries where PathSafety.isChromiumProfile(profile.lastPathComponent.lowercased()) && isRealDirectory(profile) {
                    guard FileManager.default.fileExists(atPath: profile.appendingPathComponent("Preferences").path) else { continue }
                    folders += FileManager.default.children(of: profile).filter {
                        PathSafety.appWebCacheFolderNames.contains($0.lastPathComponent.lowercased()) && isRealDirectory($0)
                    }
                }
                if !folders.isEmpty { apps.append(WebApp(owner: app.lastPathComponent, folders: folders)) }
            }
        }
        return apps
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink == false
    }
}
