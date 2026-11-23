import Foundation

/// What every scanner gets: where home is, what's running, and which tools exist.
nonisolated struct ScanContext: Sendable {
    let env: CleanupEnvironment
    let processes: ProcessSnapshot
    let tools: ToolPaths
    var settings: CleanupSettings = .standard

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

nonisolated enum ScanFormatting {
    /// "Largest: Google 1.3 GB, Brave 814 MB"
    static func largest(_ entries: [(name: String, bytes: Int64)], limit: Int = 3) -> String? {
        let top = entries.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }.prefix(limit)
        guard !top.isEmpty else { return nil }
        return "Largest: " + top.map { "\($0.name) \(ByteSize.string($0.bytes))" }.joined(separator: ", ")
    }

    static func count(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }

    static func relative(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Xcode

nonisolated enum XcodeScanner {
    /// Archives older than this are offered (never preselected).
    static let archiveAge: TimeInterval = 90 * 86_400

    static let deviceSupportFolders: [(folder: String, platform: String, devices: String)] = [
        ("iOS DeviceSupport", "iOS", "iPhones and iPads"),
        ("watchOS DeviceSupport", "watchOS", "Apple Watches"),
        ("tvOS DeviceSupport", "tvOS", "Apple TVs"),
        ("visionOS DeviceSupport", "visionOS", "Vision Pro devices"),
        ("xrOS DeviceSupport", "visionOS", "Vision Pro devices"),
        ("macOS DeviceSupport", "macOS", "Macs")
    ]

    static func scan(_ context: ScanContext) -> CleanupGroup {
        let env = context.env
        let xcode = env.path("Library/Developer/Xcode")
        var items: [CleanupItem] = []

        // Derived data
        let derivedData = xcode.appendingPathComponent("DerivedData")
        let projects = FileManager.default.children(of: derivedData)
            .map { (url: $0, size: DirectorySizer.size(of: $0)) }
        let derivedTotal = projects.reduce(SizeInfo.zero) { $0 + $1.size }
        if derivedTotal.bytes > 0 {
            let projectCount = projects.filter { !$0.url.lastPathComponent.hasSuffix(".noindex") }.count
            let largest = ScanFormatting.largest(projects.map { (projectName($0.url.lastPathComponent), $0.size.bytes) })
            items.append(CleanupItem(
                id: "xcode.derivedData",
                group: .xcode,
                title: "Derived data",
                explanation: "Build products, intermediate files and indexes for every project you've built. Xcode rebuilds them; the first build afterwards is slower.",
                detail: [ScanFormatting.count(projectCount, "project"), largest].compactMap { $0 }.joined(separator: " · "),
                sizeBytes: derivedTotal.bytes,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .deleteContents([derivedData]),
                    regeneration: .automatic,
                    explanation: "Deleted. Xcode rebuilds it on the next build."
                )],
                isRecommended: true,
                blockedReason: context.processes.runningBuildTool.map { "A build is running (\($0)). Clean again when it finishes." },
                inUseCheck: .buildTools,
                entries: projects.map { project in
                    CleanupEntry(id: project.url.path, title: projectName(project.url.lastPathComponent),
                                 detail: project.url.path, sizeBytes: project.size.bytes,
                                 operations: ["delete": .delete([project.url])], location: project.url)
                }.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
            ))
        }

        // Device support
        for entry in deviceSupportFolders {
            let folder = xcode.appendingPathComponent(entry.folder)
            let versions = FileManager.default.children(of: folder).filter { FileManager.default.isDirectory($0) }
            let size = DirectorySizer.size(of: folder)
            guard size.bytes > 0 else { continue }

            let names = versions.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            let listed = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
            items.append(CleanupItem(
                id: "xcode.deviceSupport.\(entry.folder)",
                group: .xcode,
                title: "\(entry.platform) device support",
                explanation: "Debug symbols Xcode copied from \(entry.devices) you've connected. Copied again the next time you connect that device, which takes a few minutes.",
                detail: [ScanFormatting.count(versions.count, "version"), listed].filter { !$0.isEmpty }.joined(separator: " · "),
                sizeBytes: size.bytes,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .deleteContents([folder]),
                    regeneration: .onDeviceConnect,
                    explanation: "Deleted. Xcode copies the symbols again when the device connects."
                )],
                isRecommended: true
            ))
        }

        if let logs = deviceLogs(context) { items.append(logs) }

        // Xcode's own caches
        let cachesFolder = env.path("Library/Caches")
        let xcodeCacheFolders = FileManager.default.children(of: cachesFolder)
            .filter { $0.lastPathComponent.lowercased().hasPrefix("com.apple.dt.") }
            + [xcode.appendingPathComponent("DocumentationCache")].filter { context.exists($0) }
        let xcodeCacheSize = DirectorySizer.size(ofAll: xcodeCacheFolders)
        if xcodeCacheSize.bytes > 0 {
            let xcodeOpen = context.processes.runningAppBundleIDs.contains("com.apple.dt.xcode")
            items.append(CleanupItem(
                id: "xcode.caches",
                group: .xcode,
                title: "Xcode caches",
                explanation: "Download, documentation and module caches Xcode keeps. Xcode re-creates what it needs.",
                sizeBytes: xcodeCacheSize.bytes,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .deleteContents(xcodeCacheFolders),
                    regeneration: .automatic,
                    explanation: "Deleted. Xcode re-creates them."
                )],
                isRecommended: true,
                blockedReason: xcodeOpen ? "Xcode is open. Quit Xcode to clear its caches." : nil,
                inUseCheck: .runningApp(bundleIDPrefixes: ["com.apple.dt.xcode"], name: "Xcode")
            ))
        }

        // Old archives
        let archives = oldArchives(in: xcode.appendingPathComponent("Archives"), now: env.now())
        if !archives.isEmpty {
            let size = DirectorySizer.size(ofAll: archives.map(\.url))
            let names = archives.map(\.name)
            let listed = Array(Set(names)).sorted().prefix(3).joined(separator: ", ")
            items.append(CleanupItem(
                id: "xcode.archives",
                group: .xcode,
                title: "Archives older than 3 months",
                explanation: "Builds you archived for release, with the debug symbols needed to read their crash reports and re-export them. They don't come back.",
                detail: [ScanFormatting.count(archives.count, "archive"), listed].joined(separator: " · "),
                sizeBytes: size.bytes,
                actions: [CleanupAction(
                    id: "trash",
                    title: "Move to Trash",
                    operation: .moveToTrash(archives.map(\.url)),
                    regeneration: .movedToTrash,
                    explanation: "Moved to the Trash, so you can still put them back."
                )],
                isRecommended: false,
                warning: "Keep archives of versions people still use — you need them to read those crash reports."
            ))
        }

        let extraBuilds = AppBuildScanner.scan(context)
        return CleanupGroup(kind: .xcode, items: recommendedFirst(items + extraBuilds.items), notes: extraBuilds.notes)
    }

    /// "CachePop-aszqbgiyscwhnvbbvpxkjsuycqlx" → "CachePop".
    static func projectName(_ folder: String) -> String {
        guard let dash = folder.range(of: "-", options: .backwards) else { return folder }
        let suffix = folder[dash.upperBound...]
        if suffix.count >= 20, suffix.allSatisfy({ $0.isLowercase && $0.isLetter }) {
            return String(folder[..<dash.lowerBound])
        }
        return folder
    }

    nonisolated struct Archive {
        let url: URL
        let name: String
        let date: Date
    }

    static func oldArchives(in folder: URL, now: Date) -> [Archive] {
        let fileManager = FileManager.default
        let candidates = fileManager.children(of: folder).flatMap { child -> [URL] in
            if child.pathExtension == "xcarchive" { return [child] }
            return fileManager.children(of: child).filter { $0.pathExtension == "xcarchive" }
        }

        return candidates.compactMap { url -> Archive? in
            let info = MetadataReader.propertyList(from: url.appendingPathComponent("Info.plist"))
            let created = info?["CreationDate"] as? Date
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            guard let created, now.timeIntervalSince(created) > archiveAge else { return nil }
            let name = info?["Name"] as? String ?? url.deletingPathExtension().lastPathComponent
            return Archive(url: url, name: name, date: created)
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Simulators

nonisolated enum SimulatorScanner {
    static func scan(_ context: ScanContext) async -> CleanupGroup {
        let env = context.env
        var bulk: [CleanupItem] = []
        var runtimes: [CleanupItem] = []
        var deviceItems: [CleanupItem] = []
        var notes: [String] = []

        let control = context.tools.simctl.map { SimulatorControl(simctl: $0, runner: env.commands) }
        var devices: [SimulatorDevice] = []
        if let control {
            do {
                devices = try await control.devices()
            } catch {
                notes.append("Couldn't list simulators with simctl, so they're not shown.")
            }
        } else {
            notes.append("Xcode isn't installed or selected, so simulators can't be listed or removed.")
        }
        let anyBooted = devices.contains(where: \.isBooted)

        // Simulator caches — plain files, so cleanable even without simctl.
        let caches = env.path("Library/Developer/CoreSimulator/Caches")
        let cacheSize = DirectorySizer.size(of: caches)
        if cacheSize.bytes > 0 {
            bulk.append(CleanupItem(
                id: "simulators.caches",
                group: .simulators,
                title: "Simulator caches",
                explanation: "Shared caches simulators build when they boot. Re-created the next time a simulator starts.",
                sizeBytes: cacheSize.bytes,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .deleteContents([caches]),
                    regeneration: .automatic,
                    explanation: "Deleted. Rebuilt when a simulator boots."
                )],
                isRecommended: true,
                blockedReason: anyBooted ? "A simulator is running. Shut it down, then clean." : nil,
                inUseCheck: .anySimulator
            ))
        }

        guard let control else {
            return CleanupGroup(kind: .simulators, items: bulk, notes: notes)
        }

        // Every clone has its own card and a command targeting only its scanned UDID.
        for (set, relative, parentID, label) in [
            (SimulatorDeviceSet.testing, "Library/Developer/XCTestDevices", "simulators.testingClones", "Test clone"),
            (.previews, "Library/Developer/Xcode/UserData/Previews/Simulator Devices", "simulators.previews", "SwiftUI preview")
        ] {
            let folder = env.path(relative)
            guard context.exists(folder) else { continue }
            guard let listed = try? await control.devices(in: set) else {
                notes.append("Couldn't list \(label.lowercased()) simulators. Scan again to include them.")
                continue
            }
            for device in listed {
                bulk.append(individualClone(device, control: control, set: set, parentID: parentID,
                                            label: label, folder: folder, now: env.now(),
                                            setIsBooted: listed.contains(where: \.isBooted)))
            }
        }

        // Unavailable simulators are individual targets too, never `delete unavailable`.
        for device in devices where !device.available {
            bulk.append(individualClone(device, control: control, set: .standard,
                                        parentID: "simulators.unavailable", label: "Runtime unavailable",
                                        folder: env.path("Library/Developer/CoreSimulator/Devices"),
                                        now: env.now(), setIsBooted: device.isBooted))
        }

        // Runtimes no simulator uses
        if let images = try? await control.runtimeImages() {
            let used = Set(devices.map(\.runtimeIdentifier))
            for image in images {
                let size = image.sizeBytes ?? 0
                guard size > 0, image.deletable != false else { continue }
                guard let runtimeID = image.runtimeIdentifier, !used.contains(runtimeID) else { continue }

                let name = SimulatorControl.runtimeName(runtimeID)
                let lastUsed = ScanFormatting.relative(SimulatorControl.date(image.lastUsedAt), now: env.now())
                runtimes.append(CleanupItem(
                    id: "simulators.runtime.\(image.identifier)",
                    group: .simulators,
                    title: "\(name) runtime",
                    explanation: "No simulator uses this runtime. If you need it again, download it in Xcode › Settings › Components.",
                    detail: [image.build.map { "Build \($0)" }, lastUsed.map { "Last used \($0)" }].compactMap { $0 }.joined(separator: " · "),
                    sizeBytes: size,
                    actions: [CleanupAction(
                        id: "delete",
                        title: "Delete",
                        operation: .command(control.command(["runtime", "delete", image.identifier])),
                        regeneration: .redownloaded,
                        explanation: "Deletes the runtime with simctl runtime delete."
                    )],
                    isRecommended: false
                ))
            }
        }

        // Individual simulators
        for device in devices where device.available {
            let runtime = SimulatorControl.runtimeName(device.runtimeIdentifier)
            let lastUsed = ScanFormatting.relative(SimulatorControl.date(device.lastUsedAt), now: env.now())
            deviceItems.append(CleanupItem(
                id: "simulators.device.\(device.udid)",
                group: .simulators,
                title: device.name,
                explanation: "Apps and data installed on this simulator.",
                detail: [runtime, device.isBooted ? "Booted" : "Shut down", lastUsed.map { "Used \($0)" }]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                sizeBytes: deviceSize(device),
                sizeIsUpperBound: true,
                actions: [
                    CleanupAction(
                        id: "erase",
                        title: "Erase",
                        operation: .command(control.command(["erase", device.udid])),
                        regeneration: .permanent,
                        explanation: "Removes its apps and data. The simulator stays."
                    ),
                    CleanupAction(
                        id: "delete",
                        title: "Delete",
                        operation: .command(control.command(["delete", device.udid])),
                        regeneration: .permanent,
                        explanation: "Removes the simulator. Create a new one in Xcode if you need it."
                    )
                ],
                isRecommended: false,
                blockedReason: device.isBooted ? "Booted. Shut it down to erase or delete it." : nil,
                inUseCheck: .simulator(udid: device.udid)
            ))
        }

        return CleanupGroup(
            kind: .simulators,
            items: recommendedFirst(bulk) + runtimes.sorted { $0.sizeBytes > $1.sizeBytes } + deviceItems.sorted { $0.sizeBytes > $1.sizeBytes },
            notes: notes
        )
    }

    static func deviceSize(_ device: SimulatorDevice) -> Int64 {
        if let size = device.dataPathSize { return size }
        guard let path = device.dataPath else { return 0 }
        return DirectorySizer.size(of: URL(fileURLWithPath: path)).bytes
    }

    private static func individualClone(_ device: SimulatorDevice, control: SimulatorControl,
                                         set: SimulatorDeviceSet, parentID: String, label: String,
                                         folder: URL, now: Date, setIsBooted: Bool) -> CleanupItem {
        let measured = device.dataPathSize ?? device.dataPath.map {
            DirectorySizer.size(of: URL(fileURLWithPath: $0)).bytes
        } ?? DirectorySizer.size(of: folder.appendingPathComponent(device.udid)).bytes
        let runtime = SimulatorControl.runtimeName(device.runtimeIdentifier)
        let used = ScanFormatting.relative(SimulatorControl.date(device.lastUsedAt), now: now)
        return CleanupItem(
            id: parentID + "." + device.udid, group: .simulators, title: device.name,
            explanation: set == .standard ? "Its runtime is no longer available." : "A simulator Xcode re-creates when it needs it.",
            detail: [runtime, label, device.isBooted ? "Booted" : "Shut down", used.map { "Used \($0)" }]
                .compactMap { $0 }.joined(separator: " · "),
            sizeBytes: measured, sizeIsUpperBound: true,
            actions: [CleanupAction(id: "delete", title: "Delete",
                                    operation: .command(control.command(["delete", device.udid], set: set)),
                                    regeneration: set == .standard ? .unusable : .automatic,
                                    explanation: "Deletes only this simulator.")],
            isRecommended: true,
            blockedReason: setIsBooted ? "A simulator in this set is running. Shut it down before cleaning." : nil,
            inUseCheck: set == .standard ? .simulator(udid: device.udid) : .simulatorSet(set),
            parentID: parentID
        )
    }

}

