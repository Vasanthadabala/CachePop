import Foundation

// MARK: - Old files

nonisolated enum OldFiles {
    /// Regular files anywhere under `folder` last changed before `cutoff`, and their total size.
    static func find(in folder: URL, before cutoff: Date) -> (files: [URL], bytes: Int64) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return ([], 0) }

        var files: [URL] = []
        var total: Int64 = 0
        var done = false
        while !done && !Task.isCancelled {
            // Simulator and crash logs can number tens of thousands; drain each file's
            // autoreleased URL and resource values as we go.
            autoreleasepool {
                guard var url = enumerator.nextObject() as? URL else {
                    done = true
                    return
                }
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified < cutoff else { return }
                total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                url.removeAllCachedResourceValues()
                files.append(url)
            }
        }
        return (files, total)
    }
}

// MARK: - Safari and Mail

extension GeneralScanner {
    nonisolated static let safariCheck = BrowserDataScanner.safariCheck
    nonisolated static let mailCheck = InUseCheck.runningApp(bundleIDPrefixes: ["com.apple.mail"], name: "Mail")

    /// Safari's page cache. macOS hides it without Full Disk Access, so then it's listed
    /// blocked with a way to grant it, like the Trash.
    nonisolated static func safariCache(_ context: ScanContext) -> CleanupItem? {
        let folder = context.env.path("Library/Caches/com.apple.Safari")
        guard context.exists(folder) else { return nil }

        let explanation = "Pages, images and scripts Safari saved so sites load faster. Your history, bookmarks, passwords and open tabs aren't touched."
        let action = CleanupAction(
            id: "delete",
            title: "Delete",
            operation: .deleteContents([folder]),
            regeneration: .automatic,
            explanation: "Deleted. Safari saves pages again as you browse."
        )

        guard (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) != nil else {
            return CleanupItem(
                id: "general.safariCache",
                group: .general,
                title: "Safari cache",
                explanation: explanation,
                sizeBytes: 0,
                actions: [action],
                isRecommended: false,
                blockedReason: "CachePop needs Full Disk Access to see Safari's cache.",
                needsFullDiskAccess: true
            )
        }

        let size = DirectorySizer.size(of: folder)
        guard size.bytes > 0 else { return nil }
        return CleanupItem(
            id: "general.safariCache",
            group: .general,
            title: "Safari cache",
            explanation: explanation,
            sizeBytes: size.bytes,
            actions: [action],
            isRecommended: true,
            blockedReason: inUseReason(for: safariCheck, processes: context.processes),
            inUseCheck: safariCheck
        )
    }

    /// Changed more than this after it was saved means you edited the attachment, so it's kept.
    nonisolated static let editedAfter: TimeInterval = 60

    /// Copies Mail saves when you open or preview an attachment. The message keeps the original,
    /// so these are only copies — except ones you edited after opening, which are left alone.
    nonisolated static func mailAttachments(_ context: ScanContext) -> CleanupItem? {
        guard context.exists(context.env.path("Library/Containers/com.apple.mail")) else { return nil }
        let folder = context.env.path("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            return CleanupItem(
                id: "general.mailAttachments",
                group: .general,
                title: "Mail attachments",
                explanation: "Copies of attachments Mail saved when you opened or previewed them.",
                sizeBytes: 0,
                actions: [CleanupAction(id: "delete", title: "Delete", operation: .delete([]), regeneration: .automatic,
                                        explanation: "Deleted. Your messages keep their attachments.")],
                isRecommended: false,
                blockedReason: "CachePop needs Full Disk Access to see Mail's attachments.",
                needsFullDiskAccess: true
            )
        }

        var eligible: [URL] = []
        var edited = 0
        for entry in entries where entry.lastPathComponent != ".DS_Store" {
            if wasEdited(entry) { edited += 1 } else { eligible.append(entry) }
        }
        let size = DirectorySizer.size(ofAll: eligible)
        guard size.bytes > 0 else { return nil }

