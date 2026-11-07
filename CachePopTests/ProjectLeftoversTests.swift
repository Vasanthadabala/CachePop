import Foundation
import SQLite3
import Testing
@testable import CachePop

@Suite("Deleted projects and web caches")
struct ProjectLeftoversTests {
    // MARK: Deleted projects

    @Test func aProjectOnADiskThatIsntConnectedIsNotDeleted() throws {
        let fixture = try Fixture()
        let kept = try fixture.dir("Projects/Kept").path
        #expect(!ProjectLeftoversScanner.isGone(kept))
        #expect(ProjectLeftoversScanner.isGone(fixture.url("Projects/Gone").path))
        #expect(!ProjectLeftoversScanner.isGone("/Volumes/Not-Plugged-In-\(UUID().uuidString)/App"))
        #expect(!ProjectLeftoversScanner.isGone("relative/path"))
        #expect(!ProjectLeftoversScanner.isGone("/"))
    }

    @Test func claudeCodeTranscriptsOfDeletedProjects() async throws {
        let fixture = try Fixture()
        let kept = try fixture.dir("Projects/Kept").path
        let gone = fixture.url("Projects/My App").path
        try transcript(fixture, folder: "-Projects-Kept", cwd: kept)
        try transcript(fixture, folder: "-Projects-My-App", cwd: gone)
        try fixture.file(".claude/projects/-Projects-My-App/a1b2/tool-output.txt", bytes: 40_000)

        let orphans = ProjectLeftoversScanner.claudeCode(home: fixture.home)
        #expect(orphans.map(\.project) == [gone])
        #expect(orphans.first?.urls.map(\.lastPathComponent) == ["-Projects-My-App"])

        let group = await LeftoversScanner.scan(await fixture.context(fixture.environment()))
        let item = try #require(group.item("leftovers.projects.claudeCode"))
        #expect(!item.isRecommended, "unticked: these are conversations")
        #expect(item.defaultAction.regeneration == .movedToTrash)
        #expect(item.detail?.contains("My App") == true)
    }

    @Test func codexConversationsOfDeletedProjects() throws {
        let fixture = try Fixture()
        let kept = try fixture.dir("Projects/Kept").path
        let gone = fixture.url("Projects/Old").path
        let compressed = try fixture.file(".codex/sessions/2026/09/30/rollout-a.jsonl.zst", bytes: 30_000)
        let plain = try fixture.file(".codex/sessions/2026/10/01/rollout-b.jsonl", bytes: 20_000)
        let keptRollout = try fixture.file(".codex/sessions/2026/10/02/rollout-c.jsonl", bytes: 20_000)
        try codexDatabase(fixture, threads: [
            (gone, compressed.path.replacingOccurrences(of: ".zst", with: "")),   // compressed since
            (gone, plain.path),
            (kept, keptRollout.path),
            (gone, "/etc/hosts")                                                    // outside sessions: ignored
        ])

        let orphans = ProjectLeftoversScanner.codex(home: fixture.home)
        #expect(orphans.count == 1)
        #expect(Set(orphans.first?.urls.map(\.lastPathComponent) ?? []) == ["rollout-a.jsonl.zst", "rollout-b.jsonl"])
    }

    @Test func editorWorkspaceDataOfDeletedProjects() throws {
        let fixture = try Fixture()
        let kept = try fixture.dir("Projects/Kept")
        let storage = "Library/Application Support/Cursor/User/workspaceStorage"
        try workspace(fixture, "\(storage)/aaa", uri: kept.absoluteString)
        try workspace(fixture, "\(storage)/bbb", uri: fixture.url("Projects/Gone").absoluteString)
        try workspace(fixture, "\(storage)/ccc", uri: "vscode-remote://ssh-remote+box/home/me/app")

        let orphans = ProjectLeftoversScanner.workspaceStorage(home: fixture.home, editorFolder: "Cursor")
        #expect(orphans.map { $0.urls.first?.lastPathComponent } == ["bbb"])
    }

    @Test func deletedProjectDataOnlyGoesToTheTrash() async throws {
        let fixture = try Fixture()
        try transcript(fixture, folder: "-Projects-Gone", cwd: fixture.url("Projects/Gone").path)
        try workspace(fixture, "Library/Application Support/Code/User/workspaceStorage/bbb", uri: fixture.url("Projects/Gone").absoluteString)

        let home = fixture.home
        #expect(PathSafety.violation(for: fixture.url(".claude/projects/-Projects-Gone"), mode: .trash, home: home) == nil)
        #expect(PathSafety.violation(for: fixture.url(".claude/projects/-Projects-Gone"), mode: .delete, home: home) != nil)
        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/Code/User/workspaceStorage/bbb"), mode: .trash, home: home) == nil)
        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/Code/User/workspaceStorage/bbb"), mode: .delete, home: home) != nil)
        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/Code/User/settings.json"), mode: .trash, home: home) != nil)

        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let selections = result.allItems.filter { $0.id.hasPrefix("leftovers.projects.") }.map { CleanupEngine.Selection(item: $0, action: $0.defaultAction) }
        #expect(selections.count == 2)
        let report = await engine.clean(selections)
        #expect(report.entries.allSatisfy { if case .movedToTrash = $0.outcome { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: fixture.url(".claude/projects/-Projects-Gone").path))
        #expect(FileManager.default.fileExists(atPath: fixture.userTrash.appendingPathComponent("-Projects-Gone").path))
    }

