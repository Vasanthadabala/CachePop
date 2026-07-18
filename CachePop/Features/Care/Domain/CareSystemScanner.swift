import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

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

    nonisolated static func scanProtectionItems() -> (count: Int, details: [CareScanDetailItem], permissions: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let browserPrivacyRoots = [
            CacheRoot(url: home.appendingPathComponent("Library/Safari"), kind: "Privacy Trace", label: "Safari Privacy"),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/Google/Chrome"), kind: "Privacy Trace", label: "Chrome Privacy", limit: 3_500),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/Microsoft Edge"), kind: "Privacy Trace", label: "Edge Privacy", limit: 3_500),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/Firefox/Profiles"), kind: "Privacy Trace", label: "Firefox Privacy", limit: 3_500),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser"), kind: "Privacy Trace", label: "Brave Privacy", limit: 3_500),
            CacheRoot(url: home.appendingPathComponent("Library/Application Support/Arc"), kind: "Privacy Trace", label: "Arc Privacy", limit: 3_500)
        ]

        var details: [CareScanDetailItem] = []
        var permissions: [String] = []

        for root in browserPrivacyRoots {
            let partial = privacyTraceDetails(at: root)
            details.append(contentsOf: partial.details)
            permissions.append(contentsOf: partial.permissions)
        }

        let installers = downloadedInstallerDetails(in: home.appendingPathComponent("Downloads"))
        details.append(contentsOf: installers.details)
        permissions.append(contentsOf: installers.permissions)

        let uniqueDetails = uniqueProtectionItems(details)
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(120)
            .map { $0 }

        return (
            count: uniqueDetails.count,
            details: uniqueDetails,
            permissions: uniquePermissions(permissions)
        )
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

    nonisolated private static func privacyTraceDetails(at root: CacheRoot) -> (details: [CareScanDetailItem], permissions: [String]) {
        guard FileManager.default.fileExists(atPath: root.url.path) else {
            return ([], [])
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root.url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { blockedURL, _ in
                return !blockedURL.path.lowercased().contains("/library/")
            }
        ) else {
            return (
                [],
                ["CachePop could not open \(abbreviatedPath(root.url.path)). Grant Full Disk Access to include privacy traces."]
            )
        }

        var details: [CareScanDetailItem] = []
        var scannedFiles = 0

        for case let fileURL as URL in enumerator {
            guard scannedFiles < root.limit, details.count < 80 else { break }
            scannedFiles += 1

            guard isPrivacyTraceFile(fileURL),
                  let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            details.append(detailItem(
                title: fileURL.lastPathComponent,
                subtitle: root.label,
                path: fileURL.path,
                size: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
                kind: root.kind,
                modified: values.contentModificationDate
            ))
        }

        return (details, [])
    }

    nonisolated private static func downloadedInstallerDetails(in downloadsURL: URL) -> (details: [CareScanDetailItem], permissions: [String]) {
        guard FileManager.default.fileExists(atPath: downloadsURL.path) else {
            return ([], [])
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (
                [],
                ["CachePop could not read \(abbreviatedPath(downloadsURL.path)). Grant Full Disk Access to include downloaded installers."]
            )
        }

        let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "appinstaller", "installer"]
        let details = contents
            .filter { installerExtensions.contains($0.pathExtension.lowercased()) }
            .prefix(80)
            .compactMap { url -> CareScanDetailItem? in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey])
                return detailItem(
                    title: url.lastPathComponent,
                    subtitle: "Downloaded Installers",
                    path: url.path,
                    size: Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0),
                    kind: "Installer Leftover",
                    modified: values?.contentModificationDate
                )
            }

        return (details, [])
    }

    nonisolated private static func isPrivacyTraceFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let privacyNames: Set<String> = [
            "history", "history.db", "history.sqlite", "cookies", "cookies.binarycookies",
            "cookies.sqlite", "web data", "favicons", "top sites", "last session",
            "current session", "places.sqlite", "formhistory.sqlite", "downloads.sqlite"
        ]

        return privacyNames.contains(name)
            || name.hasSuffix("history.db")
            || name.hasSuffix("cookies.sqlite")
            || name.contains("session")
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

    nonisolated private static func uniqueProtectionItems(_ items: [CareScanDetailItem]) -> [CareScanDetailItem] {
        var seen = Set<String>()
        return items.filter { item in
            seen.insert(item.path.lowercased()).inserted
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