// MARK: - Developer caches

nonisolated enum DeveloperCacheScanner {
    nonisolated struct Spec: Sendable {
        let id: String
        let title: String
        let relativePath: String
        let explanation: String
        var regeneration: Regeneration = .redownloaded
        var recommended = true
        var inUseCheck: InUseCheck = .none
        /// More folders cleaned with this one, as one item.
        var extraPaths: [String] = []

        var relativePaths: [String] { [relativePath] + extraPaths }
    }

    static let specs: [Spec] = [
        Spec(id: "npm", title: "npm cache", relativePath: ".npm",
             explanation: "Packages npm has downloaded before. npm fetches them again on the next install."),
        Spec(id: "yarn", title: "Yarn cache", relativePath: "Library/Caches/Yarn",
             explanation: "Packages Yarn has downloaded before. Fetched again on the next install."),
        Spec(id: "bun", title: "Bun cache", relativePath: ".bun/install/cache",
             explanation: "Packages Bun has downloaded before. Fetched again on the next install."),
        // Gradle is unticked by default: it's the slowest to rebuild, and the next Android or
        // Java build re-downloads everything before it can start.
        Spec(id: "gradleCaches", title: "Gradle caches", relativePath: ".gradle/caches",
             explanation: "Dependencies and build outputs Gradle keeps for Android and Java projects. The next build downloads and rebuilds them, which can take several minutes.",
             recommended: false,
             inUseCheck: .gradleDaemon),
        Spec(id: "gradleWrapper", title: "Gradle versions", relativePath: ".gradle/wrapper/dists",
             explanation: "Gradle releases your projects' wrappers downloaded. The next build downloads the version it needs before it can start.",
             recommended: false,
             inUseCheck: .gradleDaemon),
        Spec(id: "swiftpm", title: "Swift Package Manager cache", relativePath: "Library/Caches/org.swift.swiftpm",
             explanation: "Swift packages cached by Xcode and swift build. Fetched again when a project resolves its packages.",
             inUseCheck: .buildTools),
        Spec(id: "cocoapods", title: "CocoaPods cache", relativePath: "Library/Caches/CocoaPods",
             explanation: "Pods CocoaPods has downloaded before. Fetched again on the next pod install."),
        Spec(id: "cocoapodsRepos", title: "CocoaPods spec repos", relativePath: ".cocoapods/repos",
             explanation: "A local copy of the CocoaPods spec index. Cloned again on the next pod install, which can take a while.",
             recommended: false),
        Spec(id: "pip", title: "pip cache", relativePath: "Library/Caches/pip",
             explanation: "Python packages pip has downloaded before. Fetched again on the next install."),
        Spec(id: "goBuild", title: "Go build cache", relativePath: "Library/Caches/go-build",
             explanation: "Compiled Go packages. Rebuilt on the next go build.", regeneration: .automatic),
        Spec(id: "cargo", title: "Cargo downloads", relativePath: ".cargo/registry/cache",
             explanation: "Crate archives Cargo downloaded. Fetched again when a build needs them."),
        Spec(id: "maven", title: "Maven repository", relativePath: ".m2/repository",
             explanation: "Java libraries Maven downloaded. Fetched again on the next build — keep it if you build offline.",
             recommended: false),
        Spec(id: "pub", title: "Dart and Flutter packages", relativePath: ".pub-cache",
             explanation: "Packages pub downloaded, plus globally activated tools. Run flutter pub get again afterwards.",
             recommended: false),
        Spec(id: "android", title: "Android SDK cache", relativePath: ".android/cache",
             explanation: "Download metadata the Android SDK tools keep. Re-created automatically.", regeneration: .automatic),
        Spec(id: "nodeGyp", title: "node-gyp headers", relativePath: "Library/Caches/node-gyp",
             explanation: "Node.js headers for building native modules. Downloaded again when needed."),
        Spec(id: "electron", title: "Electron downloads", relativePath: "Library/Caches/electron",
             explanation: "Electron builds fetched by npm installs. Downloaded again when needed."),
        Spec(id: "playwright", title: "Playwright browsers", relativePath: "Library/Caches/ms-playwright",
             explanation: "Browsers Playwright installed for testing. Reinstall them with npx playwright install.",
             recommended: false),
        Spec(id: "deno", title: "Deno cache", relativePath: "Library/Caches/deno",
             explanation: "Modules Deno downloaded. Fetched again when a script needs them."),
        // Only Codex's caches. Its conversations (sessions), thread history and generated
        // images are yours and are never offered.
        Spec(id: "codex", title: "Codex caches", relativePath: ".codex/cache",
             explanation: "The plugin catalog, temporary files and plugin downloads Codex keeps. Codex fetches them again when it needs them. Your conversations and generated images aren't touched.",
             inUseCheck: .runningApp(bundleIDPrefixes: ["com.openai.codex"], executableNames: ["codex"], name: "Codex"),
             extraPaths: [".codex/.tmp", ".codex/plugins/cache"])
    ]

    /// Folders in `~/Library/Caches` handled here, so App caches doesn't count them twice.
    static var libraryCacheFolderNames: Set<String> {
        Set(specs.compactMap { spec in
            spec.relativePath.hasPrefix("Library/Caches/")
                ? String(spec.relativePath.dropFirst("Library/Caches/".count)).lowercased()
                : nil
        } + ["homebrew", "jetbrains"])
    }

    /// `~/.cache` folders that are pure caches. Anything else there is offered unticked,
    /// because some tools keep slow-to-fetch downloads (models, browsers) in it.
    static let knownSafeXDGCaches: Set<String> = [
        "pip", "yarn", "pre-commit", "node-gyp", "typescript", "uv", "pypoetry", "ruff", "mypy",
        "black", "jedi", "go-build", "golangci-lint", "prisma", "turbo", "nx", "selenium", "pnpm"
    ]

    /// `~/.cache` folders another scanner reports in its own way.
    static let xdgHandledElsewhere: Set<String> = ["lm-studio"]

    static func scan(_ context: ScanContext) async -> CleanupGroup {
        let env = context.env
        var items: [CleanupItem] = []

        for spec in specs {
            let urls = spec.relativePaths.map(env.path).filter { FileManager.default.fileExists(atPath: $0.path) }
            let size = urls.map(DirectorySizer.size(of:)).reduce(SizeInfo.zero, +)
            guard size.bytes > 0 else { continue }

            items.append(CleanupItem(
                id: "dev.\(spec.id)",
                group: .developerCaches,
                title: spec.title,
                explanation: spec.explanation,
                sizeBytes: size.bytes,
                sizeIsUpperBound: size.hasSharedFiles,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .deleteContents(urls),
                    regeneration: spec.regeneration,
                    explanation: "Deleted. \(spec.regeneration.label)."
                )],
                isRecommended: spec.recommended,
                blockedReason: inUseReason(for: spec.inUseCheck, processes: context.processes),
                inUseCheck: spec.inUseCheck
            ))
        }

        // ~/.cache, one folder per tool
        let xdg = env.path(".cache")
        for folder in FileManager.default.children(of: xdg) where FileManager.default.isDirectory(folder) {
            // Its models get a row each below; the rest of the folder holds its chats.
            guard !xdgHandledElsewhere.contains(folder.lastPathComponent.lowercased()) else { continue }
            let size = DirectorySizer.size(of: folder)
            guard size.bytes > 0 else { continue }
            let name = folder.lastPathComponent
            let known = knownSafeXDGCaches.contains(name.lowercased())
            items.append(CleanupItem(
                id: "dev.xdg.\(name)",
                group: .developerCaches,
                title: "\(name) (~/.cache)",
                explanation: known
                    ? "Cache files the \(name) tool keeps. Re-created when the tool runs."
                    : "A cache folder made by a command-line tool. Usually re-created when needed, but some tools keep large downloads here.",
                sizeBytes: size.bytes,
                sizeIsUpperBound: size.hasSharedFiles,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .delete([folder]),
                    regeneration: known ? .automatic : .redownloaded,
                    explanation: "Deleted. The tool re-creates it when it needs it."
                )],
                isRecommended: known
            ))
        }

        items += LocalModelsScanner.scan(context)

        // Homebrew
        if let brew = context.tools.brew {
            let dryRun = ToolCommand(executable: brew, arguments: ["cleanup", "--dry-run"], environment: homebrewEnvironment)
            if let output = try? await env.commands.run(dryRun, timeout: 120), output.succeeded {
                let bytes = HomebrewOutput.reclaimableBytes(fromDryRun: output.stdout + "\n" + output.stderr)
                if bytes > 0 {
                    items.append(CleanupItem(
                        id: "dev.homebrew",
                        group: .developerCaches,
                        title: "Homebrew",
                        explanation: "Old versions of installed formulae and casks, and downloads Homebrew keeps. Runs brew cleanup.",
                        sizeBytes: bytes,
                        actions: [CleanupAction(
                            id: "cleanup",
                            title: "Clean up",
                            operation: .command(ToolCommand(executable: brew, arguments: ["cleanup"], environment: homebrewEnvironment)),
                            regeneration: .redownloaded,
                            explanation: "Runs brew cleanup. Current versions stay installed."
                        )],
                        isRecommended: true
                    ))
                }
            }
        }

        return CleanupGroup(kind: .developerCaches, items: recommendedFirst(items))
    }

    static let homebrewEnvironment = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_ANALYTICS": "1",
        "HOMEBREW_NO_ENV_HINTS": "1"
    ]
}