    // MARK: Web caches in apps

    @Test func webCachesOfClosedChromiumAppsOnly() async throws {
        let fixture = try Fixture()
        let support = "Library/Application Support"
        // An Electron app: caches next to Chromium's own files.
        try fixture.file("\(support)/Claude/Cache/Cache_Data/f_000001", bytes: 50_000)
        try fixture.file("\(support)/Claude/Code Cache/js/index", bytes: 20_000)
        try fixture.file("\(support)/Claude/Preferences", bytes: 100)
        try fixture.file("\(support)/Claude/IndexedDB/data.leveldb", bytes: 30_000)
        // A VS Code-based editor: its extra caches count too.
        try fixture.file("\(support)/Code/CachedData/abc/chrome", bytes: 40_000)
        try fixture.file("\(support)/Code/User/settings.json", bytes: 100)
        // Not Chromium: a folder merely called Cache stays.
        try fixture.file("\(support)/SomeApp/Cache/important.db", bytes: 60_000)
        // Open app: left alone.
        try fixture.file("\(support)/Slack/Cache/Cache_Data/x", bytes: 10_000)
        try fixture.file("\(support)/Slack/Local Storage/leveldb", bytes: 100)

        let processes = ProcessSnapshot(runningAppBundleIDs: ["com.tinyspeck.slackmacgap"], runningAppNames: ["com.tinyspeck.slackmacgap": "Slack"])
        let group = GeneralScanner.scan(await fixture.context(fixture.environment(), processes: processes))
        let item = try #require(group.item("general.appWebCaches"))
        guard case .deleteContents(let folders) = item.defaultAction.operation else {
            Issue.record("Expected deleteContents")
            return
        }
        #expect(Set(folders.map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" })
                == ["Claude/Cache", "Claude/Code Cache", "Code/CachedData"])
        #expect(item.isRecommended)
        #expect(group.notes.contains { $0.contains("Slack") })

        let engine = CleanupEngine(env: fixture.environment())
        _ = await engine.clean([.init(item: item, action: item.defaultAction)])
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: fixture.url("\(support)/Claude/Cache/Cache_Data").path))
        #expect(!fm.fileExists(atPath: fixture.url("\(support)/Code/CachedData/abc").path))
        #expect(fm.fileExists(atPath: fixture.url("\(support)/Claude/IndexedDB/data.leveldb").path))
        #expect(fm.fileExists(atPath: fixture.url("\(support)/Code/User/settings.json").path))
        #expect(fm.fileExists(atPath: fixture.url("\(support)/SomeApp/Cache/important.db").path))
    }

    @Test func googleUpdateDownloadsWaitForTheUpdater() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Application Support/Google/GoogleUpdater/crx_cache/chrome.crx3", bytes: 80_000)
        try fixture.file("Library/Application Support/Google/GoogleUpdater/prefs.json", bytes: 100)

        let idle = GeneralScanner.scan(await fixture.context(fixture.environment()))
        #expect(idle.item("general.googleUpdates")?.blockedReason == nil)
        let busy = GeneralScanner.scan(await fixture.context(fixture.environment(), processes: ProcessSnapshot(executableNames: ["GoogleUpdater"])))
        #expect(busy.item("general.googleUpdates")?.blockedReason != nil)

        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/Google/GoogleUpdater/crx_cache/chrome.crx3"), mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/Google/GoogleUpdater/prefs.json"), mode: .delete, home: fixture.home) != nil)
    }

    // MARK: Helpers

    private func transcript(_ fixture: Fixture, folder: String, cwd: String) throws {
        let line = try JSONSerialization.data(withJSONObject: ["type": "user", "cwd": cwd, "sessionId": "s1"])
        let url = try fixture.file(".claude/projects/\(folder)/s1.jsonl", bytes: 0)
        try (Data("{\"type\":\"summary\"}\n".utf8) + line + Data("\n".utf8) + Data(repeating: 0x20, count: 20_000)).write(to: url)
    }

    private func workspace(_ fixture: Fixture, _ relative: String, uri: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["folder": uri])
        let url = try fixture.file("\(relative)/workspace.json", bytes: 0)
        try data.write(to: url)
        try fixture.file("\(relative)/state.vscdb", bytes: 15_000)
    }

    private func codexDatabase(_ fixture: Fixture, threads: [(cwd: String, rollout: String)]) throws {
        let path = fixture.url(".codex/state_5.sqlite").path
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, cwd TEXT NOT NULL)", nil, nil, nil)
        for (index, thread) in threads.enumerated() {
            let sql = "INSERT INTO threads VALUES ('t\(index)', '\(thread.rollout)', '\(thread.cwd)')"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        }
    }
}