        return CleanupItem(
            id: "general.mailAttachments",
            group: .general,
            title: "Mail attachments",
            explanation: "Copies of attachments Mail saved when you opened or previewed them. The attachments stay in your messages, and Mail copies them again when you open them.",
            detail: [ScanFormatting.count(eligible.count, "attachment"),
                     edited > 0 ? "\(edited) you changed \(edited == 1 ? "is" : "are") kept" : nil]
                .compactMap { $0 }.joined(separator: " · "),
            sizeBytes: size.bytes,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .delete(eligible),
                regeneration: .automatic,
                explanation: "Deleted. Your messages keep their attachments."
            )],
            isRecommended: true,
            blockedReason: inUseReason(for: mailCheck, processes: context.processes),
            inUseCheck: mailCheck
        )
    }

    /// True when any file in `entry` was changed well after Mail saved it.
    nonisolated static func wasEdited(_ entry: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        func edited(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return false }
            guard let created = values.creationDate, let modified = values.contentModificationDate else { return true }
            return modified.timeIntervalSince(created) > editedAfter
        }
        if edited(entry) { return true }
        guard let enumerator = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: Array(keys)) else { return false }
        for case let url as URL in enumerator {
            // A cancelled check must keep the attachment, rather than mark it safe to remove.
            if Task.isCancelled { return true }
            if autoreleasepool(invoking: { edited(url) }) { return true }
        }
        return false
    }
}

// MARK: - Xcode device logs

extension XcodeScanner {
    /// Where Xcode keeps crash reports it copied from devices: DeviceLogs since Xcode 15.
    nonisolated static let deviceLogFolders = ["DeviceLogs", "iOS Device Logs"]

    /// Device crash reports older than the log age in Settings, like the Mac's own logs.
    nonisolated static func deviceLogs(_ context: ScanContext) -> CleanupItem? {
        let xcode = context.env.path("Library/Developer/Xcode")
        let age = context.settings.logAge
        let cutoff = context.env.now().addingTimeInterval(-age)

        var files: [URL] = []
        var bytes: Int64 = 0
        for name in deviceLogFolders {
            let found = OldFiles.find(in: xcode.appendingPathComponent(name), before: cutoff)
            files += found.files
            bytes += found.bytes
        }
        guard bytes > 0 else { return nil }

        let period = GeneralScanner.ageDescription(age)
        return CleanupItem(
            id: "xcode.deviceLogs",
            group: .xcode,
            title: "Device crash logs",
            explanation: "Crash and diagnostic reports Xcode copied from your iPhone and other devices, older than \(period). Newer ones stay.",
            detail: ScanFormatting.count(files.count, "report"),
            sizeBytes: bytes,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .delete(files),
                regeneration: .automatic,
                explanation: "Deleted. Reports from the last \(period.replacingOccurrences(of: "a ", with: "")) stay."
            )],
            isRecommended: true
        )
    }
}

// MARK: - Broken login items

