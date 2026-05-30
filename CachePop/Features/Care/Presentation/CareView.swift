//
//  CareView.swift
//  CachePop
//
//  Created by Vasanth on 13/05/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CareView: View {
    @State private var selectedItem: CareSidebarItem = .smartCare
    @State private var scanPhase: ScanPhase = .idle
    @State private var scanProgress = 0.0
    @State private var cleaningProgress = 0.0
    @State private var scanSnapshot = CareScanSnapshot.empty
    @State private var activeDetail: CareLogDetail?
    @State private var scanTask: Task<Void, Never>?
    @State private var pulse = false

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let scale = min(max(proxy.size.width / 1180, 0.78), 1.08)

                ZStack(alignment: .topLeading) {
                    CareSectionBackground(selectedItem: selectedItem)

                    if let activeDetail {
                        HStack(spacing: 0) {
                            CareSidebar(selectedItem: $selectedItem)
                                .frame(width: 250)
                                .clipped()

                            CareLogDetailContent(
                                detail: activeDetail,
                                onBack: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        self.activeDetail = nil
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        HStack(spacing: 0) {
                            CareSidebar(selectedItem: $selectedItem)
                                .frame(width: 250)

                            Group {
                                if selectedItem == .smartCare, scanPhase == .complete {
                                    CareResultsContent(
                                        snapshot: scanSnapshot,
                                        onViewLog: { showLog(.all, cleaned: true) },
                                        onStartOver: resetScan
                                    )
                                } else if selectedItem == .smartCare, scanPhase == .readyToRun {
                                    CareReadyToRunContent(
                                        snapshot: scanSnapshot,
                                        pulse: pulse,
                                        onStartOver: resetScan,
                                        onReview: { showLog($0, cleaned: false) },
                                        onRun: runReadyTasks
                                    )
                                } else if selectedItem == .smartCare, scanPhase == .cleaning {
                                    CareCleaningContent(
                                        progress: cleaningProgress,
                                        snapshot: scanSnapshot,
                                        pulse: pulse
                                    )
                                } else if selectedItem == .smartCare, scanPhase == .scanning {
                                    CareScanningContent(
                                        scanProgress: scanProgress,
                                        snapshot: scanSnapshot,
                                        pulse: pulse,
                                        onStop: resetScan
                                    )
                                } else if selectedItem == .cleanup {
                                    JunkCleanerView {
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                            selectedItem = .smartCare
                                        }
                                    }
                                } else if selectedItem == .performance {
                                    BoostView {
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                            selectedItem = .smartCare
                                        }
                                    }
                                } else if selectedItem == .applications {
                                    AppManagerView {
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                            selectedItem = .smartCare
                                        }
                                    }
                                } else if selectedItem == .myClutter {
                                    ClutterView {
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                            selectedItem = .smartCare
                                        }
                                    }
                                } else if selectedItem == .assistant {
                                    AssistantView()
                                } else {
                                    CareHomeContent(
                                        scanPhase: scanPhase,
                                        scanProgress: scanProgress,
                                        pulse: pulse,
                                        scale: scale,
                                        onScan: startScan
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func startScan() {
        guard scanPhase != .scanning else { return }

        scanTask?.cancel()
        scanProgress = 0
        cleaningProgress = 0
        scanSnapshot = .empty

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            scanPhase = .scanning
        }

        scanTask = Task {
            var snapshot = CareScanSnapshot.empty

            updateScan(progress: 0.04, snapshot: snapshot.withDetail("Preparing local scan..."))
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }

            updateScan(progress: 0.10, snapshot: snapshot.withDetail("Scanning browser junk caches."))
            let browserCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanBrowserCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += browserCacheResult.bytes
            snapshot.cacheItems += browserCacheResult.items
            snapshot.cacheDetails.append(contentsOf: browserCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: browserCacheResult.permissions)
            updateScan(progress: 0.22, snapshot: snapshot.withDetail("Scanning app, system, log, temp, and developer junk."))
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }

            let appCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanApplicationCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += appCacheResult.bytes
            snapshot.cacheItems += appCacheResult.items
            snapshot.cacheDetails.append(contentsOf: appCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: appCacheResult.permissions)
            let trashResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanTrashItems()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += trashResult.bytes
            snapshot.cacheItems += trashResult.items
            snapshot.cacheDetails.append(contentsOf: trashResult.details)
            snapshot.permissionMessages.append(contentsOf: trashResult.permissions)
            updateScan(progress: 0.38, snapshot: snapshot.withDetail("Finished browser and app junk scan."))
            try? await Task.sleep(for: .milliseconds(420))
            if Task.isCancelled { return }

            updateScan(progress: 0.46, snapshot: snapshot.withDetail("Scanning startup items and background helpers."))
            let startupResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanStartupItems()
            }.value
            if Task.isCancelled { return }
            snapshot.startupItems = startupResult.count
            snapshot.startupDetails = startupResult.details
            snapshot.permissionMessages.append(contentsOf: startupResult.permissions)
            updateScan(progress: 0.57, snapshot: snapshot.withDetail("Finished startup scan."))
            try? await Task.sleep(for: .milliseconds(160))
            if Task.isCancelled { return }

            updateScan(progress: 0.64, snapshot: snapshot.withDetail("Checking installed applications for updates."))
            let appResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanApplications()
            }.value
            if Task.isCancelled { return }
            snapshot.appsChecked = appResult.count
            snapshot.appDetails = appResult.details
            snapshot.permissionMessages.append(contentsOf: appResult.permissions)
            updateScan(progress: 0.75, snapshot: snapshot.withDetail("Finished app update scan."))
            try? await Task.sleep(for: .milliseconds(160))
            if Task.isCancelled { return }

            updateScan(progress: 0.82, snapshot: snapshot.withDetail("Scanning large files and duplicate candidates."))
            let clutterResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanClutter()
            }.value
            if Task.isCancelled { return }
            snapshot.largeFiles = clutterResult.largeFiles
            snapshot.duplicateFiles = clutterResult.duplicateFiles
            snapshot.clutterDetails = clutterResult.details
            snapshot.permissionMessages.append(contentsOf: clutterResult.permissions)
            updateScan(progress: 1, snapshot: snapshot.withDetail("Finished comparing large files and duplicates."))

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    scanPhase = snapshot.hasFindings ? .readyToRun : .complete
                }
            }
        }
    }

    private func runReadyTasks() {
        scanTask?.cancel()
        cleaningProgress = 0

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            selectedItem = .smartCare
            scanPhase = .cleaning
        }

        scanTask = Task {
            let steps: [(Double, String)] = [
                (0.18, "Cleaning browser and application cache selections..."),
                (0.42, "Applying startup item review decisions..."),
                (0.64, "Finalizing application update checks..."),
                (0.86, "Processing large and duplicate file selections..."),
                (1.0, "Writing after-cleaning result logs...")
            ]

            for step in steps {
                try? await Task.sleep(for: .milliseconds(520))
                if Task.isCancelled { return }

                await MainActor.run {
                    withAnimation(.linear(duration: 0.2)) {
                        cleaningProgress = step.0
                        scanSnapshot.currentDetail = step.1
                    }
                }
            }

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    scanPhase = .complete
                }
            }
        }
    }

    private func resetScan() {
        scanTask?.cancel()
        scanTask = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            scanProgress = 0
            cleaningProgress = 0
            scanSnapshot = .empty
            activeDetail = nil
            scanPhase = .idle
            selectedItem = .smartCare
        }
    }

    private func showLog(_ category: CareLogCategory, cleaned: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            activeDetail = CareLogDetail(
                category: category,
                snapshot: scanSnapshot,
                cleaned: cleaned
            )
        }
    }

    @MainActor
    private func updateScan(progress: Double, snapshot: CareScanSnapshot) {
        withAnimation(.linear(duration: 0.16)) {
            scanProgress = progress
            scanSnapshot = snapshot
        }
    }
}

