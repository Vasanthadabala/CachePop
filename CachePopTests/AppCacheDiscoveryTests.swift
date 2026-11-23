import Foundation
import Testing
@testable import CachePop

@Suite("Safe cache discovery across apps")
struct AppCacheDiscoveryTests {
    @Test func ideCachesShareAppCachesWhileRecoveryPluginsAndModelsStay() async throws {
        let fixture = try Fixture()
        let idea = "Library/Caches/JetBrains/IntelliJIdea2026.3"
        let python = "Library/Caches/JetBrains/PyCharmCE2026.2"
        for path in ["\(idea)/index/data", "\(idea)/caches/data", "\(python)/tmp/data"] { try fixture.file(path) }
        for path in ["\(idea)/LocalHistory/changes", "\(idea)/plugins/plugin.jar", "\(idea)/full-line/model.bin", "Library/Caches/JetBrains/Daemon/remDev/state"] {
            try fixture.file(path)
        }
        let engine = CleanupEngine(env: fixture.environment())
        let scan = await engine.scan()
        let caches = try #require(scan.item("general.appCaches"))
        #expect(scan.item("dev.jetbrains") == nil)
        #expect(Set(caches.defaultAction.operation.paths) == Set(["\(idea)/index", "\(idea)/caches", "\(python)/tmp"].map { canonical(fixture.url($0)) }))
        #expect(caches.detail?.contains("2 apps") == true)
        _ = await engine.clean([.init(item: caches, action: caches.defaultAction)])
        #expect(!fixture.exists("\(idea)/index/data"))
        for path in ["\(idea)/LocalHistory/changes", "\(idea)/plugins/plugin.jar", "\(idea)/full-line/model.bin", "Library/Caches/JetBrains/Daemon/remDev/state"] {
            #expect(fixture.exists(path))
            #expect(PathSafety.violation(for: fixture.url(path), mode: .delete, home: fixture.home) != nil)
        }
    }

    @Test func oneOpenIDEKeepsItsCachesWithoutHidingAnotherIDE() async throws {
        let fixture = try Fixture()
        let idea = "Library/Caches/JetBrains/IntelliJIdea2026.3/index"
        let python = "Library/Caches/JetBrains/PyCharmCE2026.2/caches"
        try fixture.file("\(idea)/data")
        try fixture.file("\(python)/data")
        let processes = ProcessSnapshot(runningAppBundleIDs: ["com.jetbrains.intellij"])
        let group = GeneralScanner.scan(await fixture.context(fixture.environment(), processes: processes))
        let item = try #require(group.item("general.appCaches"))
        #expect(item.defaultAction.operation.paths == [canonical(fixture.url(python))])
        #expect(group.notes.contains { $0.contains("com.jetbrains.intellij") })
    }

