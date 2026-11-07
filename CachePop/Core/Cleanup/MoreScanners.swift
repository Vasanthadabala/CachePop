import Foundation

// MARK: - Android emulators

/// Android emulators (AVDs) and the SDK system images no emulator uses. Reported under
/// "Simulators & emulators" alongside Apple's simulators.
nonisolated enum AndroidScanner {
    /// Files an emulator recreates from its system image on the next boot.
    static let userDataFiles = ["userdata-qemu.img", "userdata-qemu.img.qcow2", "cache.img", "cache.img.qcow2", "snapshots"]

    static func scan(_ context: ScanContext) -> CleanupGroup {
        let env = context.env
        var emulators: [CleanupItem] = []
        var images: [CleanupItem] = []

        let avdFolder = env.path(".android/avd")
        var usedImages = Set<String>()

        for ini in FileManager.default.children(of: avdFolder) where ini.pathExtension == "ini" {
            let name = ini.deletingPathExtension().lastPathComponent
            let folder = avdFolder.appendingPathComponent("\(name).avd", isDirectory: true)
            guard FileManager.default.isDirectory(folder) else { continue }

            let config = keyValues(in: folder.appendingPathComponent("config.ini"))
            if let sysdir = config["image.sysdir.1"] { usedImages.insert(normalizedImagePath(sysdir)) }

            let size = DirectorySizer.size(of: folder)
            let running = isRunning(avd: name, processes: context.processes)
            let wipeTargets = userDataFiles.map { folder.appendingPathComponent($0) }.filter { context.exists($0) }
            let lastUsed = ScanFormatting.relative(lastUsedDate(of: folder), now: env.now())
            let image = config["image.sysdir.1"].map(imageDescription)

            var actions: [CleanupAction] = []
            if !wipeTargets.isEmpty {
                actions.append(CleanupAction(
                    id: "wipe",
                    title: "Wipe Data",
                    operation: .delete(wipeTargets),
                    regeneration: .permanent,
                    explanation: "Removes its apps and data. The emulator stays and starts fresh."
                ))
            }
            actions.append(CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .delete([folder, ini]),
                regeneration: .permanent,
                explanation: "Removes the emulator. Create a new one in Android Studio if you need it."
            ))

            emulators.append(CleanupItem(
                id: "simulators.android.\(name)",
                group: .simulators,
                title: config["avd.ini.displayname"] ?? name.replacingOccurrences(of: "_", with: " "),
                explanation: "An Android emulator, with the apps and data installed on it.",
                detail: [image, running ? "Running" : nil, lastUsed.map { "Used \($0)" }].compactMap { $0 }.joined(separator: " · "),
                sizeBytes: size.bytes,
                actions: actions,
                isRecommended: false,
                blockedReason: running ? "This emulator is running. Close it in Android Studio first." : nil,
                inUseCheck: .androidEmulator(name: name)
            ))
        }

        // System images, three levels down: android-34/google_apis_playstore/arm64-v8a
        let systemImages = env.path("Library/Android/sdk/system-images")
        for api in FileManager.default.children(of: systemImages) where FileManager.default.isDirectory(api) {
            for tag in FileManager.default.children(of: api) where FileManager.default.isDirectory(tag) {
                for abi in FileManager.default.children(of: tag) where FileManager.default.isDirectory(abi) {
                    let relative = "\(api.lastPathComponent)/\(tag.lastPathComponent)/\(abi.lastPathComponent)"
                    guard !usedImages.contains(relative.lowercased()) else { continue }
                    let size = DirectorySizer.size(of: abi)
                    guard size.bytes > 0 else { continue }
                    images.append(CleanupItem(
                        id: "simulators.androidImage.\(relative)",
                        group: .simulators,
                        title: "\(androidVersion(api.lastPathComponent)) system image",
                        explanation: "No emulator uses this system image. Download it again in Android Studio › SDK Manager if you need it.",
                        detail: "\(tagName(tag.lastPathComponent)) · \(abi.lastPathComponent)",
                        sizeBytes: size.bytes,
                        actions: [CleanupAction(
                            id: "delete",
                            title: "Delete",
                            operation: .delete([abi]),
                            regeneration: .redownloaded,
                            explanation: "Deleted. Android Studio downloads it again when an emulator needs it."
                        )],
                        isRecommended: true
                    ))
                }
            }
        }

        return CleanupGroup(
            kind: .simulators,
            items: images.sorted { $0.sizeBytes > $1.sizeBytes } + emulators.sorted { $0.sizeBytes > $1.sizeBytes }
        )
    }

    /// The emulator process is `qemu-system-…` started with `-avd Name` (or `@Name`).
    static func isRunning(avd name: String, processes: ProcessSnapshot) -> Bool {
        processes.commandLines.contains { line in
            (line.contains("qemu-system") || line.contains("emulator"))
                && (line.contains("-avd \(name)") || line.contains("@\(name)"))
        }
    }

    static func keyValues(in file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        return values
    }

    /// "system-images/android-34/google_apis/arm64-v8a/" → "android-34/google_apis/arm64-v8a"
    static func normalizedImagePath(_ sysdir: String) -> String {
        var path = sysdir.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("system-images/") { path.removeFirst("system-images/".count) }
        while path.hasSuffix("/") { path.removeLast() }
        return path.lowercased()
    }

    static func imageDescription(_ sysdir: String) -> String {
        let parts = normalizedImagePath(sysdir).split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return sysdir }
        return "\(androidVersion(parts[0])) · \(tagName(parts[1]))"
    }

    /// "android-34" → "Android 14 (API 34)"
    static func androidVersion(_ folder: String) -> String {
        let api = folder.replacingOccurrences(of: "android-", with: "")
        let names = ["36": "16", "35": "15", "34": "14", "33": "13", "32": "12L", "31": "12", "30": "11", "29": "10", "28": "9"]
        if let name = names[api] { return "Android \(name) (API \(api))" }
        return Int(api) != nil ? "Android API \(api)" : folder
    }

    static func tagName(_ tag: String) -> String {
        switch tag {
        case "google_apis_playstore": "Google Play"
        case "google_apis": "Google APIs"
        case "default": "AOSP"
        default: tag.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func lastUsedDate(of folder: URL) -> Date? {
        let candidates = [folder.appendingPathComponent("userdata-qemu.img.qcow2"),
                          folder.appendingPathComponent("userdata-qemu.img"), folder]
        return candidates.lazy.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.first
    }
}

// MARK: - Docker

/// Docker's build cache and images no container uses, cleaned with Docker's own commands.
/// Containers and volumes are never touched: they can hold data.
nonisolated enum DockerScanner {
    static func scan(_ context: ScanContext) async -> CleanupGroup {
        guard let docker = context.tools.docker else {
            return CleanupGroup(kind: .developerCaches, items: [])
        }

        let df = ToolCommand(executable: docker, arguments: ["system", "df", "--format", "{{json .}}"])
        guard let output = try? await context.env.commands.run(df, timeout: 60), output.succeeded else {
            return CleanupGroup(kind: .developerCaches, items: [], notes: [
                "Docker isn't running, so its images and build cache couldn't be measured. Start Docker and scan again."
            ])
        }

        let usage = DockerOutput.reclaimable(fromSystemDF: output.stdout)
        var items: [CleanupItem] = []

        if let bytes = usage["Build Cache"], bytes > 0 {
            items.append(CleanupItem(
                id: "dev.docker.buildCache",
                group: .developerCaches,
                title: "Docker build cache",
                explanation: "Layers Docker keeps to speed up builds. The next docker build runs every step again, so it takes longer.",
                sizeBytes: bytes,
                actions: [CleanupAction(
                    id: "prune",
                    title: "Clear",
                    operation: .command(ToolCommand(executable: docker, arguments: ["builder", "prune", "--all", "--force"])),
                    regeneration: .automatic,
                    explanation: "Runs docker builder prune. Images and containers stay."
                )],
                isRecommended: false
            ))
        }

        if let bytes = usage["Images"], bytes > 0 {
            items.append(CleanupItem(
                id: "dev.docker.images",
                group: .developerCaches,
                title: "Unused Docker images",
                explanation: "Images no container uses. Docker pulls them again the next time you run or build with them.",
                sizeBytes: bytes,
                actions: [CleanupAction(
                    id: "prune",
                    title: "Remove",
                    operation: .command(ToolCommand(executable: docker, arguments: ["image", "prune", "--all", "--force"])),
                    regeneration: .redownloaded,
                    explanation: "Runs docker image prune. Images in use stay."
                )],
                isRecommended: false
            ))
        }

        let notes = items.isEmpty ? [] : ["Docker containers and volumes are never touched — they can hold your data."]
        return CleanupGroup(kind: .developerCaches, items: items, notes: notes)
    }
}

nonisolated enum DockerOutput {
    /// `docker system df --format '{{json .}}'` prints one JSON object per line, e.g.
    /// `{"Type":"Images","Reclaimable":"1.2GB (47%)",…}`. Returns reclaimable bytes by type.
    static func reclaimable(fromSystemDF output: String) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["Type"] as? String,
                  let reclaimable = object["Reclaimable"] as? String else { continue }
            result[type] = bytes(fromHumanSize: reclaimable)
        }
        return result
    }

    /// "1.234GB (47%)" → 1 234 000 000. Docker counts in powers of 1000.
    static func bytes(fromHumanSize text: String) -> Int64 {
        let token = text.split(separator: " ").first.map(String.init) ?? text
        let number = token.prefix { $0.isNumber || $0 == "." }
        let unit = token.dropFirst(number.count).uppercased()
        guard let value = Double(number) else { return 0 }
        let multiplier: Double = switch unit {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64(value * multiplier)
    }
}