// MARK: - App caches, logs, installers and Trash

nonisolated enum GeneralScanner {
    /// Caches macOS manages itself. Clearing them gains little and can sign you out of things.
    static let appleCacheFolders: Set<String> = [
        "cloudkit", "familycircle", "geoservices", "passkit", "gamekit", "metadata", "siritts"
    ]

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]

    static func scan(_ context: ScanContext) -> CleanupGroup {
        var items: [CleanupItem] = []
        var notes: [String] = []
        var openApps = Set<String>()

        if let appCaches = appCaches(context, openApps: &openApps) { items.append(appCaches) }
        if let webCaches = appWebCaches(context, openApps: &openApps) { items.append(webCaches) }
        if let updates = googleUpdateDownloads(context) { items.append(updates) }
        if let safari = safariCache(context) { items.append(safari) }
        if let mail = mailAttachments(context) { items.append(mail) }
        if !openApps.isEmpty {
            // "Claude Helper" is Claude; name each app once.
            let names = Set(openApps.map { $0.hasSuffix(" Helper") ? String($0.dropLast(" Helper".count)) : $0 }).sorted()
            let listed = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " and \(names.count - 4) more" : "")
            notes.append("Caches of open apps are left alone: \(listed). Quit them and scan again to include them.")
        }
        if let logs = oldLogs(context) { items.append(logs) }
        if let installers = installers(context) { items.append(installers) }
        if let trash = trash(context) { items.append(trash) }

        return CleanupGroup(kind: .general, items: recommendedFirst(items), notes: notes)
    }

    static func appCaches(_ context: ScanContext, openApps: inout Set<String>) -> CleanupItem? {
        let caches = context.env.path("Library/Caches")
        let ownBundleID = (Bundle.main.bundleIdentifier ?? "").lowercased()
        let excluded = DeveloperCacheScanner.libraryCacheFolderNames.union(appleCacheFolders)

        var eligible: [(url: URL, bytes: Int64, app: String)] = []
        var unreadable = 0

        // Shared vendor folders need one owner per app. Never offer Google's parent, which
        // would also erase Android Studio's Local History when Chrome is closed.
        let folders = FileManager.default.children(of: caches).flatMap { folder -> [URL] in
            guard folder.lastPathComponent.lowercased() == "google" else { return [folder] }
            return FileManager.default.children(of: folder).filter {
                !$0.lastPathComponent.lowercased().hasPrefix("androidstudio")
            }
        } + IDECacheScanner.cacheFolders(
            home: context.env.home,
            includesJetBrains: !context.settings.neverClean.itemIDs.contains("dev.jetbrains"),
            includesAndroidStudio: !context.settings.neverClean.itemIDs.contains("general.androidStudioCaches")
        ) + AppCacheDiscovery.sandboxCaches(context)
        for folder in folders where FileManager.default.isDirectory(folder) {
            let name = folder.lastPathComponent.lowercased()
            if excluded.contains(name) || name.hasPrefix("com.apple.") || name == ownBundleID { continue }
            let ownerFolder = AppCacheOwnership.ownerFolderName(of: folder)
            if let owner = AppCacheOwnership.runningOwner(ofFolder: ownerFolder, processes: context.processes) {
                openApps.insert(owner)
                continue
            }
            let size = DirectorySizer.size(of: folder)
            if size.hasUnreadableParts && size.bytes == 0 { unreadable += 1 }
            if size.bytes > 0 {
                eligible.append((folder, size.bytes, IDECachePolicy.displayName(for: ownerFolder) ?? (folder.lastPathComponent == "Caches" ? ownerFolder : folder.lastPathComponent)))
            }
        }

        let total = eligible.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > 0 else { return nil }

        let apps = Dictionary(grouping: eligible, by: \.app).map { name, entries in
            (name, entries.reduce(Int64(0)) { $0 + $1.bytes })
        }
        let largest = ScanFormatting.largest(apps)
        let studioNote = eligible.contains { IDECachePolicy.displayName(for: AppCacheOwnership.ownerFolderName(of: $0.url)) != nil }
            ? " IDE Local History, settings and plugins are kept; indexes rebuild afterwards." : ""
        return CleanupItem(
            id: "general.appCaches",
            group: .general,
            title: "App caches",
            explanation: "Temporary files apps keep so they load faster. Apps re-create what they need; the first launch afterwards may be a little slower." + studioNote,
            detail: [ScanFormatting.count(apps.count, "app"), largest].compactMap { $0 }.joined(separator: " · "),
            sizeBytes: total,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .deleteContents(eligible.map(\.url)),
                regeneration: .automatic,
                explanation: "Deleted. Apps re-create their caches."
            )],
            isRecommended: true,
            inUseCheck: .appCacheOwners,
            entries: Dictionary(grouping: eligible, by: \.app).map { app, caches in
                CleanupEntry(id: app, title: app, detail: caches.map { $0.url.path }.joined(separator: "\n"),
                             sizeBytes: caches.reduce(0) { $0 + $1.bytes },
                             operations: ["delete": .deleteContents(caches.map(\.url))],
                             location: caches.count == 1 ? caches.first?.url : nil)
            }.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        )
    }

    /// Files Chromium leaves in an app's folder. An app folder needs one of these before its
    /// "Cache" folder counts as a web cache; a folder merely named Cache isn't enough.
    static let chromiumMarkers = PathSafety.chromiumMarkers

    /// Page, script and graphics caches that apps built on web technology (Electron and
    /// Chromium: Claude, VS Code, Obsidian, Slack…) keep in Application Support rather than in
    /// ~/Library/Caches. Skipped for apps that are open.
    static func appWebCaches(_ context: ScanContext, openApps: inout Set<String>) -> CleanupItem? {
        let ownName = (Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "CachePop").lowercased()
        var eligible: [(app: String, caches: [URL], bytes: Int64)] = []

        for app in AppCacheDiscovery.webApps(home: context.env.home, excluding: ownName) {
            let caches = app.folders
            guard let first = caches.first else { continue }
            let name = AppCacheOwnership.ownerFolderName(of: first)
            if let owner = AppCacheOwnership.runningOwner(ofFolder: name, processes: context.processes) {
                openApps.insert(owner)
                continue
            }
            let bytes = caches.map(DirectorySizer.size(of:)).reduce(SizeInfo.zero, +).bytes
            if bytes > 0 { eligible.append((name, caches, bytes)) }
        }

        let total = eligible.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > 0 else { return nil }
        let largest = ScanFormatting.largest(eligible.map { ($0.app, $0.bytes) })
        return CleanupItem(
            id: "general.appWebCaches",
            group: .general,
            title: "Web caches in apps",
            explanation: "Page, script and graphics caches that apps built on web technology, such as Claude, VS Code and Slack, keep in their Application Support folder. Re-created when the app next opens.",
            detail: [ScanFormatting.count(eligible.count, "app"), largest].compactMap { $0 }.joined(separator: " · "),
            sizeBytes: total,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .deleteContents(eligible.flatMap(\.caches)),
                regeneration: .automatic,
                explanation: "Deleted. Apps re-create their caches."
            )],
            isRecommended: true,
            inUseCheck: .appCacheOwners,
            entries: eligible.map { app in
                CleanupEntry(id: app.app, title: app.app,
                             detail: app.caches.map(\.path).joined(separator: "\n"), sizeBytes: app.bytes,
                             operations: ["delete": .deleteContents(app.caches)],
                             location: app.caches.first?.deletingLastPathComponent())
            }.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        )
    }

    /// Update packages Google's updater keeps for Chrome and its other apps.
    static func googleUpdateDownloads(_ context: ScanContext) -> CleanupItem? {
        let folder = context.env.path("Library/Application Support/Google/GoogleUpdater/crx_cache")
        let size = DirectorySizer.size(of: folder)
        guard size.bytes > 0 else { return nil }
        let check = InUseCheck.runningApp(bundleIDPrefixes: ["com.google.googleupdater"], executableNames: ["GoogleUpdater"], name: "Google Updater")
        return CleanupItem(
            id: "general.googleUpdates",
            group: .general,
            title: "Google update downloads",
            explanation: "Update packages Google's updater downloaded for Chrome and its other apps. Downloaded again if an update needs them.",
            sizeBytes: size.bytes,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .deleteContents([folder]),
                regeneration: .redownloaded,
                explanation: "Deleted. Downloaded again when needed."
            )],
            isRecommended: true,
            blockedReason: inUseReason(for: check, processes: context.processes),
            inUseCheck: check
        )
    }

    static func oldLogs(_ context: ScanContext) -> CleanupItem? {
        let age = context.settings.logAge
        let cutoff = context.env.now().addingTimeInterval(-age)
        let (files, total) = OldFiles.find(in: context.env.path("Library/Logs"), before: cutoff)

        guard total > 0 else { return nil }
        return CleanupItem(
            id: "general.logs",
            group: .general,
            title: "Old logs and crash reports",
            explanation: "Diagnostic logs and crash reports older than \(ageDescription(age)). Apps keep writing new ones as they run.",
            detail: ScanFormatting.count(files.count, "file"),
            sizeBytes: total,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .delete(files),
                regeneration: .automatic,
                explanation: "Deleted. Logs from the last \(ageDescription(age).replacingOccurrences(of: "a ", with: "")) stay."
            )],
            isRecommended: true
        )
    }

    /// 86 400 → "a day", 7 days → "a week", 30 days → "a month", 90 days → "3 months".
    static func ageDescription(_ age: TimeInterval) -> String {
        let days = Int((age / 86_400).rounded())
        switch days {
        case ...1:  return "a day"
        case 7:     return "a week"
        case 14:    return "2 weeks"
        case 30:    return "a month"
        case 90:    return "3 months"
        default:    return days % 30 == 0 ? "\(days / 30) months" : "\(days) days"
        }
    }

    static func installers(_ context: ScanContext) -> CleanupItem? {
        let downloads = context.env.path("Downloads")
        let files = FileManager.default.children(of: downloads)
            .filter { installerExtensions.contains($0.pathExtension.lowercased()) }
        let size = DirectorySizer.size(ofAll: files)
        guard size.bytes > 0 else { return nil }

        let names = files.map(\.lastPathComponent).sorted()
        return CleanupItem(
            id: "general.installers",
            group: .general,
            title: "Installers in Downloads",
            explanation: "Disk images and installer packages you've downloaded. Usually not needed once the app is installed.",
            detail: [ScanFormatting.count(files.count, "file"), names.prefix(3).joined(separator: ", ")].joined(separator: " · "),
            sizeBytes: size.bytes,
            actions: [CleanupAction(
                id: "trash",
                title: "Move to Trash",
                operation: .moveToTrash(files),
                regeneration: .movedToTrash,
                explanation: "Moved to the Trash, so you can still put them back."
            )],
            isRecommended: false
        )
    }

    static func trash(_ context: ScanContext) -> CleanupItem? {
        let trash = context.env.path(".Trash")
        guard context.exists(trash) else { return nil }

        let explanation = "Files you've already moved to the Trash. Emptying it deletes them for good."
        let action = CleanupAction(
            id: "empty",
            title: "Empty",
            operation: .deleteContents([trash]),
            regeneration: .permanent,
            explanation: "Deletes everything in the Trash. This can't be undone."
        )

        guard let contents = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: []) else {
            return CleanupItem(
                id: "general.trash",
                group: .general,
                title: "Trash",
                explanation: explanation,
                sizeBytes: 0,
                actions: [action],
                isRecommended: false,
                blockedReason: "CachePop needs Full Disk Access to see inside the Trash.",
                needsFullDiskAccess: true
            )
        }

        let size = DirectorySizer.size(ofAll: contents)
        guard size.bytes > 0 else { return nil }
        let visible = contents.filter { $0.lastPathComponent != ".DS_Store" }
        return CleanupItem(
            id: "general.trash",
            group: .general,
            title: "Trash",
            explanation: explanation,
            detail: ScanFormatting.count(visible.count, "item"),
            sizeBytes: size.bytes,
            actions: [action],
            isRecommended: false,
            warning: "Emptying the Trash can't be undone."
        )
    }
}

