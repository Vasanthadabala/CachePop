import Foundation
import Testing
@testable import CachePop

@Suite("Android Studio cache cleanup")
struct AndroidStudioCacheTests {
    private let version = "Library/Caches/Google/AndroidStudio2026.1.4"
    private let chrome = "Library/Caches/Google/Chrome"

    @Test func chromeDoesNotHideStudioCachesAndSizesExcludeRecoveryData() async throws {
        let fixture = try Fixture()
        try fixture.file("\(version)/caches/data", bytes: 50_000)
        try fixture.file("\(version)/index/data", bytes: 70_000)
        try fixture.file("\(version)/tmp/data", bytes: 20_000)
        try fixture.file("\(version)/LocalHistory/changes", bytes: 500_000)
        try fixture.file("\(version)/plugins/plugin.jar", bytes: 400_000)
        try fixture.file("\(version)/unknown/data", bytes: 300_000)
        let preview = "Library/Caches/Google/AndroidStudioPreview2026.2"
        try fixture.file("\(preview)/caches/data", bytes: 30_000)
        try fixture.file("\(chrome)/Default/Cache/data", bytes: 60_000)
        let processes = ProcessSnapshot(runningAppBundleIDs: ["com.google.chrome"], runningAppNames: ["com.google.chrome": "Google Chrome"])
        let context = await fixture.context(fixture.environment(), processes: processes)

        let group = GeneralScanner.scan(context)
        let item = try #require(group.item("general.appCaches"))
        let expected = ["\(version)/caches", "\(version)/index", "\(version)/tmp", "\(preview)/caches"].map(fixture.url)
        #expect(Set(item.defaultAction.operation.paths) == Set(expected.map(canonical)))
        #expect(item.sizeBytes == DirectorySizer.size(ofAll: expected).bytes)
        #expect(item.detail?.contains("1 app") == true)
        #expect(item.detail?.contains("Android Studio") == true)
        #expect(item.explanation.contains("Local History"))
        #expect(!item.isBlocked)
        #expect(group.item("general.androidStudioCaches") == nil, "Studio belongs in the single App caches row.")
    }

    @Test func closedChromeIsCountedSeparatelyWithoutTheGoogleParent() async throws {
        let fixture = try Fixture()
        try fixture.file("\(version)/index/data")
        try fixture.file("\(version)/LocalHistory/keep")
        try fixture.file("\(chrome)/Default/Cache/data")
        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))
        let generic = try #require(group.item("general.appCaches"))
        #expect(Set(generic.defaultAction.operation.paths) == Set([canonical(fixture.url(chrome)), canonical(fixture.url("\(version)/index"))]))
        #expect(generic.detail?.contains("2 apps") == true)
        #expect(group.item("general.androidStudioCaches") == nil)
    }

    @Test func cleaningKeepsLocalHistoryPluginsSettingsAndOtherGoogleApps() async throws {
        let fixture = try Fixture()
        try fixture.file("\(version)/index/data")
        try fixture.file("\(version)/caches/data")
        try fixture.file("\(version)/LocalHistory/keep")
        try fixture.file("\(version)/plugins/keep.jar")
        try fixture.file("\(version)/unknown/keep")
        try fixture.file("Library/Application Support/Google/AndroidStudio2026.1.4/options/keep.xml")
        try fixture.file("\(chrome)/Default/Cache/keep")
        let chromeOpen = FakeProcessInspector(ProcessSnapshot(runningAppBundleIDs: ["com.google.chrome"]))
        let engine = CleanupEngine(env: fixture.environment(processes: chromeOpen))
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appCaches"))

        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(report.entries.first?.outcome == .removed(bytes: item.sizeBytes))
        #expect(fixture.children("\(version)/index").isEmpty)
        #expect(fixture.children("\(version)/caches").isEmpty)
        for kept in ["\(version)/LocalHistory/keep", "\(version)/plugins/keep.jar", "\(version)/unknown/keep",
                     "Library/Application Support/Google/AndroidStudio2026.1.4/options/keep.xml", "\(chrome)/Default/Cache/keep"] {
            #expect(fixture.exists(kept), "\(kept) must survive cache cleanup.")
        }
    }

    @Test(arguments: ["com.google.android.studio", "com.google.android.studio.preview"])
    func studioOpenedAfterScanningIsRecheckedBeforeCleaning(bundleID: String) async throws {
        let fixture = try Fixture()
        try fixture.file("\(version)/index/keep")
        try fixture.file("Library/Caches/com.example.closed/data")
        let processes = FakeProcessInspector()
        let env = fixture.environment(processes: processes)
        let engine = CleanupEngine(env: env)
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appCaches"))
        processes.set(ProcessSnapshot(runningAppBundleIDs: [bundleID]))

        let blockedScan = GeneralScanner.scan(await fixture.context(env, processes: await processes.snapshot()))
        #expect(blockedScan.item(item.id)?.defaultAction.operation.paths == [canonical(fixture.url("Library/Caches/com.example.closed"))])
        #expect(blockedScan.notes.contains { $0.contains("Android Studio") })
        let report = await engine.clean([.init(item: item, action: item.defaultAction)])
        guard case .failed(let message, let removed) = report.entries.first?.outcome else {
            Issue.record("Expected the running Studio cache to be skipped while closed apps are cleaned.")
            return
        }
        #expect(message.contains("Android Studio") && removed > 0)
        #expect(fixture.exists("\(version)/index/keep"))
        #expect(!fixture.exists("Library/Caches/com.example.closed/data"))
    }

    @Test func permanentDeletionCannotRemoveRecoveryDataOrWholeVendorDirectories() throws {
        let fixture = try Fixture()
        let history = try fixture.file("\(version)/LocalHistory/changes")
        let plugin = try fixture.file("\(version)/plugins/keep.jar")
        let unknown = try fixture.file("\(version)/unknown/keep")
        let cache = try fixture.file("\(version)/index/data")
        for protected in [fixture.url("Library/Caches/Google"), fixture.url(version), history, plugin, unknown] {
            #expect(PathSafety.violation(for: protected, mode: .delete, home: fixture.home) != nil)
        }
        #expect(PathSafety.violation(for: cache, mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: fixture.url(version), mode: .trash, home: fixture.home) == nil,
                "Explicit app uninstall can still move its whole data folder to Trash.")
    }

    @Test func symlinkedCachesAreSkippedAndAChangedLocationCannotDeleteAnotherAppsCache() async throws {
        let fixture = try Fixture()
        let cache = try fixture.dir("\(version)/index")
        try fixture.file("\(version)/index/data")
        let history = try fixture.dir("\(version)/LocalHistory")
        try fixture.file("\(version)/LocalHistory/keep")
        try fixture.symlink("\(version)/caches", to: history)
        let other = try fixture.dir(chrome)
        try fixture.file("\(chrome)/keep")
        let chromeOpen = FakeProcessInspector(ProcessSnapshot(runningAppBundleIDs: ["com.google.chrome"]))
        let engine = CleanupEngine(env: fixture.environment(processes: chromeOpen))
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appCaches"))
        #expect(item.defaultAction.operation.paths == [canonical(cache)])
        try FileManager.default.removeItem(at: cache)
        try fixture.symlink("\(version)/index", to: other)

        _ = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(fixture.exists("\(chrome)/keep"))
        #expect(fixture.exists("\(version)/LocalHistory/keep"))
    }
}
