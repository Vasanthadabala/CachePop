import Foundation

/// Registered development copies account for many repeated app results in macOS search.
/// Offer individual bundles, never their enclosing project, build folder or release archive.
nonisolated enum AppBuildScanner {
    static func scan(_ context: ScanContext) -> CleanupGroup {
        let catalog = context.env.apps
        let installedIDs = catalog.installedBundleIDs()
        let derivedData = context.env.path("Library/Developer/Xcode/DerivedData").resolvingSymlinksInPath().path
        var candidates: [URL] = []
        for bundleID in installedIDs.sorted() where !bundleID.hasPrefix("com.apple.") {
            guard !Task.isCancelled else { break }
            let copies = catalog.applicationURLs(bundleID: bundleID)
            candidates += copies
            // Test runners don't have an installed counterpart. Find them beside registered
            // build products, without recursively walking projects or the whole disk.
            for copy in copies where isBuildProduct(copy) {
                candidates += FileManager.default.children(of: copy.deletingLastPathComponent()).filter {
                    $0.pathExtension == "app" && bundleIdentifier(at: $0)?.hasSuffix(".xctrunner") == true
                }
            }
        }

        var seen: Set<String> = []
        var items: [CleanupItem] = []
        for candidate in candidates {
            guard !Task.isCancelled else { break }
            let url = candidate.resolvingSymlinksInPath()
            guard isDisposableBuild(candidate), seen.insert(url.path).inserted,
                  // The existing Derived data item already accounts for this storage.
                  !url.path.hasPrefix(derivedData + "/"),
                  let info = MetadataReader.propertyList(from: url.appendingPathComponent("Contents/Info.plist")),
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  installedIDs.contains(bundleID.lowercased()) || bundleID.lowercased().hasSuffix(".xctrunner") else { continue }
            let size = DirectorySizer.size(of: url)
            guard size.bytes > 0, !size.hasUnreadableParts else { continue }
            let runner = bundleID.hasSuffix(".xctrunner")
            let name = ApplicationDetails.cleanName(info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "")
                ?? url.deletingPathExtension().lastPathComponent
            let version = info["CFBundleShortVersionString"] as? String
            let check = InUseCheck.appBuild(bundleID: bundleID.lowercased(), path: url.path)
            items.append(CleanupItem(
                id: "xcode.appBuild.\(url.path)",
                group: .xcode,
                title: "\(name) — \(runner ? "test runner" : "extra app build")",
                explanation: runner
                    ? "An app Xcode generated to run UI tests. Xcode rebuilds it when tests run again."
                    : "A development or exported build of an installed app. Extra copies can appear separately in macOS search. Keep any build you still need.",
                detail: [version.map { "Version \($0)" }, url.path].compactMap { $0 }.joined(separator: " · "),
                sizeBytes: size.bytes,
                sizeIsUpperBound: size.hasSharedFiles,
                actions: [CleanupAction(
                    id: "trash",
                    title: "Move to Trash",
                    operation: .moveToTrash([url]),
                    regeneration: .movedToTrash,
                    explanation: "Only this app bundle is moved to the Trash. You can put it back; space is freed when the Trash is emptied."
                )],
                isRecommended: false,
                note: "Select this copy only if you no longer need it.",
                blockedReason: inUseReason(for: check, processes: context.processes),
                inUseCheck: check
            ))
        }
        return CleanupGroup(kind: .xcode, items: items.sorted { $0.sizeBytes > $1.sizeBytes })
    }

    /// A narrow Trash-only exception for custom build locations, including other volumes.
    /// Repeated immediately before moving a bundle, with the identifier recorded by the scan.
    static func isDisposableBuild(_ url: URL, expectedBundleID: String? = nil) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains(".."), url.pathExtension.lowercased() == "app",
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { return false }
        let canonical = url.resolvingSymlinksInPath()
        let ancestors = canonical.deletingLastPathComponent().pathComponents.map { $0.lowercased() }
        guard !ancestors.contains(where: {
            $0 == "applications" || $0 == ".git" || $0 == ".trash" || $0 == ".trashes"
                || $0.hasSuffix(".app") || $0.hasSuffix(".xcarchive") || $0.hasSuffix(".photoslibrary")
        }), !canonical.path.hasPrefix("/System/"),
              canonical.path != Bundle.main.bundleURL.resolvingSymlinksInPath().path,
              let info = MetadataReader.propertyList(from: canonical.appendingPathComponent("Contents/Info.plist")),
              info["CFBundlePackageType"] as? String == "APPL",
              let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              !id.lowercased().hasPrefix("com.apple."),
              expectedBundleID == nil || id.lowercased() == expectedBundleID?.lowercased() else { return false }
        if isBuildProduct(canonical) { return true }

        // Exported/notarized copies qualify only inside an Xcode project's build directory.
        // A folder merely named "export" or "build" elsewhere doesn't qualify.
        var parent = canonical.deletingLastPathComponent()
        while parent.path != "/" {
            if parent.lastPathComponent.lowercased() == "build" {
                let project = parent.deletingLastPathComponent()
                return FileManager.default.children(of: project).contains {
                    $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace"
                }
            }
            parent.deleteLastPathComponent()
        }
        return false
    }

    private static func isBuildProduct(_ url: URL) -> Bool {
        let configuration = url.deletingLastPathComponent()
        let products = configuration.deletingLastPathComponent()
        return products.lastPathComponent == "Products"
            && products.deletingLastPathComponent().lastPathComponent == "Build"
    }

    private static func bundleIdentifier(at url: URL) -> String? {
        MetadataReader.propertyList(from: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
    }
}