/// Launch agents in your Library that start something which isn't on this Mac any more.
nonisolated enum BrokenLoginItemsScanner {
    static func scan(_ context: ScanContext) -> CleanupItem? {
        let folder = context.env.path("Library/LaunchAgents")
        var broken: [(url: URL, name: String)] = []
        for plist in FileManager.default.children(of: folder) where plist.pathExtension.lowercased() == "plist" {
            guard !Task.isCancelled, let info = MetadataReader.propertyList(from: plist),
                  let program = program(in: info),
                  isMissing(program) else { continue }
            let label = info["Label"] as? String
            broken.append((plist, label ?? plist.deletingPathExtension().lastPathComponent))
        }
        guard !broken.isEmpty else { return nil }

        let names = broken.map(\.name).sorted()
        let listed = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and \(names.count - 3) more" : "")
        return CleanupItem(
            id: "leftovers.brokenLoginItems",
            group: .leftovers,
            title: "Broken login items",
            explanation: "Set to start when you log in, but the app or program they start isn't on this Mac any more. They can't run, so nothing is lost.",
            detail: [ScanFormatting.count(broken.count, "item"), listed].joined(separator: " · "),
            sizeBytes: DirectorySizer.size(ofAll: broken.map(\.url)).bytes,
            actions: [CleanupAction(
                id: "trash",
                title: "Move to Trash",
                operation: .moveToTrash(broken.map(\.url)),
                regeneration: .movedToTrash,
                explanation: "Moved to the Trash, so you can put them back."
            )],
            isRecommended: true
        )
    }

    /// What a launch agent starts: `Program`, or the first of `ProgramArguments`.
    static func program(in info: [String: Any]) -> String? {
        info["Program"] as? String ?? (info["ProgramArguments"] as? [String])?.first
    }

    /// True only when `path` is definitely gone: an absolute path that isn't on another disk
    /// (which may just be unplugged) and doesn't exist, rather than merely being unreadable.
    static func isMissing(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.hasPrefix("/Volumes/") else { return false }
        var info = stat()
        return stat(path, &info) != 0 && errno == ENOENT
    }
}

// MARK: - Local AI models

