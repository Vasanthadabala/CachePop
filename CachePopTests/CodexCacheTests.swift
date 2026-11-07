import Foundation
import Testing
@testable import CachePop

@Suite("Codex caches")
struct CodexCacheTests {
    /// ~/.codex as the Codex app and CLI leave it: caches next to the user's own data.
    private func codexHome() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.file(".codex/cache/remote_plugin_catalog/catalog.json", bytes: 60_000)
        try fixture.file(".codex/.tmp/plugins/bundle.tar", bytes: 40_000)
        try fixture.file(".codex/plugins/cache/openai-bundled/plugin.zip", bytes: 20_000)
        // The user's data: never offered, never removed.
        try fixture.file(".codex/sessions/2026/09/30/rollout-1.jsonl.zst", bytes: 500_000)
        try fixture.file(".codex/thread_history_1.sqlite", bytes: 400_000)
        try fixture.file(".codex/generated_images/image.png", bytes: 300_000)
        try fixture.file(".codex/plugins/installed-plugin/manifest.json", bytes: 50_000)
        return fixture
    }

    @Test func offersOnlyTheCaches() async throws {
        let fixture = try codexHome()
        let group = await DeveloperCacheScanner.scan(await fixture.context(fixture.environment()))
        let item = try #require(group.item("dev.codex"))

        #expect(item.sizeBytes >= 120_000 && item.sizeBytes < 200_000, "only cache, .tmp and plugins/cache count")
        #expect(item.isRecommended)
        guard case .deleteContents(let urls) = item.defaultAction.operation else {
            Issue.record("Expected deleteContents")
            return
        }
        #expect(Set(urls.map(\.lastPathComponent)) == ["cache", ".tmp"])
        #expect(urls.count == 3)
    }

    @Test func blockedWhileTheAppOrCLIRuns() async throws {
        let fixture = try codexHome()
        for processes in [ProcessSnapshot(executableNames: ["codex"]), ProcessSnapshot(runningAppBundleIDs: ["com.openai.codex"])] {
            let group = await DeveloperCacheScanner.scan(await fixture.context(fixture.environment(), processes: processes))
            #expect(group.item("dev.codex")?.blockedReason == "Codex is open. Quit it to clean this.")
        }
    }

    @Test func cleaningEmptiesCachesAndKeepsConversations() async throws {
        let fixture = try codexHome()
        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let item = try #require(result.allItems.first { $0.id == "dev.codex" })

        let report = await engine.clean([.init(item: item, action: item.defaultAction)])
        guard case .removed = report.entries.first?.outcome else {
            Issue.record("Expected removed, got \(String(describing: report.entries.first?.outcome))")
            return
        }
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: fixture.url(".codex/cache/remote_plugin_catalog").path))
        #expect(!fm.fileExists(atPath: fixture.url(".codex/.tmp/plugins").path))
        #expect(!fm.fileExists(atPath: fixture.url(".codex/plugins/cache/openai-bundled").path))
        #expect(fm.fileExists(atPath: fixture.url(".codex/cache").path), "the folders themselves stay")
        #expect(fm.fileExists(atPath: fixture.url(".codex/sessions/2026/09/30/rollout-1.jsonl.zst").path))
        #expect(fm.fileExists(atPath: fixture.url(".codex/thread_history_1.sqlite").path))
        #expect(fm.fileExists(atPath: fixture.url(".codex/generated_images/image.png").path))
        #expect(fm.fileExists(atPath: fixture.url(".codex/plugins/installed-plugin/manifest.json").path))
    }

    @Test func safetyAllowsCodexCachesOnly() throws {
        let fixture = try codexHome()
        #expect(PathSafety.violation(for: fixture.url(".codex/cache/remote_plugin_catalog"), mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: fixture.url(".codex/sessions/2026"), mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: fixture.url(".codex/thread_history_1.sqlite"), mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: fixture.url(".codex/generated_images/image.png"), mode: .trash, home: fixture.home) != nil)
    }
}