// MARK: - iPhone and iPad

/// Device backups Finder made and iOS restore files it downloaded.
nonisolated enum DeviceFilesScanner {
    static let updateFolders = ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"]

    static func scan(_ context: ScanContext) -> CleanupGroup {
        let env = context.env
        var items: [CleanupItem] = []

        // Restore files
        let updates = updateFolders
            .map { env.path("Library/iTunes/\($0)") }
            .flatMap { FileManager.default.children(of: $0) }
            .filter { $0.pathExtension.lowercased() == "ipsw" }
        let updateSize = DirectorySizer.size(ofAll: updates)
        if updateSize.bytes > 0 {
            items.append(CleanupItem(
                id: "devices.updates",
                group: .devices,
                title: "iOS and iPadOS update files",
                explanation: "Software Finder downloaded to update or restore an iPhone or iPad. Downloaded again if you restore a device.",
                detail: [ScanFormatting.count(updates.count, "file"), updates.map(\.lastPathComponent).sorted().prefix(2).joined(separator: ", ")]
                    .joined(separator: " · "),
                sizeBytes: updateSize.bytes,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .delete(updates),
                    regeneration: .redownloaded,
                    explanation: "Deleted. Finder downloads the software again when it needs it."
                )],
                isRecommended: true
            ))
        }

        // Backups, one item per device
        let backups = env.path(PathSafety.deviceBackupsRoot)
        if context.exists(backups) {
            if let folders = try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for folder in folders where FileManager.default.isDirectory(folder) {
                    if let item = backupItem(folder, now: env.now()) { items.append(item) }
                }
            } else {
                items.append(CleanupItem(
                    id: "devices.backups",
                    group: .devices,
                    title: "iPhone and iPad backups",
                    explanation: "Local backups Finder made of your devices.",
                    sizeBytes: 0,
                    actions: [CleanupAction(id: "trash", title: "Move to Trash", operation: .moveToTrash([]),
                                            regeneration: .movedToTrash, explanation: "Moved to the Trash.")],
                    isRecommended: false,
                    blockedReason: "CachePop needs Full Disk Access to see device backups.",
                    needsFullDiskAccess: true
                ))
            }
        }

        return CleanupGroup(kind: .devices, items: recommendedFirst(items))
    }

    static func backupItem(_ folder: URL, now: Date) -> CleanupItem? {
        let size = DirectorySizer.size(of: folder)
        guard size.bytes > 0 else { return nil }
        let info = NSDictionary(contentsOf: folder.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
        let name = info["Device Name"] as? String ?? info["Display Name"] as? String ?? "Device backup"
        let version = (info["Product Version"] as? String).map { "iOS \($0)" }
        let date = info["Last Backup Date"] as? Date
            ?? (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let backedUp = ScanFormatting.relative(date, now: now).map { "Backed up \($0)" }

        return CleanupItem(
            id: "devices.backup.\(folder.lastPathComponent)",
            group: .devices,
            title: "Backup of \(name)",
            explanation: "A local backup Finder made of this device. Keep it if it's your only backup of a device you still use.",
            detail: [version, backedUp].compactMap { $0 }.joined(separator: " · "),
            sizeBytes: size.bytes,
            actions: [CleanupAction(
                id: "trash",
                title: "Move to Trash",
                operation: .moveToTrash([folder]),
                regeneration: .movedToTrash,
                explanation: "Moved to the Trash, so you can put it back until you empty the Trash."
            )],
            isRecommended: false,
            warning: "Once the Trash is emptied this backup is gone. Back up again in Finder or iCloud first if you need one."
        )
    }
}

// MARK: - Deleted apps

/// Settings and data apps leave behind after they've been deleted.
///
/// Only entries named like an app identifier are considered, never Apple's, and only when no
/// installed or running app (or another app from the same developer) could own them and
/// nothing has touched them for a month. Everything goes to the Trash.
nonisolated enum LeftoversScanner {
    /// Leftovers changed more recently than this are probably still used by something.
    static let minimumAge: TimeInterval = 30 * 86_400
    /// Smaller leftovers are listed together in one row.
    static let individualThreshold: Int64 = 1_000_000

    nonisolated enum Kind: Sendable {
        case folder, groupContainer, plist, savedState, cookies
    }

    static let locations: [(path: String, kind: Kind)] = [
        ("Library/Application Support", .folder),
        ("Library/Containers", .folder),
        ("Library/Group Containers", .groupContainer),
        ("Library/Preferences", .plist),
        ("Library/Saved Application State", .savedState),
        ("Library/HTTPStorages", .cookies),
        ("Library/WebKit", .folder)
    ]

    nonisolated struct Leftover: Sendable {
        let appID: String
        var urls: [URL] = []
        var bytes: Int64 = 0
        var newest: Date?
    }

    static func scan(_ context: ScanContext) async -> CleanupGroup {
        let env = context.env
        let installed = env.apps.installedBundleIDs().union(context.processes.runningAppBundleIDs)
        let ownID = (Bundle.main.bundleIdentifier ?? "").lowercased()
        let cutoff = env.now().addingTimeInterval(-minimumAge)

        var byApp: [String: Leftover] = [:]
        var knownCache: [String: Bool] = [:]

        for location in locations {
            for url in FileManager.default.children(of: env.path(location.path)) {
                guard let appID = appIdentifier(url.lastPathComponent, kind: location.kind),
                      PathSafety.looksLikeThirdPartyIdentifier(url.lastPathComponent),
                      appID != ownID, !ownID.hasPrefix(appID + "."),
                      !isOwned(appID, installed: installed) else { continue }

                let known = knownCache[appID] ?? env.apps.isKnown(bundleID: appID)
                knownCache[appID] = known
                guard !known else { continue }

                var leftover = byApp[appID] ?? Leftover(appID: appID)
                leftover.urls.append(url)
                leftover.bytes += DirectorySizer.size(of: url).bytes
                if let modified = newestModification(url), modified > (leftover.newest ?? .distantPast) {
                    leftover.newest = modified
                }
                byApp[appID] = leftover
            }
        }

        let candidates = byApp.values
            .filter { ($0.newest ?? .distantPast) < cutoff && $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }

        var items: [CleanupItem] = []
        let large = candidates.filter { $0.bytes >= individualThreshold }
        let small = candidates.filter { $0.bytes < individualThreshold }

        for leftover in large {
            let name = displayName(leftover.appID)
            let changed = ScanFormatting.relative(leftover.newest, now: env.now()).map { "last changed \($0)" }
            items.append(CleanupItem(
                id: "leftovers.\(leftover.appID)",
                group: .leftovers,
                title: name,
                explanation: "Settings and data left by \(name), which isn't on this Mac any more. If you reinstall it, it starts fresh.",
                detail: [leftover.appID, ScanFormatting.count(leftover.urls.count, "place"), changed].compactMap { $0 }.joined(separator: " · "),
                sizeBytes: leftover.bytes,
                actions: [trashAction(leftover.urls)],
                isRecommended: false
            ))
        }

        if !small.isEmpty {
            let names = small.map { displayName($0.appID) }
            let listed = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " and \(names.count - 4) more" : "")
            items.append(CleanupItem(
                id: "leftovers.small",
                group: .leftovers,
                title: "Small leftovers of \(ScanFormatting.count(small.count, "app"))",
                explanation: "Settings files left by apps that aren't on this Mac any more.",
                detail: listed,
                sizeBytes: small.reduce(0) { $0 + $1.bytes },
                actions: [trashAction(small.flatMap(\.urls))],
                isRecommended: false
            ))
        }

        // Data coding tools keep for project folders that are gone.
        items += ProjectLeftoversScanner.scan(context)
        return CleanupGroup(kind: .leftovers, items: items)
    }

    private static func trashAction(_ urls: [URL]) -> CleanupAction {
        CleanupAction(
            id: "trash",
            title: "Move to Trash",
            operation: .moveToTrash(urls),
            regeneration: .movedToTrash,
            explanation: "Moved to the Trash, so you can put it back if you reinstall the app."
        )
    }

    /// The app identifier an entry belongs to, lowercased, or nil when it isn't named after one.
    static func appIdentifier(_ name: String, kind: Kind) -> String? {
        var id = name
        switch kind {
        case .folder:
            break
        case .plist:
            guard id.hasSuffix(".plist") else { return nil }
            id = String(id.dropLast(".plist".count))
        case .savedState:
            guard id.hasSuffix(".savedState") else { return nil }
            id = String(id.dropLast(".savedState".count))
        case .cookies:
            if id.hasSuffix(".binarycookies") { id = String(id.dropLast(".binarycookies".count)) }
        case .groupContainer:
            // "ABCDE12345.com.foo.shared" or "group.com.foo.app"
            let labels = id.split(separator: ".", maxSplits: 1).map(String.init)
            if labels.count == 2, labels[0].count == 10, labels[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
                id = labels[1]
            }
            if id.lowercased().hasPrefix("group.") { id = String(id.dropFirst("group.".count)) }
        }

        let lower = id.lowercased()
        let labels = lower.split(separator: ".")
        guard labels.count >= 3, let first = labels.first,
              AppCacheOwnership.reverseDomainPrefixes.contains(String(first)),
              !lower.hasPrefix("com.apple.") else { return nil }
        return lower
    }

    /// Owned when an installed or running app has this identifier, extends it, or comes from
    /// the same developer ("com.google.keystone" ↔ "com.google.chrome").
    static func isOwned(_ appID: String, installed: Set<String>) -> Bool {
        let vendor = appID.split(separator: ".").prefix(2).joined(separator: ".")
        return installed.contains { id in
            id == appID || id.hasPrefix(appID + ".") || appID.hasPrefix(id + ".")
                || id.split(separator: ".").prefix(2).joined(separator: ".") == vendor
        }
    }

    /// "com.figma.desktop" → "Figma"; "com.github.atom" → "Atom".
    static func displayName(_ appID: String) -> String {
        let labels = appID.split(separator: ".").map(String.init)
        let generic: Set<String> = ["github", "gitlab", "electron", "app", "apps", "mac", "macos", "desktop", "inc", "llc"]
        let vendor = labels.count > 1 ? labels[1] : appID
        let last = labels.last ?? appID
        let pick = generic.contains(vendor) || vendor.count < 3 ? last : vendor
        guard let first = pick.first else { return appID }
        return first.uppercased() + pick.dropFirst()
    }

    /// The latest change to an entry or anything directly inside it.
    private static func newestModification(_ url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var dates = [(try? url.resourceValues(forKeys: keys))?.contentModificationDate]
        if FileManager.default.isDirectory(url) {
            dates += FileManager.default.children(of: url).prefix(200).map {
                (try? $0.resourceValues(forKeys: keys))?.contentModificationDate
            }
        }
        return dates.compactMap { $0 }.max()
    }
}