/// Models downloaded to run on this Mac with Ollama and LM Studio, one row per model. Never
/// preselected: each one was a deliberate, often large, download.
nonisolated enum LocalModelsScanner {
    static let ollamaCheck = InUseCheck.runningApp(bundleIDPrefixes: ["com.electron.ollama"], executableNames: ["ollama", "Ollama"], name: "Ollama")
    static let lmStudioCheck = InUseCheck.runningApp(bundleIDPrefixes: ["ai.elementlabs.lmstudio"], executableNames: ["LM Studio", "lms"], name: "LM Studio")

    /// LM Studio's models folder: ~/.lmstudio since 0.3, ~/.cache/lm-studio before.
    static let lmStudioFolders = [".lmstudio/models", ".cache/lm-studio/models"]

    static func scan(_ context: ScanContext) -> [CleanupItem] {
        ollama(context) + lmStudio(context)
    }

    // MARK: Ollama

    nonisolated struct OllamaModel {
        let name: String
        let manifest: URL
        let blobNames: Set<String>
        let downloaded: Date?
    }

    /// ~/.ollama/models: manifests/<host>/<namespace>/<model>/<tag> list the blobs each model
    /// uses, and blobs/ holds them, shared between models where they match.
    static func ollama(_ context: ScanContext) -> [CleanupItem] {
        let fileManager = FileManager.default
        let root = context.env.path(".ollama/models")
        let manifests = root.appendingPathComponent("manifests")
        let blobs = root.appendingPathComponent("blobs")
        guard fileManager.isDirectory(blobs) else { return [] }

        var models: [OllamaModel] = []
        var unreadableManifest = false
        for host in fileManager.children(of: manifests) where fileManager.isDirectory(host) {
            guard !Task.isCancelled else { return [] }
            for namespace in fileManager.children(of: host) where fileManager.isDirectory(namespace) {
                guard !Task.isCancelled else { return [] }
                for model in fileManager.children(of: namespace) where fileManager.isDirectory(model) {
                    guard !Task.isCancelled else { return [] }
                    for tag in fileManager.children(of: model) where !fileManager.isDirectory(tag) && !tag.lastPathComponent.hasPrefix(".") {
                        guard !Task.isCancelled else { return [] }
                        guard let names = blobNames(inManifest: tag) else {
                            unreadableManifest = true
                            continue
                        }
                        let downloaded = try? tag.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                        models.append(OllamaModel(
                            name: ollamaName(host: host.lastPathComponent, namespace: namespace.lastPathComponent,
                                             model: model.lastPathComponent, tag: tag.lastPathComponent),
                            manifest: tag, blobNames: names, downloaded: downloaded
                        ))
                    }
                }
            }
        }

        var users: [String: Int] = [:]
        for model in models {
            for name in model.blobNames { users[name, default: 0] += 1 }
        }

        let blocked = inUseReason(for: ollamaCheck, processes: context.processes)
        var items: [CleanupItem] = models.compactMap { model in
            // Blobs another model also uses stay, so that model keeps working.
            let own = model.blobNames.filter { users[$0] == 1 }
                .map { blobs.appendingPathComponent($0) }
                .filter { context.exists($0) }
            let size = DirectorySizer.size(ofAll: own)
            guard size.bytes > 0 else { return nil }
            let shares = own.count < model.blobNames.count
            return CleanupItem(
                id: "dev.ollama.\(model.name)",
                group: .developerCaches,
                title: "Ollama: \(model.name)",
                explanation: "A model you downloaded to run with Ollama. Download it again with ollama pull if you need it.",
                detail: [ScanFormatting.relative(model.downloaded, now: context.env.now()).map { "Downloaded \($0)" },
                         shares ? "Files it shares with other models stay" : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                sizeBytes: size.bytes,
                actions: [CleanupAction(
                    id: "delete",
                    title: "Delete",
                    operation: .delete([model.manifest] + own),
                    regeneration: .redownloaded,
                    explanation: "Deleted. Download it again with ollama pull \(model.name)."
                )],
                isRecommended: false,
                blockedReason: blocked,
                inUseCheck: ollamaCheck
            )
        }

        // Files no model uses: an interrupted download, or what a removed model left. Skipped
        // if any manifest couldn't be read, since its blobs would look unused.
        if !unreadableManifest {
            let unused = fileManager.children(of: blobs).filter { blob in
                let name = blob.lastPathComponent
                return name.hasPrefix("sha256") && users[name] == nil && !fileManager.isDirectory(blob)
            }
            let size = DirectorySizer.size(ofAll: unused)
            if size.bytes > 0 {
                items.append(CleanupItem(
                    id: "dev.ollama.unused",
                    group: .developerCaches,
                    title: "Ollama: unused downloads",
                    explanation: "Model files no downloaded model uses, such as an interrupted download. Ollama doesn't need them.",
                    detail: ScanFormatting.count(unused.count, "file"),
                    sizeBytes: size.bytes,
                    actions: [CleanupAction(
                        id: "delete",
                        title: "Delete",
                        operation: .delete(unused),
                        regeneration: .unusable,
                        explanation: "Deleted. No model uses them."
                    )],
                    isRecommended: true,
                    blockedReason: blocked,
                    inUseCheck: ollamaCheck
                ))
            }
        }
        return items
    }

    /// Blob file names ("sha256-…") a manifest lists, or nil when it can't be read.
    static func blobNames(inManifest url: URL) -> Set<String>? {
        guard let data = MetadataReader.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var digests: [String] = []
        if let config = json["config"] as? [String: Any], let digest = config["digest"] as? String {
            digests.append(digest)
        }
        for layer in json["layers"] as? [[String: Any]] ?? [] {
            if let digest = layer["digest"] as? String { digests.append(digest) }
        }
        guard !digests.isEmpty else { return nil }
        return Set(digests.map { $0.replacingOccurrences(of: ":", with: "-") })
    }

    /// "llama3.2:3b" for Ollama's own library, "user/model:tag" or "hf.co/user/model:tag" otherwise.
    static func ollamaName(host: String, namespace: String, model: String, tag: String) -> String {
        if host == "registry.ollama.ai" {
            return namespace == "library" ? "\(model):\(tag)" : "\(namespace)/\(model):\(tag)"
        }
        return "\(host)/\(namespace)/\(model):\(tag)"
    }

    // MARK: LM Studio

    /// models/<publisher>/<model>/…, one row per model folder.
    static func lmStudio(_ context: ScanContext) -> [CleanupItem] {
        let fileManager = FileManager.default
        let blocked = inUseReason(for: lmStudioCheck, processes: context.processes)
        var items: [CleanupItem] = []

        for relative in lmStudioFolders {
            guard !Task.isCancelled else { return [] }
            let root = context.env.path(relative)
            for publisher in fileManager.children(of: root) where fileManager.isDirectory(publisher) {
                guard !Task.isCancelled else { return [] }
                for model in fileManager.children(of: publisher) where fileManager.isDirectory(model) {
                    guard !Task.isCancelled else { return [] }
                    let size = DirectorySizer.size(of: model)
                    guard size.bytes > 0 else { continue }
                    let modified = try? model.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    items.append(CleanupItem(
                        id: "dev.lmstudio.\(publisher.lastPathComponent)/\(model.lastPathComponent)",
                        group: .developerCaches,
                        title: "LM Studio: \(model.lastPathComponent)",
                        explanation: "A model you downloaded to run in LM Studio. Download it again in LM Studio if you need it.",
                        detail: [publisher.lastPathComponent,
                                 ScanFormatting.relative(modified, now: context.env.now()).map { "Downloaded \($0)" }]
                            .compactMap { $0 }.joined(separator: " · "),
                        sizeBytes: size.bytes,
                        actions: [CleanupAction(
                            id: "delete",
                            title: "Delete",
                            operation: .delete([model]),
                            regeneration: .redownloaded,
                            explanation: "Deleted. Download it again in LM Studio."
                        )],
                        isRecommended: false,
                        blockedReason: blocked,
                        inUseCheck: lmStudioCheck
                    ))
                }
            }
        }
        return items
    }
}

// MARK: - Time Machine local snapshots

/// Hourly restore points Time Machine keeps on the Mac's own disk between backups.
nonisolated enum TimeMachineScanner {
    static let tmutil = URL(fileURLWithPath: "/usr/bin/tmutil")

    static func scan(_ context: ScanContext) async -> CleanupGroup {
        let list = ToolCommand(executable: tmutil, arguments: ["listlocalsnapshotdates", "/"])
        guard let output = try? await context.env.commands.run(list, timeout: 30), output.succeeded else {
            return CleanupGroup(kind: .general, items: [])
        }
        let dates = snapshotDates(in: output.stdout)
        guard let oldest = dates.min() else { return CleanupGroup(kind: .general, items: []) }

        let item = CleanupItem(
            id: "general.timeMachineSnapshots",
            group: .general,
            title: "Time Machine local snapshots",
            explanation: "Restore points Time Machine keeps on this Mac between backups. Your backups on the backup disk aren't touched. macOS already counts this space as free and reclaims it when something needs room; removing them frees it right away.",
            detail: [ScanFormatting.count(dates.count, "snapshot"),
                     ScanFormatting.relative(oldest, now: context.env.now()).map { "oldest from \($0)" }]
                .compactMap { $0 }.joined(separator: " · "),
            // Snapshots only report their size as part of the purgeable space.
            sizeBytes: context.env.space.purgeableBytes() ?? 0,
            sizeIsUpperBound: true,
            actions: [CleanupAction(
                id: "delete",
                title: "Delete",
                operation: .command(ToolCommand(executable: tmutil, arguments: ["deletelocalsnapshots", "/"])),
                regeneration: .permanent,
                explanation: "Deletes them with tmutil deletelocalsnapshots. Time Machine makes new ones at its next backup."
            )],
            isRecommended: false,
            entries: dates.sorted().map { date in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let token = formatter.string(from: date)
                return CleanupEntry(id: token, title: date.formatted(date: .abbreviated, time: .standard),
                                    detail: token, sizeBytes: nil,
                                    operations: ["delete": .command(ToolCommand(executable: tmutil,
                                                                               arguments: ["deletelocalsnapshots", token]))])
            }
        )
        return CleanupGroup(kind: .general, items: [item])
    }

    /// Dates from `tmutil listlocalsnapshotdates` lines such as "2026-11-08-101530".
    static func snapshotDates(in output: String) -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return output.split(separator: "\n").compactMap { line in
            formatter.date(from: line.trimmingCharacters(in: .whitespaces))
        }
    }
}