/// Decides whether a folder in `~/Library/Caches` belongs to an app that's open right now.
nonisolated enum AppCacheOwnership {
    /// The folder that names a cache's app: the cache folder itself in ~/Library/Caches, or
    /// the app's folder for a cache inside Application Support ("Claude/Cache" → "Claude").
    static func ownerFolderName(of cache: URL) -> String {
        let parts = cache.pathComponents
        if let index = parts.firstIndex(of: "Containers"), parts.count > index + 4,
           Array(parts[(index + 2)...(index + 4)]) == ["Data", "Library", "Caches"] {
            return parts[index + 1]
        }
        let parent = cache.deletingLastPathComponent()
        if parent.lastPathComponent.lowercased().hasPrefix("androidstudio"),
           parent.deletingLastPathComponent().lastPathComponent.lowercased() == "google" {
            return "com.google.android.studio"
        }
        if parent.deletingLastPathComponent().lastPathComponent.lowercased() == "jetbrains",
           let product = IDECachePolicy.product(for: parent.lastPathComponent) {
            return product.bundleID
        }
        if let index = parts.firstIndex(of: "Application Support"), parts.count > index + 1 {
            let app = parts[index + 1]
            if ["google", "bravesoftware"].contains(app.lowercased()), parts.count > index + 2 { return parts[index + 2] }
            return app
        }
        return parent.deletingLastPathComponent().lastPathComponent == "Application Support"
            ? parent.lastPathComponent
            : cache.lastPathComponent
    }

    /// Parts of a bundle identifier that say nothing about which app it is.
    private static let genericComponents: Set<String> = [
        "com", "org", "net", "io", "app", "apps", "co", "de", "uk", "dev", "mac", "macos",
        "apple", "desktop", "helper", "agent", "client", "inc", "www", "company", "us"
    ]

    /// First labels that mark a folder name as a reverse-domain identifier.
    static let reverseDomainPrefixes: Set<String> = [
        "com", "org", "net", "io", "co", "app", "company", "us", "de", "uk", "dev", "me", "ai", "eu"
    ]

    /// Cache folders whose names don't follow their app's bundle identifier. Browsers matter
    /// most: clearing a running browser's cache makes it reload and can glitch until restart.
    static let knownOwners: [String: [String]] = [
        "bravesoftware": ["com.brave.browser"],
        "microsoftedge": ["com.microsoft.edgemac"],
        "microsoft": ["com.microsoft.edgemac"],
        "google": ["com.google.chrome"],
        "chromium": ["org.chromium.chromium"],
        "mozilla": ["org.mozilla.firefox"],
        "firefox": ["org.mozilla.firefox"],
        "vivaldi": ["com.vivaldi.vivaldi"],
        "operasoftware": ["com.operasoftware.opera"],
        "arc": ["company.thebrowser.browser"]
    ]

    /// Returns the open app's name, or nil when no open app seems to own the folder.
    ///
    /// Errs towards "owned": a cache left alone costs a little space, a cache cleared under a
    /// running app can make it misbehave.
    static func runningOwner(ofFolder folder: String, processes: ProcessSnapshot) -> String? {
        let lower = folder.lowercased()
        if lower == "com.google.android.studio" {
            return inUseReason(for: IDECacheScanner.inUseCheck, processes: processes) == nil ? nil : "Android Studio"
        }
        let running = processes.runningAppBundleIDs
        func name(_ bundleID: String) -> String { processes.runningAppNames[bundleID] ?? bundleID }

        // "com.spotify.client", "com.tinyspeck.slackmacgap.ShipIt": compare identifiers.
        let labels = lower.split(separator: ".").map(String.init)
        if labels.count >= 2, let first = labels.first, reverseDomainPrefixes.contains(first) {
            let owner = running.first { id in
                lower == id || lower.hasPrefix(id + ".") || id.hasPrefix(lower + ".")
            }
            return owner.map(name)
        }

        // "BraveSoftware", "Microsoft Edge", "Google": compare names.
        let folderKey = normalized(folder)
        guard !folderKey.isEmpty else { return nil }

        if let ids = knownOwners[folderKey],
           let owner = running.first(where: { id in ids.contains { id == $0 || id.hasPrefix($0 + ".") } }) {
            return name(owner)
        }

        for bundleID in running {
            if normalized(name(bundleID)) == folderKey { return name(bundleID) }

            let components = bundleID.split(separator: ".").map(String.init).filter { !genericComponents.contains($0) }
            for component in components.map(normalized) where !component.isEmpty {
                if component == folderKey { return name(bundleID) }
                // "brave" ↔ "bravesoftware", "edgemac" ↔ "edge"; short words only match exactly.
                if component.count >= 4, folderKey.count >= 4,
                   folderKey.hasPrefix(component) || component.hasPrefix(folderKey) {
                    return name(bundleID)
                }
            }
        }
        return nil
    }

    /// Lowercase letters and digits only: "Microsoft Edge" → "microsoftedge".
    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

// MARK: - Shared

/// Why an item can't be cleaned right now, from what's running. Simulator checks need simctl,
/// so the engine handles those separately.
nonisolated func inUseReason(for check: InUseCheck, processes: ProcessSnapshot) -> String? {
    let unknown = "Couldn't check whether this is in use. Scan again in a moment."
    switch check {
    case .buildTools:
        guard processes.executableListAvailable else { return unknown }
        return processes.runningBuildTool.map { "A build is running (\($0)). Clean again when it finishes." }
    case .appBuild(let bundleID, let path):
        if let reason = inUseReason(for: .buildTools, processes: processes) { return reason }
        guard processes.commandLinesAvailable else { return unknown }
        if processes.runningAppPaths.values.contains(where: { paths in
            paths.contains { $0 == path || $0.hasPrefix(path + "/") }
        }) {
            return "This app build is running. Quit it before cleaning this copy."
        }
        if processes.runningAppBundleIDs.contains(bundleID) {
            guard let paths = processes.runningAppPaths[bundleID], !paths.isEmpty, !paths.contains("") else {
                return "This app is open and its location couldn't be checked. Quit it first."
            }
            if paths.contains(where: { $0.contains("/AppTranslocation/") }) {
                return "This app build is running. Quit it before cleaning this copy."
            }
        }
        if processes.commandLines.contains(where: { $0.contains(path + "/") }) {
            return "This app build is running. Quit it before cleaning this copy."
        }
        return nil
    case .gradleDaemon:
        guard processes.commandLinesAvailable else { return unknown }
        return processes.isGradleDaemonRunning
            ? "A Gradle daemon is running. Stop it with ./gradlew --stop, then clean."
            : nil
    case .runningApp(let prefixes, let executables, let name):
        guard executables.isEmpty || processes.executableListAvailable else { return unknown }
        if !processes.executableNames.isDisjoint(with: executables)
            || !processes.runningAppBundleIDs.isDisjoint(with: prefixes) {
            return "\(name) is open. Quit it to clean this."
        }
        // A bundle identifier is a component hierarchy, not an arbitrary text prefix.
        // SafariPlatformSupport.Helper can run for other apps while Safari is closed.
        let background = processes.runningAppBundleIDs.contains { id in
            prefixes.contains { id.hasPrefix($0 + ".") }
        }
        return background ? "\(name) background processes are running. Quit \(name) completely to clean this." : nil
    case .androidEmulator(let name):
        guard processes.commandLinesAvailable else { return unknown }
        return AndroidScanner.isRunning(avd: name, processes: processes)
            ? "This emulator is running. Close it in Android Studio first."
            : nil
    case .none, .simulator, .simulatorSet, .anySimulator, .appCacheOwners:
        return nil
    }
}
