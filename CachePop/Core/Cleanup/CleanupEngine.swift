import Foundation

/// Scans for reclaimable space and removes only what the user confirmed.
///
/// Rules the engine enforces regardless of what the UI passes in:
/// - every path is re-checked by `PathSafety` immediately before it's touched;
/// - anything in use (booted simulator, running build, open app) is re-checked and skipped;
/// - freed space is measured from the volume, not summed from file sizes.
nonisolated struct CleanupEngine: Sendable {
    let env: CleanupEnvironment

    init(env: CleanupEnvironment = .live) {
        self.env = env
    }

    // MARK: Scan

    /// Runs every scanner concurrently and reports each group as soon as it's ready.
    /// `settings` sets the re-download threshold, the log age and the Never Clean list.
    /// `@concurrent` so the work (and the Never Clean sizing) stays off the caller's actor.
    @concurrent
    func scan(
        settings: CleanupSettings = .standard,
        onGroup: @escaping @Sendable (CleanupGroup) async -> Void = { _ in }
    ) async -> CleanupScanResult {
        let processes = await env.processes.snapshot()
        let tools = await env.tools.locate()
        let context = ScanContext(env: env, processes: processes, tools: tools, settings: settings)

        var groups: [CleanupGroup] = []
        await withTaskGroup(of: CleanupGroup.self) { taskGroup in
            taskGroup.addTask { XcodeScanner.scan(context) }
            taskGroup.addTask {
                let apple = await SimulatorScanner.scan(context)
                return apple.appending(AndroidScanner.scan(context), sortRecommendedFirst: false)
            }
            taskGroup.addTask {
                async let caches = DeveloperCacheScanner.scan(context)
                async let docker = DockerScanner.scan(context)
                return await caches.appending(docker, sortRecommendedFirst: true)
            }
            taskGroup.addTask { DeviceFilesScanner.scan(context) }
            taskGroup.addTask { await LeftoversScanner.scan(context) }
            taskGroup.addTask { GeneralScanner.scan(context) }

            for await scanned in taskGroup {
                let tuned = RecommendationPolicy.apply(to: scanned, threshold: settings.largeDownloadThreshold)
                let group = settings.neverClean.apply(to: tuned)
                groups.append(group)
                // A cancelled scan's partial groups must not show up in the next scan's list.
                if !Task.isCancelled { await onGroup(group) }
            }
        }

        let order = CleanupGroupKind.allCases
        return CleanupScanResult(groups: groups.sorted {
            order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)!
        })
    }

    // MARK: Clean

    nonisolated struct Selection: Sendable, Equatable {
        let item: CleanupItem
        let action: CleanupAction
    }

    /// Cleans the selections in order. `onProgress` receives the index about to run. Folders on
    /// the Never Clean list are skipped even if they were added after the scan.
    /// `@concurrent` so deleting and re-measuring never block the caller's actor.
    @concurrent
    func clean(
        _ selections: [Selection],
        neverClean: NeverCleanList = NeverCleanList(),
        onProgress: @escaping @Sendable (Int, CleanupItem) async -> Void = { _, _ in }
    ) async -> CleanupReport {
        let availableBefore = env.space.availableBytes()
        let processes = await env.processes.snapshot()
        let tools = await env.tools.locate()
        let needsSimulatorState = selections.contains { selection in
            switch selection.item.inUseCheck {
            case .simulator, .simulatorSet, .anySimulator: true
            default: false
            }
        }
        let simulators = needsSimulatorState
            ? await SimulatorStates.load(tools: tools, runner: env.commands)
            : SimulatorStates()

        var entries: [CleanupItemReport] = []
        for (index, selection) in selections.enumerated() {
            if Task.isCancelled {
                entries.append(CleanupItemReport(item: selection.item, action: selection.action, outcome: .skipped(reason: "Cancelled.")))
                continue
            }

            await onProgress(index, selection.item)

            if let reason = liveBlockReason(for: selection.item, processes: processes, simulators: simulators) {
                entries.append(CleanupItemReport(item: selection.item, action: selection.action, outcome: .skipped(reason: reason)))
            } else if neverClean.itemIDs.contains(selection.item.id) {
                entries.append(CleanupItemReport(item: selection.item, action: selection.action,
                                                 outcome: .skipped(reason: "It's on your Never Clean list.")))
            } else {
                let (outcome, trashed) = await perform(selection, processes: processes, neverClean: neverClean)
                entries.append(CleanupItemReport(item: selection.item, action: selection.action, outcome: outcome, trashed: trashed))
            }
        }

        let availableAfter = await settledAvailableBytes(after: availableBefore)
        return CleanupReport(entries: entries, availableBefore: availableBefore, availableAfter: availableAfter)
    }

    /// APFS hands space back a moment after files go. Poll until the figure stops growing.
    func settledAvailableBytes(after before: Int64?) async -> Int64? {
        var latest = env.space.availableBytes()
        guard before != nil else { return latest }

        let deadline = Date().addingTimeInterval(env.settleTimeout)
        var stableReadings = 0
        while Date() < deadline, stableReadings < 2 {
            await pause(env.settleInterval)
            let reading = env.space.availableBytes()
            if let reading, let previous = latest, reading <= previous {
                stableReadings += 1
            } else {
                stableReadings = 0
            }
            latest = reading ?? latest
        }
        return latest
    }

    /// Sleeps even after Stop: the report still needs APFS to settle, and a cancelled
    /// `Task.sleep` returns at once, which would turn the loop above into a busy wait.
    private func pause(_ seconds: TimeInterval) async {
        await Task { _ = try? await Task.sleep(for: .seconds(seconds)) }.value
    }

    // MARK: In use

    func liveBlockReason(for item: CleanupItem, processes: ProcessSnapshot, simulators: SimulatorStates) -> String? {
        if item.needsFullDiskAccess {
            return item.blockedReason ?? "CachePop needs Full Disk Access for this."
        }

        // When simctl couldn't say what's booted, assume something is rather than clean under it.
        let unchecked = "Couldn't check whether a simulator is running. Scan again in a moment."
        switch item.inUseCheck {
        case .simulator(let udid):
            if simulators.uncheckedSets.contains(.standard) { return unchecked }
            if simulators.booted.contains(udid) { return "This simulator is booted. Shut it down first." }
            return nil
        case .simulatorSet(let set):
            if simulators.uncheckedSets.contains(set) { return unchecked }
            if simulators.bootedSets.contains(set) {
                return set == .testing ? "Tests are running on these clones." : "A SwiftUI preview is running."
            }
            return nil
        case .anySimulator:
            if simulators.uncheckedSets.contains(.standard) { return unchecked }
            // Test clones and preview simulators share the caches too.
            return simulators.booted.isEmpty && simulators.bootedSets.isEmpty
                ? nil
                : "A simulator is running. Shut it down, then clean."
        default:
            return inUseReason(for: item.inUseCheck, processes: processes)
        }
    }

    // MARK: Perform

    private func perform(
        _ selection: Selection,
        processes: ProcessSnapshot,
        neverClean: NeverCleanList
    ) async -> (CleanupOutcome, [TrashedItem]) {
        let item = selection.item

        switch selection.action.operation {
        case .delete(let urls):
            let failures = urls.flatMap { removeSkipping(neverClean, $0) }
            // Re-measuring is only needed to report a partial failure.
            if failures.isEmpty { return (.removed(bytes: item.sizeBytes), []) }
            let remaining = DirectorySizer.size(ofAll: urls.filter { exists($0) && !neverClean.protects($0) }).bytes
                - DirectorySizer.size(ofAll: urls.flatMap(neverClean.protectedFolders(inside:))).bytes
            return (outcome(for: item, failures: failures, remaining: SizeInfo(bytes: max(remaining, 0))), [])

        case .deleteContents(let folders):
            var failures: [String] = []
            var skippedOpenApps: [String] = []
            var touched: [URL] = []

            for folder in folders where !neverClean.protects(folder) {
                if item.inUseCheck == .appCacheOwners,
                   let owner = AppCacheOwnership.runningOwner(ofFolder: AppCacheOwnership.ownerFolderName(of: folder), processes: processes) {
                    skippedOpenApps.append(owner)
                    continue
                }
                // An unreadable folder (Full Disk Access revoked since the scan) would otherwise
                // list as empty and be reported as cleaned.
                guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                    if exists(folder) { failures.append("\(folder.lastPathComponent) couldn't be read.") }
                    continue
                }
                touched.append(folder)
                for child in children {
                    failures += removeSkipping(neverClean, child)
                }
            }

            // Re-measuring (including kept Never Clean folders, which can be large) is only
            // needed to report a partial result.
            if failures.isEmpty, skippedOpenApps.isEmpty { return (.removed(bytes: item.sizeBytes), []) }
            let kept = DirectorySizer.size(ofAll: touched.flatMap(neverClean.protectedFolders(inside:))).bytes
            let remaining = SizeInfo(bytes: max(DirectorySizer.size(ofAll: touched).bytes - kept, 0))
            let skippedBytes = skippedOpenApps.isEmpty ? 0 : DirectorySizer.size(ofAll: folders.filter { !touched.contains($0) && !neverClean.protects($0) }).bytes
            if !skippedOpenApps.isEmpty, failures.isEmpty {
                let removed = max(item.sizeBytes - skippedBytes - remaining.bytes, 0)
                return (.failed(message: "Skipped caches of apps opened since the scan: \(skippedOpenApps.sorted().joined(separator: ", ")).", removedBytes: removed), [])
            }
            return (outcome(for: item, failures: failures, remaining: remaining, alreadyExcluded: skippedBytes), [])

        case .moveToTrash(let urls):
            var failures: [String] = []
            var trashed: [TrashedItem] = []
            for url in urls {
                // A folder can't be half moved, so anything holding a protected folder stays.
                if neverClean.protects(url) || !neverClean.protectedFolders(inside: url).isEmpty { continue }
                if let violation = PathSafety.violation(for: url, mode: .trash, home: env.home) {
                    failures.append(violation)
                    continue
                }
                do {
                    if let destination = try env.trash.moveToTrash(url) {
                        trashed.append(TrashedItem(original: url, trashed: destination))
                    }
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if failures.isEmpty { return (.movedToTrash(bytes: item.sizeBytes), trashed) }
            return (.failed(message: summary(failures), removedBytes: 0), trashed)

        case .command(let command):
            do {
                // In its own task, so Stop lets the tool finish ("stops after the item in
                // progress") instead of killing it half way.
                let output = try await Task { [env] in try await env.commands.run(command, timeout: 900) }.value
                if output.succeeded { return (.removed(bytes: item.sizeBytes), []) }
                return (.failed(message: "\(command.displayString) failed: \(output.failureSummary)", removedBytes: 0), [])
            } catch CommandError.timedOut {
                return (.failed(message: "\(command.displayString) took too long and was stopped.", removedBytes: 0), [])
            } catch {
                return (.failed(message: "Couldn't run \(command.displayString): \(error.localizedDescription)", removedBytes: 0), [])
            }
        }
    }

    /// Removes `url`, except for folders on the Never Clean list: those are kept, and a folder
    /// holding one is emptied around it instead. Returns failure messages.
    private func removeSkipping(_ neverClean: NeverCleanList, _ url: URL) -> [String] {
        if neverClean.protects(url) { return [] }
        guard !neverClean.isEmpty, !neverClean.protectedFolders(inside: url).isEmpty else {
            return remove(url, mode: .delete).map { [$0] } ?? []
        }
        return FileManager.default.children(of: url).flatMap { removeSkipping(neverClean, $0) }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func outcome(for item: CleanupItem, failures: [String], remaining: SizeInfo, alreadyExcluded: Int64 = 0) -> CleanupOutcome {
        if failures.isEmpty { return .removed(bytes: item.sizeBytes) }
        let removed = max(item.sizeBytes - alreadyExcluded - remaining.bytes, 0)
        return .failed(message: summary(failures), removedBytes: removed)
    }

    private func summary(_ failures: [String]) -> String {
        guard let first = failures.first else { return "" }
        return failures.count == 1 ? first : "\(first) (and \(failures.count - 1) more)"
    }

    /// Removes one file or folder permanently, after the safety check. Returns a failure
    /// message, or nil on success. Read-only folders (some package caches) are made writable
    /// and retried once.
    func remove(_ url: URL, mode: PathSafety.Mode) -> String? {
        if let violation = PathSafety.violation(for: url, mode: mode, home: env.home) {
            return violation
        }

        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
            return nil
        } catch {
            guard fileManager.fileExists(atPath: url.path) || isSymlink(url) else { return nil }
            makeWritable(url)
            do {
                try fileManager.removeItem(at: url)
                return nil
            } catch {
                return "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Adds owner write permission to folders inside `url` (never following symlinks).
    private func makeWritable(_ url: URL) {
        let fileManager = FileManager.default
        guard fileManager.isDirectory(url), !isSymlink(url) else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: child.path)
            }
        }
    }
}

/// Which simulators are booted right now, across the standard, testing and preview sets.
nonisolated struct SimulatorStates: Sendable, Equatable {
    var booted: Set<String> = []
    var bootedSets: Set<SimulatorControl.DeviceSet> = []
    /// Sets simctl couldn't list, so whether anything in them is booted is unknown.
    var uncheckedSets: Set<SimulatorControl.DeviceSet> = []

    static func load(tools: ToolPaths, runner: any CommandRunning) async -> SimulatorStates {
        guard let simctl = tools.simctl else { return SimulatorStates() }
        let control = SimulatorControl(simctl: simctl, runner: runner)
        var states = SimulatorStates()
        for set in [SimulatorControl.DeviceSet.standard, .testing, .previews] {
            guard let devices = try? await control.devices(in: set) else {
                states.uncheckedSets.insert(set)
                continue
            }
            let booted = devices.filter(\.isBooted)
            if set == .standard {
                states.booted = Set(booted.map(\.udid))
            } else if !booted.isEmpty {
                states.bootedSets.insert(set)
            }
        }
        return states
    }
}