private extension CareScanSnapshot {
    func withDetail(_ detail: String) -> CareScanSnapshot {
        var snapshot = self
        snapshot.currentDetail = detail
        return snapshot
    }
}

enum CareSystemScanner {
    nonisolated static func scanCaches() -> (bytes: Int64, items: Int, details: [CareScanDetailItem], permissions: [String]) {
        let browser = scanBrowserCaches()
        let app = scanApplicationCaches()

        return (
            bytes: browser.bytes + app.bytes,
            items: browser.items + app.items,
            details: browser.details + app.details,
            permissions: uniquePermissions(browser.permissions + app.permissions)
        )
    }

    nonisolated static func scanBrowserCaches() -> (bytes: Int64, items: Int, details: [CareScanDetailItem], permissions: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cacheRoots = [
            CacheRoot(url: home.appendingPathComponent("Library/Caches/Google/Chrome"), kind: "Browser Cache", label: "Chrome Cache", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/com.google.Chrome"), kind: "Browser Cache", label: "Chrome Cache"),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/Microsoft Edge"), kind: "Browser Cache", label: "Edge Cache", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/Firefox"), kind: "Browser Cache", label: "Firefox Cache", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser"), kind: "Browser Cache", label: "Brave Cache", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/com.operasoftware.Opera"), kind: "Browser Cache", label: "Opera Cache", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/com.vivaldi.Vivaldi"), kind: "Browser Cache", label: "Vivaldi Cache", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/company.thebrowser.Browser"), kind: "Browser Cache", label: "Arc Cache"),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/com.apple.Safari"), kind: "Browser Cache", label: "Safari Cache"),
            CacheRoot(url: home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Caches"), kind: "Browser Cache", label: "Safari Container")
        ] + discoveredBrowserCacheRoots(home: home)

        return scanCacheRoots(cacheRoots)
    }

    nonisolated static func scanApplicationCaches() -> (bytes: Int64, items: Int, details: [CareScanDetailItem], permissions: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cacheRoots = [
            CacheRoot(url: home.appendingPathComponent("Library/Caches"), kind: "App Cache", label: "Application Caches", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Containers"), kind: "App Cache", label: "Container Caches", limit: 6_000),
            CacheRoot(url: home.appendingPathComponent("Library/Group Containers"), kind: "App Cache", label: "Group Container Caches", limit: 4_000),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/Caches"), kind: "App Cache", label: "Application Support Caches"),
            CacheRoot(url: home.appendingPathComponent("Library/HTTPStorages"), kind: "App Cache", label: "HTTP Storage Caches"),
            CacheRoot(url: home.appendingPathComponent("Library/WebKit"), kind: "App Cache", label: "WebKit Caches"),
            CacheRoot(url: home.appendingPathComponent("Library/Saved Application State"), kind: "App Cache", label: "Saved Application State"),
            CacheRoot(url: URL(fileURLWithPath: "/Library/Caches"), kind: "System Cache", label: "System Caches"),
            CacheRoot(url: home.appendingPathComponent("Library/Logs"), kind: "Log File", label: "User Logs", limit: 5_000),
            CacheRoot(url: URL(fileURLWithPath: "/Library/Logs"), kind: "Log File", label: "System Logs", limit: 4_000),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/CrashReporter"), kind: "Log File", label: "Crash Reports"),
            CacheRoot(url: URL(fileURLWithPath: "/private/tmp"), kind: "Temporary File", label: "Temporary Files", limit: 6_000),
            CacheRoot(url: URL(fileURLWithPath: "/private/var/tmp"), kind: "Temporary File", label: "System Temporary Files", limit: 4_000),
            CacheRoot(url: URL(fileURLWithPath: "/private/var/folders"), kind: "Temporary File", label: "Per-user Temporary Caches", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"), kind: "Developer Cache", label: "Xcode Derived Data", limit: 8_000),
            CacheRoot(url: home.appendingPathComponent("Library/Developer/Xcode/Archives"), kind: "Developer Cache", label: "Xcode Archives", limit: 4_000),
            CacheRoot(url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"), kind: "Developer Cache", label: "iOS Device Support", limit: 4_000),
            CacheRoot(url: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"), kind: "Developer Cache", label: "Simulator Caches"),
            CacheRoot(url: home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"), kind: "Developer Cache", label: "Simulator Device Caches", limit: 4_000),
            CacheRoot(url: home.appendingPathComponent(".npm"), kind: "Package Cache", label: "npm Cache", limit: 5_000),
            CacheRoot(url: home.appendingPathComponent(".cache/yarn"), kind: "Package Cache", label: "Yarn Cache", limit: 5_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/Yarn"), kind: "Package Cache", label: "Yarn Cache", limit: 5_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/pip"), kind: "Package Cache", label: "pip Cache", limit: 5_000),
            CacheRoot(url: home.appendingPathComponent("Library/Caches/Homebrew"), kind: "Package Cache", label: "Homebrew Cache", limit: 5_000),
            CacheRoot(url: home.appendingPathComponent(".gradle/caches"), kind: "Package Cache", label: "Gradle Cache", limit: 5_000),
            CacheRoot(url: home.appendingPathComponent(".m2/repository"), kind: "Package Cache", label: "Maven Cache", limit: 5_000)
        ]

        return scanCacheRoots(cacheRoots)
    }

    nonisolated static func scanTrashItems() -> (bytes: Int64, items: Int, details: [CareScanDetailItem], permissions: [String]) {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard FileManager.default.fileExists(atPath: trashURL.path) else {
            return (bytes: 0, items: 0, details: [], permissions: [])
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return (
                bytes: 0,
                items: 0,
                details: [],
                permissions: ["CachePop could not read \(abbreviatedPath(trashURL.path)). Grant Full Disk Access to include Trash Bins."]
            )
        }

        var totalBytes = Int64(0)
        var details: [CareScanDetailItem] = []

        for itemURL in contents.prefix(500) {
            let values = try? itemURL.resourceValues(forKeys: Set(keys))
            let size: Int64

            if values?.isDirectory == true {
                size = directorySize(at: CacheRoot(url: itemURL, kind: "Trash Item", label: "Trash Bins", limit: 4_000), limit: 4_000).bytes
            } else {
                size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }

            totalBytes += size
            details.append(detailItem(
                title: itemURL.lastPathComponent,
                subtitle: "Trash Bins",
                path: itemURL.path,
                size: size,
                kind: "Trash Item",
                modified: values?.contentModificationDate
            ))
        }

        return (
            bytes: totalBytes,
            items: details.count,
            details: details.sorted { $0.sizeBytes > $1.sizeBytes },
            permissions: []
        )
    }

    nonisolated private static func scanCacheRoots(_ roots: [CacheRoot]) -> (bytes: Int64, items: Int, details: [CareScanDetailItem], permissions: [String]) {
        var result = roots.reduce(into: (bytes: Int64(0), items: 0, details: [CareScanDetailItem](), permissions: [String]())) { result, root in
            let partial = directorySize(at: root, limit: root.limit)
            result.bytes += partial.bytes
            result.items += partial.items
            result.details.append(contentsOf: partial.details)
            result.permissions.append(contentsOf: partial.permissions)
        }
        result.permissions = uniquePermissions(result.permissions)
        return result
    }

    nonisolated private static func discoveredBrowserCacheRoots(home: URL) -> [CacheRoot] {
        let browserSupportRoots = [
            (url: home.appendingPathComponent("Library/Application Support/Google/Chrome"), label: "Chrome"),
            (url: home.appendingPathComponent("Library/Application Support/Microsoft Edge"), label: "Edge"),
            (url: home.appendingPathComponent("Library/Application Support/Firefox"), label: "Firefox"),
            (url: home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser"), label: "Brave"),
            (url: home.appendingPathComponent("Library/Application Support/com.operasoftware.Opera"), label: "Opera"),
            (url: home.appendingPathComponent("Library/Application Support/Vivaldi"), label: "Vivaldi"),
            (url: home.appendingPathComponent("Library/Application Support/Arc"), label: "Arc")
        ]

        return browserSupportRoots.flatMap { root in
            discoverCacheFolders(in: root.url, labelPrefix: root.label)
        }
    }

    nonisolated private static func discoverCacheFolders(in root: URL, labelPrefix: String) -> [CacheRoot] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
              ) else {
            return []
        }

        var roots: [CacheRoot] = []
        var scannedDirectories = 0

        for case let directoryURL as URL in enumerator {
            guard scannedDirectories < 2_500, roots.count < 80 else { break }
            scannedDirectories += 1

            guard let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                continue
            }

            guard isBrowserCacheDirectory(directoryURL) else {
                continue
            }

            let profileName = directoryURL.deletingLastPathComponent().lastPathComponent
            let label: String
            if profileName.isEmpty || profileName == root.lastPathComponent {
                label = "\(labelPrefix) \(directoryURL.lastPathComponent)"
            } else {
                label = "\(labelPrefix) \(profileName) \(directoryURL.lastPathComponent)"
            }

            roots.append(CacheRoot(url: directoryURL, kind: "Browser Cache", label: label, limit: 3_500))
            enumerator.skipDescendants()
        }

        return roots
    }

    nonisolated private static func isBrowserCacheDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()
        let cacheDirectoryNames: Set<String> = [
            "cache",
            "cache_data",
            "cache2",
            "cachestorage",
            "code cache",
            "dawncache",
            "gpucache",
            "grshadercache",
            "shadercache",
            "scriptcache",
            "startupcache",
            "thumbnails"
        ]

        return cacheDirectoryNames.contains(name)
            || path.hasSuffix("/service worker/cachestorage")
            || path.hasSuffix("/service worker/scriptcache")
    }

    nonisolated static func scanStartupItems() -> (count: Int, details: [CareScanDetailItem], permissions: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let startupRoots = [
            CacheRoot(url: home.appendingPathComponent("Library/LaunchAgents"), kind: "Login Item", label: "Login Items"),
            CacheRoot(url: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: "Background Item", label: "Background Items"),
            CacheRoot(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: "Background Item", label: "Background Items")
        ]

        var result = startupRoots.reduce(into: (count: 0, details: [CareScanDetailItem](), permissions: [String]())) { result, root in
            let partial = plistDetails(at: root)
            result.count += partial.details.count
            result.details.append(contentsOf: partial.details)
            result.permissions.append(contentsOf: partial.permissions)
        }

        let running = runningThirdPartyBackgroundItems()
        result.count += running.count
        result.details.append(contentsOf: running)
        result.details = uniqueStartupItems(result.details)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return result
    }

    nonisolated static func scanApplications() -> (count: Int, details: [CareScanDetailItem], permissions: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appRoots = [
            CacheRoot(url: URL(fileURLWithPath: "/Applications"), kind: "Application", label: "Mac Applications"),
            CacheRoot(url: home.appendingPathComponent("Applications"), kind: "Application", label: "User Applications")
        ]

        return appRoots.reduce(into: (count: 0, details: [CareScanDetailItem](), permissions: [String]())) { result, root in
            let partial = appBundleDetails(at: root)
            result.count += partial.details.count
            result.details.append(contentsOf: partial.details)
            result.permissions.append(contentsOf: partial.permissions)
        }
    }

    nonisolated static func scanClutter() -> (largeFiles: Int, duplicateFiles: Int, details: [CareScanDetailItem], permissions: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            CacheRoot(url: home.appendingPathComponent("Downloads"), kind: "Large File", label: "Downloads")
        ]

        return scanClutter(in: roots)
    }

    nonisolated static func scanClutter(in folder: URL) -> (largeFiles: Int, duplicateFiles: Int, details: [CareScanDetailItem], permissions: [String]) {
        let standardizedFolder = folder.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if standardizedFolder.path == home.path {
            return scanClutter(in: homeClutterRoots(home: home))
        }

        let label = folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
        return scanClutter(in: [
            CacheRoot(url: folder, kind: "Large File", label: label)
        ])
    }

    nonisolated private static func homeClutterRoots(home: URL) -> [CacheRoot] {
        [
            ("Desktop", "Desktop"),
            ("Documents", "Documents"),
            ("Downloads", "Downloads"),
            ("Pictures", "Pictures"),
            ("Movies", "Movies"),
            ("Music", "Music"),
            ("Public", "Public")
        ]
        .map { folderName, label in
            CacheRoot(url: home.appendingPathComponent(folderName), kind: "Large File", label: label)
        }
        .filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    nonisolated private static func scanClutter(in roots: [CacheRoot]) -> (largeFiles: Int, duplicateFiles: Int, details: [CareScanDetailItem], permissions: [String]) {
        var largeFiles = 0
        var details: [CareScanDetailItem] = []
        var filesBySize: [Int64: [FileSample]] = [:]
        var permissions: [String] = []

        for root in roots {
            let result = fileSamples(at: root, limit: 5_500)
            permissions.append(contentsOf: result.permissions)

            let files = result.files
            for file in files {
                if file.size > 100_000_000 {
                    largeFiles += 1
                    details.append(detailItem(
                        title: file.url.lastPathComponent,
                        subtitle: root.label,
                        path: file.url.path,
                        size: file.size,
                        kind: "Large File",
                        modified: file.modified
                    ))
                }

                if file.size > 0, isClutterDuplicateCandidate(file.url) {
                    filesBySize[file.size, default: []].append(file)
                }
            }
        }

        let duplicateGroups = filesBySize.values
            .filter { $0.count > 1 }
            .flatMap { files -> [[FileSample]] in
                Dictionary(grouping: files) { file in
                    fileContentSignature(for: file.url, size: file.size) ?? "unreadable-\(file.url.path)"
                }
                .values
                .filter { $0.count > 1 }
            }
        let duplicateFiles = duplicateGroups.reduce(0) { total, group in
            total + max(group.count - 1, 0)
        }

        for group in duplicateGroups {
            let signature = "duplicate-group-\(group.first?.size ?? 0)-\(group.map(\.url.path).sorted().joined(separator: "|").hashValue)"
            for file in group {
                details.append(duplicateDetailItem(
                    title: file.url.lastPathComponent,
                    subtitle: "Duplicate candidate",
                    path: file.url.path,
                    size: file.size,
                    groupID: signature,
                    modified: file.modified
                ))
            }
        }

        return (
            largeFiles: largeFiles,
            duplicateFiles: duplicateFiles,
            details: details.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(120).map { $0 },
            permissions: permissions
        )
    }

    nonisolated private static func fileContentSignature(for url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else { return false }

            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }

            return true
        }) {}

        return "\(size)-\(hash)"
    }

    nonisolated private static func isClutterDuplicateCandidate(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: fileExtension),
           type.conforms(to: .image) {
            return true
        }

        let allowedExtensions: Set<String> = [
            "pdf",
            "doc", "docx", "rtf", "txt", "pages",
            "xls", "xlsx", "csv", "numbers",
            "ppt", "pptx", "key",
            "zip", "rar", "7z", "tar", "gz",
            "mp3", "m4a", "wav", "aac",
            "mp4", "mov", "m4v",
            "dmg", "pkg", "mpkg", "appinstaller", "installer", "msi", "exe"
        ]

        return allowedExtensions.contains(fileExtension)
    }

    nonisolated private static func directorySize(at root: CacheRoot, limit: Int) -> (bytes: Int64, items: Int, details: [CareScanDetailItem], permissions: [String]) {
        guard FileManager.default.fileExists(atPath: root.url.path) else {
            return (bytes: 0, items: 0, details: [], permissions: [])
        }

        var permissions: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root.url,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { blockedURL, _ in
                permissions.append("CachePop could not read \(abbreviatedPath(blockedURL.path)). Grant Full Disk Access to scan every cache folder.")
                return true
            }
        ) else {
            return (
                bytes: 0,
                items: 0,
                details: [],
                permissions: ["CachePop could not open \(abbreviatedPath(root.url.path)). Grant Full Disk Access to include this location."]
            )
        }

        var result = (bytes: Int64(0), items: 0, details: [CareScanDetailItem]())
        for case let fileURL as URL in enumerator {
            guard result.items < limit else { break }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            result.items += 1
            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            result.bytes += size

            if result.details.count < 100 {
                result.details.append(detailItem(
                    title: fileURL.lastPathComponent,
                    subtitle: root.label,
                    path: fileURL.path,
                    size: size,
                    kind: root.kind,
                    modified: values.contentModificationDate
                ))
            }
        }

        let details = result.details.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(40).map { $0 }
        return (bytes: result.bytes, items: result.items, details: details, permissions: uniquePermissions(permissions))
    }

    nonisolated private static func plistDetails(at root: CacheRoot) -> (details: [CareScanDetailItem], permissions: [String]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root.url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FileManager.default.fileExists(atPath: root.url.path)
                ? ([], ["CachePop could not read \(abbreviatedPath(root.url.path)). Grant Full Disk Access to include this startup location."])
                : ([], [])
        }

        let details = contents
            .filter { $0.pathExtension == "plist" }
            .compactMap { url -> CareScanDetailItem? in
                let rawTitle = url.deletingPathExtension().lastPathComponent
                guard !isAppleStartupItem(title: rawTitle, path: url.path) else {
                    return nil
                }

                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return detailItem(
                    title: displayStartupTitle(rawTitle),
                    subtitle: root.label,
                    path: url.path,
                    size: Int64(values?.fileSize ?? 0),
                    kind: root.kind,
                    modified: values?.contentModificationDate
                )
            }

        return (details, [])
    }

    nonisolated private static func runningThirdPartyBackgroundItems() -> [CareScanDetailItem] {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications
            .filter { app in
                guard app.activationPolicy != .regular else { return false }
                return isThirdPartyApplication(bundleIdentifier: app.bundleIdentifier, bundleURL: app.bundleURL)
            }
            .map { app in
                let title = app.localizedName ?? app.bundleIdentifier ?? "Background App"
                return detailItem(
                    title: title,
                    subtitle: "Background Items",
                    path: app.bundleURL?.path ?? app.bundleIdentifier ?? title,
                    size: 0,
                    kind: "Background Item",
                    modified: nil
                )
            }
    }

    nonisolated private static func isAppleStartupItem(title: String, path: String) -> Bool {
        let lowerTitle = title.lowercased()
        let lowerPath = path.lowercased()
        return lowerTitle.hasPrefix("com.apple.")
            || lowerTitle.hasPrefix("apple.")
            || lowerPath.hasPrefix("/system/")
            || lowerPath.contains("/system/library/")
    }

    nonisolated private static func isThirdPartyApplication(bundleIdentifier: String?, bundleURL: URL?) -> Bool {
        if let bundleIdentifier = bundleIdentifier?.lowercased(),
           bundleIdentifier.hasPrefix("com.apple.") || bundleIdentifier.hasPrefix("apple.") {
            return false
        }

        guard let path = bundleURL?.path else {
            return bundleIdentifier != nil
        }

        return path.hasPrefix("/Applications/")
            || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
    }

    nonisolated private static func displayStartupTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: ".plist", with: "")
    }

    nonisolated private static func uniqueStartupItems(_ items: [CareScanDetailItem]) -> [CareScanDetailItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.kind)-\(item.title.lowercased())-\(item.path.lowercased())"
            return seen.insert(key).inserted
        }
    }

    nonisolated private static func appBundleDetails(at root: CacheRoot) -> (details: [CareScanDetailItem], permissions: [String]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FileManager.default.fileExists(atPath: root.url.path)
                ? ([], ["CachePop could not read \(abbreviatedPath(root.url.path)). Grant access to include all applications."])
                : ([], [])
        }

        let details = contents
            .filter { $0.pathExtension == "app" }
            .compactMap { url -> CareScanDetailItem? in
                let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey])
                return detailItem(
                    title: url.deletingPathExtension().lastPathComponent,
                    subtitle: root.label,
                    path: url.path,
                    size: Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0),
                    kind: root.kind,
                    modified: values?.contentModificationDate
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return (details, [])
    }

    nonisolated private static func fileSamples(at root: CacheRoot, limit: Int) -> (files: [FileSample], permissions: [String]) {
        guard FileManager.default.fileExists(atPath: root.url.path) else {
            return ([], [])
        }

        if shouldSkipClutterDirectory(root.url) {
            return ([], [])
        }

        var permissions: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root.url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { blockedURL, _ in
                permissions.append("CachePop could not read \(abbreviatedPath(blockedURL.path)). Grant Full Disk Access to scan every file.")
                return true
            }
        ) else {
            return ([], ["CachePop could not open \(abbreviatedPath(root.url.path)). Grant Full Disk Access to scan this location."])
        }

        var files: [FileSample] = []
        for case let fileURL as URL in enumerator {
            guard files.count < limit else { break }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            if values.isDirectory == true {
                if shouldSkipClutterDirectory(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            files.append(FileSample(
                url: fileURL,
                size: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
                modified: values.contentModificationDate
            ))
        }

        return (files, uniquePermissions(permissions))
    }

    nonisolated private static func shouldSkipClutterDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let path = url.standardizedFileURL.path.lowercased()

        let skippedDirectoryNames: Set<String> = [
            ".build", ".dart_tool", ".gradle", ".idea", ".next", ".nuxt", ".svelte-kit",
            ".swiftpm", ".venv", "build", "coverage", "deriveddata", "dist", "node_modules",
            "pods", "target", "vendor", "venv"
        ]

        if skippedDirectoryNames.contains(name) {
            return true
        }

        let projectContainerNames: Set<String> = [
            "androidstudioprojects", "developer", "xcode"
        ]

        if projectContainerNames.contains(name) {
            return true
        }

        if path.contains("/library/developer/xcode/deriveddata/")
            || path.contains("/.gradle/")
            || path.contains("/node_modules/")
            || path.contains("/pods/") {
            return true
        }

        return containsProjectMarker(in: url)
    }

    nonisolated private static func containsProjectMarker(in url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let markerFiles: Set<String> = [
            "Package.swift", "package.json", "pnpm-lock.yaml", "yarn.lock",
            "Podfile", "Cartfile", "build.gradle", "settings.gradle",
            "gradlew", "pubspec.yaml", "Cargo.toml", "go.mod"
        ]

        return contents.contains { item in
            markerFiles.contains(item.lastPathComponent)
                || item.pathExtension == "xcodeproj"
                || item.pathExtension == "xcworkspace"
                || item.pathExtension == "playground"
        }
    }

    nonisolated private static func detailItem(
        title: String,
        subtitle: String,
        path: String,
        size: Int64,
        kind: String,
        modified: Date?
    ) -> CareScanDetailItem {
        CareScanDetailItem(
            id: "\(kind)-\(path)-\(size)",
            title: title.isEmpty ? kind : title,
            subtitle: subtitle,
            detail: "\(kind) found in \(subtitle)",
            path: path,
            sizeBytes: size,
            kind: kind,
            modified: modified
        )
    }

    nonisolated private static func duplicateDetailItem(
        title: String,
        subtitle: String,
        path: String,
        size: Int64,
        groupID: String,
        modified: Date?
    ) -> CareScanDetailItem {
        CareScanDetailItem(
            id: "Duplicate Candidate-\(path)-\(size)",
            title: title.isEmpty ? "Duplicate Candidate" : title,
            subtitle: subtitle,
            detail: groupID,
            path: path,
            sizeBytes: size,
            kind: "Duplicate Candidate",
            modified: modified
        )
    }

    nonisolated private static func abbreviatedPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(homePath) else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    nonisolated private static func uniquePermissions(_ messages: [String]) -> [String] {
        var seen = Set<String>()
        return messages.filter { seen.insert($0).inserted }
    }

    private struct CacheRoot {
        let url: URL
        let kind: String
        let label: String
        var limit = 2_800
    }

    private struct FileSample {
        let url: URL
        let size: Int64
        let modified: Date?
    }
}

