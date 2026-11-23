import Foundation

/// Known disposable children of IDE system directories; recovery and plugin data stay.
nonisolated enum IDECacheScanner {
    static let inUseCheck = InUseCheck.runningApp(
        bundleIDPrefixes: ["com.google.android.studio"],
        executableNames: ["studio", "studio64"],
        name: "Android Studio"
    )

    static func cacheFolders(home: URL, includesJetBrains: Bool = true, includesAndroidStudio: Bool = true) -> [URL] {
        let vendor = home.appendingPathComponent("Library/Caches/Google")
        var folders: [URL] = []
        let androidVersions = includesAndroidStudio && isRealDirectory(vendor) ? FileManager.default.children(of: vendor) : []
        for version in androidVersions.sorted(by: { $0.path < $1.path }) {
            guard version.lastPathComponent.lowercased().range(
                of: "^androidstudio(?:preview)?[0-9]+(?:\\.[0-9]+)*$", options: .regularExpression
            ) != nil, isRealDirectory(version) else { continue }
            let caches = FileManager.default.children(of: version).filter {
                PathSafety.androidStudioCacheFolderNames.contains($0.lastPathComponent.lowercased()) && isRealDirectory($0)
            }.sorted { $0.path < $1.path }
            folders += caches
        }
        let jetbrains = home.appendingPathComponent("Library/Caches/JetBrains")
        if includesJetBrains, isRealDirectory(jetbrains) {
            for version in FileManager.default.children(of: jetbrains).sorted(by: { $0.path < $1.path }) {
                guard IDECachePolicy.product(for: version.lastPathComponent) != nil, isRealDirectory(version) else { continue }
                folders += FileManager.default.children(of: version).filter {
                    PathSafety.androidStudioCacheFolderNames.contains($0.lastPathComponent.lowercased()) && isRealDirectory($0)
                }.sorted { $0.path < $1.path }
            }
        }
        return folders
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink == false
    }
}