    @Test func oldNeverCleanPreferenceStillKeepsIDEFiles() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/JetBrains/IntelliJIdea2026.3/index/keep")
        try fixture.file("Library/Caches/com.example.closed/data")
        let settings = CleanupSettings(neverClean: NeverCleanList(itemIDs: ["dev.jetbrains"]))
        let scan = await CleanupEngine(env: fixture.environment()).scan(settings: settings)
        let item = try #require(scan.item("general.appCaches"))
        #expect(item.defaultAction.operation.paths == [canonical(fixture.url("Library/Caches/com.example.closed"))])
    }

    @Test func sandboxScanCleansOnlyInstalledThirdPartyCacheContents() async throws {
        let fixture = try Fixture()
        let base = "Library/Containers/com.example.reader/Data"
        try fixture.file("\(base)/Library/Caches/images/data")
        for path in ["\(base)/Documents/offline.pdf", "\(base)/Library/Preferences/settings.plist", "\(base)/Library/Application Support/library.db",
                     "Library/Containers/com.apple.example/Data/Library/Caches/keep", "Library/Containers/com.unknown.app/Data/Library/Caches/keep"] {
            try fixture.file(path)
        }
        let catalog = FakeAppCatalog(installed: ["com.example.reader", "com.apple.example"])
        let engine = CleanupEngine(env: fixture.environment(apps: catalog))
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appCaches"))
        #expect(item.defaultAction.operation.paths == [canonical(fixture.url("\(base)/Library/Caches"))])
        _ = await engine.clean([.init(item: item, action: item.defaultAction)])
        #expect(!fixture.exists("\(base)/Library/Caches/images/data"))
        for path in ["\(base)/Documents/offline.pdf", "\(base)/Library/Preferences/settings.plist", "\(base)/Library/Application Support/library.db",
                     "Library/Containers/com.apple.example/Data/Library/Caches/keep", "Library/Containers/com.unknown.app/Data/Library/Caches/keep"] {
            #expect(fixture.exists(path))
            #expect(PathSafety.violation(for: fixture.url(path), mode: .delete, home: fixture.home) != nil || path.contains("com.unknown.app"))
        }
        #expect(PathSafety.violation(for: fixture.url("\(base)/Library/Caches"), mode: .delete, home: fixture.home) != nil)
    }

    @Test func openingASandboxedAppAfterScanPreservesItsCache() async throws {
        let fixture = try Fixture()
        let base = "Library/Containers/eu.example.reader.widget/Data/Library/Caches"
        try fixture.file("\(base)/keep")
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes, apps: FakeAppCatalog(installed: ["eu.example.reader"])))
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appCaches"))
        processes.set(ProcessSnapshot(runningAppBundleIDs: ["eu.example.reader"]))
        _ = await engine.clean([.init(item: item, action: item.defaultAction)])
        #expect(fixture.exists("\(base)/keep"))
    }

    @Test func nestedBrowserProfilesAndPersistentGPUCachesKeepOfflineAndLoginData() async throws {
        let fixture = try Fixture()
        let chrome = "Library/Application Support/Google/Chrome"
        try fixture.file("\(chrome)/Local State")
        try fixture.file("\(chrome)/Default/Preferences")
        try fixture.file("\(chrome)/Default/Cache/data")
        try fixture.file("\(chrome)/Default/GPUPersistentCache/data")
        try fixture.file("\(chrome)/Profile 1/Preferences")
        try fixture.file("\(chrome)/Profile 1/Code Cache/data")
        let codex = "Library/Application Support/Codex"
        try fixture.file("\(codex)/Local State")
        try fixture.file("\(codex)/GPUPersistentCache/data")
        for path in ["\(chrome)/Default/IndexedDB/offline.db", "\(chrome)/Default/Service Worker/CacheStorage/offline", "\(chrome)/Default/Network/Cookies",
                     "\(chrome)/Default/History", "\(codex)/sessions/chat.db", "Library/Application Support/Unknown/Default/Cache/keep.db"] {
            try fixture.file(path)
        }
        let engine = CleanupEngine(env: fixture.environment())
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appWebCaches"))
        #expect(Set(item.defaultAction.operation.paths) == Set(["\(chrome)/Default/Cache", "\(chrome)/Default/GPUPersistentCache", "\(chrome)/Profile 1/Code Cache", "\(codex)/GPUPersistentCache"].map { canonical(fixture.url($0)) }))
        _ = await engine.clean([.init(item: item, action: item.defaultAction)])
        #expect(!fixture.exists("\(chrome)/Default/Cache/data"))
        #expect(!fixture.exists("\(codex)/GPUPersistentCache/data"))
        for path in ["\(chrome)/Default/IndexedDB/offline.db", "\(chrome)/Default/Service Worker/CacheStorage/offline", "\(chrome)/Default/Network/Cookies", "\(chrome)/Default/History", "\(codex)/sessions/chat.db", "Library/Application Support/Unknown/Default/Cache/keep.db"] {
            #expect(fixture.exists(path))
            // History/cookies remain separately cleanable by the explicit browser-data rows;
            // the cache action above must never include them.
            if !path.hasSuffix("/History"), !path.hasSuffix("/Cookies") {
                #expect(PathSafety.violation(for: fixture.url(path), mode: .delete, home: fixture.home) != nil)
            }
        }
    }

    @Test func profileCachesUseTheBrowserOwnerAtCleanupTime() async throws {
        let fixture = try Fixture()
        let chrome = "Library/Application Support/Google/Chrome"
        try fixture.file("\(chrome)/Local State")
        try fixture.file("\(chrome)/Default/Preferences")
        try fixture.file("\(chrome)/Default/Code Cache/keep")
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes))
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appWebCaches"))
        processes.set(ProcessSnapshot(runningAppBundleIDs: ["com.google.chrome"]))
        _ = await engine.clean([.init(item: item, action: item.defaultAction)])
        #expect(fixture.exists("\(chrome)/Default/Code Cache/keep"))
    }

    @Test func changedProfileIdentityKeepsItsCacheAfterScanning() async throws {
        let fixture = try Fixture()
        let chrome = "Library/Application Support/Google/Chrome"
        try fixture.file("\(chrome)/Local State")
        let preferences = try fixture.file("\(chrome)/Default/Preferences")
        try fixture.file("\(chrome)/Default/Cache/keep")
        let engine = CleanupEngine(env: fixture.environment())
        let scan = await engine.scan()
        let item = try #require(scan.item("general.appWebCaches"))
        try FileManager.default.removeItem(at: preferences)

        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(fixture.exists("\(chrome)/Default/Cache/keep"))
        guard case .failed(let reason, let removed) = report.entries.first?.outcome else {
            Issue.record("A profile that no longer identifies itself must not be cleaned.")
            return
        }
        #expect(reason.contains("profile changed") && removed == 0)
    }
}
