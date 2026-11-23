import Foundation
import SQLite3

/// Data that coding tools keep for each project folder, found for projects that are no
/// longer on this Mac (deleted or moved). Offered unticked and only ever moved to the Trash:
/// it can hold conversations the user may still want.
nonisolated enum ProjectLeftoversScanner {
    /// One tool's data for one missing project.
    nonisolated struct Orphan: Sendable, Equatable {
        let project: String
        let urls: [URL]
    }

    /// VS Code-based editors, by their folder in Application Support. They keep one
    /// workspaceStorage entry per opened folder.
    static let codeEditors: [(folder: String, name: String)] = [
        ("Code", "VS Code"), ("Code - Insiders", "VS Code Insiders"), ("Cursor", "Cursor"),
        ("Windsurf", "Windsurf"), ("Antigravity", "Antigravity"), ("VSCodium", "VSCodium"),
        ("Kiro", "Kiro"), ("Trae", "Trae"), ("Void", "Void")
    ]

    static func scan(_ context: ScanContext) -> [CleanupItem] {
        let home = context.env.home
        var items: [CleanupItem] = []
        if let item = makeItem(id: "claudeCode", tool: "Claude Code",
                               what: "Conversations Claude Code saved",
                               orphans: claudeCode(home: home)) {
            items.append(item)
        }
        if let item = makeItem(id: "codex", tool: "Codex",
                               what: "Conversations Codex saved",
                               orphans: codex(home: home)) {
            items.append(item)
        }
        for editor in codeEditors {
            if let item = makeItem(id: "editor.\(editor.folder.lowercased().replacingOccurrences(of: " ", with: ""))",
                                   tool: editor.name,
                                   what: "Workspace state \(editor.name) kept (open tabs, search history, extension data)",
                                   orphans: workspaceStorage(home: home, editorFolder: editor.folder)) {
                items.append(item)
            }
        }
        return items
    }

    /// True only when the project is gone from a disk that's connected. A project on an
    /// external drive that isn't plugged in is not counted as deleted.
    static func isGone(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard !Task.isCancelled, path.hasPrefix("/"), path != "/", !fileManager.fileExists(atPath: path) else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.first == "Volumes" {
            guard parts.count >= 2 else { return false }
            return fileManager.fileExists(atPath: "/Volumes/\(parts[1])")
        }
        return true
    }

    // MARK: Claude Code

    /// `~/.claude/projects/<encoded path>/`: one folder per project, holding session
    /// transcripts. The folder name loses spaces and dashes, so the real path comes from the
    /// `cwd` recorded in the transcripts.
    static func claudeCode(home: URL) -> [Orphan] {
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        return FileManager.default.children(of: projects).compactMap { folder in
            guard !Task.isCancelled, FileManager.default.isDirectory(folder), let cwd = recordedCwd(inTranscriptsOf: folder),
                  isGone(cwd) else { return nil }
            return Orphan(project: cwd, urls: [folder])
        }
    }

    /// The working folder written in the newest transcripts, from their first few hundred lines.
    static func recordedCwd(inTranscriptsOf folder: URL) -> String? {
        let transcripts = FileManager.default.children(of: folder)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { modified($0) > modified($1) }
        for file in transcripts.prefix(3) {
            guard !Task.isCancelled else { return nil }
            // The 512 KB read and the parsed lines are autoreleased; without a pool every project
            // folder's buffers stay alive until the whole scan ends.
            let found: String? = autoreleasepool {
                guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
                defer { try? handle.close() }
                let data = (try? handle.read(upToCount: 512 * 1024)) ?? Data()
                for line in data.split(separator: UInt8(ascii: "\n")).prefix(400) {
                    if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                       let cwd = object["cwd"] as? String, cwd.hasPrefix("/") {
                        return cwd
                    }
                }
                return nil
            }
            if let found { return found }
        }
        return nil
    }

    // MARK: Codex

    /// Codex records each conversation's folder (`cwd`) and file (`rollout_path`) in its
    /// state database. Rollouts are often compressed afterwards, gaining `.zst`.
    static func codex(home: URL) -> [Orphan] {
        let codexFolder = home.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexFolder.appendingPathComponent("sessions", isDirectory: true).standardizedFileURL.path + "/"
        guard let database = FileManager.default.children(of: codexFolder)
            .filter({ $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" })
            .max(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        else { return [] }

        var byProject: [String: [URL]] = [:]
        for (cwd, rollout) in threads(in: database) where isGone(cwd) {
            let candidates = [rollout, rollout + ".zst"].map { URL(fileURLWithPath: $0).standardizedFileURL }
            // Only conversation files inside ~/.codex/sessions, whatever the database says.
            guard let file = candidates.first(where: { $0.path.hasPrefix(sessions) && FileManager.default.fileExists(atPath: $0.path) })
            else { continue }
            byProject[cwd, default: []].append(file)
        }
        return byProject.map { Orphan(project: $0.key, urls: $0.value) }
    }

    /// `(cwd, rollout_path)` for every thread, read without changing the database.
    static func threads(in database: URL) -> [(String, String)] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT cwd, rollout_path FROM threads", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [(String, String)] = []
        while !Task.isCancelled, sqlite3_step(statement) == SQLITE_ROW {
            guard let cwd = sqlite3_column_text(statement, 0), let rollout = sqlite3_column_text(statement, 1) else { continue }
            rows.append((String(cString: cwd), String(cString: rollout)))
        }
        return rows
    }

    // MARK: Code editors

    /// `User/workspaceStorage/<id>/workspace.json` names the folder (or .code-workspace
    /// file) each entry belongs to.
    static func workspaceStorage(home: URL, editorFolder: String) -> [Orphan] {
        let storage = home.appendingPathComponent("Library/Application Support/\(editorFolder)/User/workspaceStorage", isDirectory: true)
        return FileManager.default.children(of: storage).compactMap { entry in
            autoreleasepool {
                guard !Task.isCancelled else { return nil }
                let manifest = entry.appendingPathComponent("workspace.json")
                guard let data = MetadataReader.data(from: manifest),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let uri = (object["folder"] ?? object["workspace"]) as? String,
                      let url = URL(string: uri), url.isFileURL,
                      isGone(url.path) else { return nil }
                return Orphan(project: url.path, urls: [entry])
            }
        }
    }

    // MARK: Items

    static func makeItem(id: String, tool: String, what: String, orphans: [Orphan]) -> CleanupItem? {
        let sized = orphans.map { orphan in
            (orphan, orphan.urls.map(DirectorySizer.size(of:)).reduce(SizeInfo.zero, +).bytes)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        guard !sized.isEmpty else { return nil }

        let total = sized.reduce(Int64(0)) { $0 + $1.1 }
        let largest = sized.prefix(3).map { "\(URL(fileURLWithPath: $0.0.project).lastPathComponent) \(ByteSize.string($0.1))" }
        let count = sized.count
        return CleanupItem(
            id: "leftovers.projects.\(id)",
            group: .leftovers,
            title: "\(tool): deleted projects",
            explanation: "\(what) for project folders that are no longer on this Mac, deleted or moved. Moved to the Trash, so you can put them back.",
            detail: "\(count) \(count == 1 ? "project" : "projects") · Largest: \(largest.joined(separator: ", "))",
            sizeBytes: total,
            actions: [CleanupAction(
                id: "trash",
                title: "Move to Trash",
                operation: .moveToTrash(sized.flatMap(\.0.urls)),
                regeneration: .movedToTrash,
                explanation: "Moved to the Trash. Put it back if you need it."
            )],
            isRecommended: false,
            entries: sized.map { orphan, bytes in
                CleanupEntry(id: orphan.project, title: URL(fileURLWithPath: orphan.project).lastPathComponent,
                             detail: orphan.project, sizeBytes: bytes,
                             operations: ["trash": .moveToTrash(orphan.urls)], location: orphan.urls.first)
            }
        )
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