private struct CareSidebar: View {
    @Binding var selectedItem: CareSidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
                .frame(height: 90)

            ForEach(CareSidebarItem.mainItems) { item in
                SidebarButton(
                    item: item,
                    isSelected: selectedItem == item
                ) {
                    selectedItem = item
                }
            }

            Spacer()

            SidebarButton(
                item: .assistant,
                isSelected: selectedItem == .assistant
            ) {
                selectedItem = .assistant
            }
            .padding(.bottom, 42)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(AppTheme.Colors.appBackground)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AppTheme.Colors.border.opacity(0.7))
                        .frame(width: 1)
            }
        }
    }
}

private struct SidebarButton: View {
    let item: CareSidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                if isSelected {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.iconColor)
                        .frame(width: 42, height: 42)
                }

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textPrimary.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .frame(height: 58)
            .padding(.horizontal, isSelected ? 16 : 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.Care.actionGradient)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.28), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}

enum CareSidebarItem: String, CaseIterable, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter
    case assistant

    var id: String { rawValue }

    static let mainItems: [CareSidebarItem] = [
        .smartCare,
        .cleanup,
        .performance,
        .applications,
        .myClutter
    ]

    var title: String {
        switch self {
        case .smartCare:
            "Care"
        case .cleanup:
            "Junk Cleaner"
        case .performance:
            "Boost"
        case .applications:
            "App Manager"
        case .myClutter:
            "Clutter"
        case .assistant:
            "Assistant"
        }
    }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        case .assistant:
            "circle.grid.cross.fill"
        }
    }

    var iconColor: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0x8299FF).opacity(0.95),
                Color(hex: 0x6377E8).opacity(0.9),
                Color(hex: 0x3E4FBE).opacity(0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let selectedIconColor = LinearGradient(
        colors: [Color(hex: 0x6F83EA), Color(hex: 0x5366D6)],
        startPoint: .top,
        endPoint: .bottom
    )
}

private struct CareSectionBackground: View {
    let selectedItem: CareSidebarItem

    var body: some View {
        SectionGradientBackground(
            colors: [
                AppTheme.Colors.appBackground,
                AppTheme.Colors.appBackground,
                AppTheme.Colors.appBackground
            ],
            glow: Color(hex: 0x86A6FF),
            glowCenter: selectedItem == .smartCare ? UnitPoint(x: 0.64, y: 0.24) : UnitPoint(x: 0.26, y: 0.22)
        )
    }
}

private struct SectionGradientBackground: View {
    let colors: [Color]
    let glow: Color
    let glowCenter: UnitPoint

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear,
                    .clear
                ],
                center: glowCenter,
                startRadius: 20,
                endRadius: 640
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.18),
                startRadius: 12,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.3, y: 0.72),
                startRadius: 30,
                endRadius: 580
            )

            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct CareBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.Colors.appBackground,
                    AppTheme.Colors.appBackground,
                    AppTheme.Colors.appBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.64, y: 0.24),
                startRadius: 20,
                endRadius: 480
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.76),
                startRadius: 20,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .clear,
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    CareView()
        .frame(width: 1180, height: 760)
}
