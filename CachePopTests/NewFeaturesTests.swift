import Foundation
import Testing
@testable import CachePop

extension Fixture {
    /// Back-dates a file or folder and everything in it, relative to the tests' fixed "now".
    func age(_ relative: String, days: Double) {
        let url = url(relative)
        let date = daysAgo(days)
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let child as URL in enumerator {
                try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: child.path)
            }
        }
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

// MARK: - Path safety for the new places

@Suite("Path safety: app data, backups, Android")
struct NewPathSafetyTests {
    @Test func appDataMayOnlyBeTrashedOneLevelDown() throws {
        let fixture = try Fixture()
        let app = try fixture.dir("Library/Application Support/com.gone.app")
        try fixture.file("Library/Application Support/com.gone.app/data.db")
        let prefs = try fixture.file("Library/Preferences/com.gone.app.plist")

        #expect(PathSafety.violation(for: app, mode: .trash, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: prefs, mode: .trash, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: app, mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/com.gone.app/data.db"), mode: .trash, home: fixture.home) != nil)
    }

    @Test func applesOwnDataAndPlainNamesAreRefused() throws {
        let fixture = try Fixture()
        let addressBook = try fixture.dir("Library/Application Support/AddressBook")
        let safari = try fixture.dir("Library/Containers/com.apple.Safari")
        let group = try fixture.dir("Library/Group Containers/group.com.apple.notes")
        for url in [addressBook, safari, group] {
            #expect(PathSafety.violation(for: url, mode: .trash, home: fixture.home) != nil)
        }
        // Mail and keychains stay protected however they're named.
        let keychain = try fixture.dir("Library/Keychains/com.example.keychain")
        #expect(PathSafety.violation(for: keychain, mode: .trash, home: fixture.home) != nil)
    }

    @Test func deviceBackupsAreTrashOnly() throws {
        let fixture = try Fixture()
        let backup = try fixture.dir("Library/Application Support/MobileSync/Backup/00008110-ABC")
        try fixture.file("Library/Application Support/MobileSync/Backup/00008110-ABC/Manifest.db")
        #expect(PathSafety.violation(for: backup, mode: .trash, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: backup, mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: fixture.url("Library/Application Support/MobileSync/Backup/00008110-ABC/Manifest.db"), mode: .trash, home: fixture.home) != nil)
    }

    @Test func androidAndRestoreFilesMayBeDeleted() throws {
        let fixture = try Fixture()
        let avd = try fixture.dir(".android/avd/Pixel.avd")
        let image = try fixture.dir("Library/Android/sdk/system-images/android-30/google_apis/x86_64")
        let ipsw = try fixture.file("Library/iTunes/iPhone Software Updates/iPhone_Restore.ipsw")
        for url in [avd, image, ipsw] {
            #expect(PathSafety.violation(for: url, mode: .delete, home: fixture.home) == nil)
        }
    }
}

// MARK: - Deleted apps

@Suite("Leftovers of deleted apps")
struct LeftoversScannerTests {
    private func makeMac() throws -> Fixture {
        let fixture = try Fixture()
        // A deleted app with data in three places.
        try fixture.file("Library/Application Support/com.gone.app/store.db", bytes: 1_500_000)
        try fixture.file("Library/Containers/com.gone.app/Data/cache", bytes: 200_000)
        try fixture.file("Library/Preferences/com.gone.app.plist", bytes: 2_000)
        // Tiny leftovers.
        try fixture.file("Library/Preferences/org.small.tool.plist", bytes: 3_000)
        // Installed app, and a helper from the same developer.
        try fixture.file("Library/Application Support/com.kept.app/data", bytes: 2_000_000)
        try fixture.file("Library/Preferences/com.kept.updater.plist", bytes: 2_000)
        // Still in use: changed recently.
        try fixture.file("Library/Application Support/com.recent.app/data", bytes: 2_000_000)
        // macOS's own, and plain names.
        try fixture.file("Library/Application Support/com.apple.sharedfilelist/x", bytes: 2_000_000)
        try fixture.file("Library/Application Support/AddressBook/x", bytes: 2_000_000)
        // Known to Launch Services somewhere else.
        try fixture.file("Library/Application Support/com.elsewhere.app/data", bytes: 2_000_000)

        for path in ["Library/Application Support/com.gone.app", "Library/Containers/com.gone.app",
                     "Library/Preferences/com.gone.app.plist", "Library/Preferences/org.small.tool.plist",
                     "Library/Application Support/com.kept.app", "Library/Preferences/com.kept.updater.plist",
                     "Library/Application Support/com.apple.sharedfilelist", "Library/Application Support/AddressBook",
                     "Library/Application Support/com.elsewhere.app"] {
            fixture.age(path, days: 120)
        }
        fixture.age("Library/Application Support/com.recent.app", days: 2)
        return fixture
    }

    private let catalog = FakeAppCatalog(installed: ["com.kept.app"], known: ["com.elsewhere.app"])

    @Test func offersOnlyDataOfAppsThatAreGone() async throws {
        let fixture = try makeMac()
        let env = fixture.environment(apps: catalog)
        let group = await LeftoversScanner.scan(await fixture.context(env))

        let gone = try #require(group.item("leftovers.com.gone.app"))
        #expect(!gone.isRecommended)
        #expect(gone.defaultAction.regeneration == .movedToTrash)
        #expect(Set(gone.defaultAction.operation.paths) == Set([
            canonical(fixture.url("Library/Application Support/com.gone.app")),
            canonical(fixture.url("Library/Containers/com.gone.app")),
            canonical(fixture.url("Library/Preferences/com.gone.app.plist"))
        ]))

        let small = try #require(group.item("leftovers.small"))
        #expect(small.defaultAction.operation.paths == [canonical(fixture.url("Library/Preferences/org.small.tool.plist"))])

        let offered = group.items.flatMap(\.defaultAction.operation.paths).joined(separator: "\n")
        for kept in ["com.kept", "com.recent", "com.apple", "AddressBook", "com.elsewhere"] {
            #expect(!offered.contains(kept), "\(kept) must not be offered")
        }
    }

    @Test func runningAppsCountAsInstalled() async throws {
        let fixture = try makeMac()
        let env = fixture.environment(apps: catalog)
        let context = ScanContext(env: env, processes: ProcessSnapshot(runningAppBundleIDs: ["com.gone.app"]), tools: .none)
        let group = await LeftoversScanner.scan(context)
        #expect(group.item("leftovers.com.gone.app") == nil)
    }

    @Test func cleaningMovesToTrashAndPutBackRestores() async throws {
        let fixture = try makeMac()
        let engine = CleanupEngine(env: fixture.environment(apps: catalog))
        let result = await engine.scan()
        let item = try #require(result.item("leftovers.com.gone.app"))

        let report = await engine.clean([CleanupEngine.Selection(item: item, action: item.defaultAction)])
        #expect(!fixture.exists("Library/Application Support/com.gone.app"))
        #expect(!fixture.exists("Library/Preferences/com.gone.app.plist"))
        #expect(report.trashedItems.count == 3)

        let restored = PutBack.restore(report.trashedItems)
        #expect(restored.failures.isEmpty)
        #expect(fixture.exists("Library/Application Support/com.gone.app/store.db"))
        #expect(fixture.exists("Library/Containers/com.gone.app/Data/cache"))
        #expect(fixture.exists("Library/Preferences/com.gone.app.plist"))
    }

    @Test func identifiersAreReadFromEachKindOfEntry() {
        #expect(LeftoversScanner.appIdentifier("com.Foo.Bar.plist", kind: .plist) == "com.foo.bar")
        #expect(LeftoversScanner.appIdentifier("com.foo.bar.savedState", kind: .savedState) == "com.foo.bar")
        #expect(LeftoversScanner.appIdentifier("ABCDE12345.com.foo.shared", kind: .groupContainer) == "com.foo.shared")
        #expect(LeftoversScanner.appIdentifier("group.com.foo.app", kind: .groupContainer) == "com.foo.app")
        #expect(LeftoversScanner.appIdentifier("com.apple.Notes", kind: .folder) == nil)
        #expect(LeftoversScanner.appIdentifier("Google", kind: .folder) == nil)
        #expect(LeftoversScanner.isOwned("com.google.keystone.agent", installed: ["com.google.chrome"]))
        #expect(!LeftoversScanner.isOwned("com.figma.desktop", installed: ["com.google.chrome"]))
        #expect(LeftoversScanner.displayName("com.figma.desktop") == "Figma")
        #expect(LeftoversScanner.displayName("com.github.atom") == "Atom")
    }
}

// MARK: - iPhone and iPad

@Suite("Device backups and restore files")
struct DeviceFilesScannerTests {
    @Test func backupsAreListedPerDeviceAndNeverPreselected() async throws {
        let fixture = try Fixture()
        let folder = "Library/Application Support/MobileSync/Backup/00008110-ABC"
        try fixture.file("\(folder)/Manifest.db", bytes: 400_000)
        let info: NSDictionary = ["Device Name": "Test iPhone", "Product Version": "18.1", "Last Backup Date": daysAgo(200)]
        info.write(to: fixture.url("\(folder)/Info.plist"), atomically: true)
        try fixture.file("Library/iTunes/iPhone Software Updates/iPhone_18.1_Restore.ipsw", bytes: 300_000)

        let group = DeviceFilesScanner.scan(await fixture.context(fixture.environment()))
        let backup = try #require(group.item("devices.backup.00008110-ABC"))
        #expect(backup.title == "Backup of Test iPhone")
        #expect(backup.detail?.contains("iOS 18.1") == true)
        #expect(!backup.isRecommended)
        #expect(backup.warning != nil)
        #expect(backup.defaultAction.regeneration == .movedToTrash)

        let updates = try #require(group.item("devices.updates"))
        #expect(updates.isRecommended)
        #expect(updates.defaultAction.regeneration == .redownloaded)
    }
}

// MARK: - Android

@Suite("Android emulators")
struct AndroidScannerTests {
    private func makeAndroid() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.file(".android/avd/Pixel_8.ini", bytes: 100)
        try fixture.file(".android/avd/Pixel_8.avd/userdata-qemu.img.qcow2", bytes: 300_000)
        try fixture.file(".android/avd/Pixel_8.avd/snapshots/default/ram.bin", bytes: 100_000)
        try "avd.ini.displayname=Pixel 8\nimage.sysdir.1=system-images/android-34/google_apis/arm64-v8a/\n"
            .write(to: fixture.url(".android/avd/Pixel_8.avd/config.ini"), atomically: true, encoding: .utf8)
        try fixture.file("Library/Android/sdk/system-images/android-34/google_apis/arm64-v8a/system.img", bytes: 200_000)
        try fixture.file("Library/Android/sdk/system-images/android-30/google_apis/x86_64/system.img", bytes: 250_000)
        return fixture
    }

    @Test func emulatorsCanBeWipedOrDeletedAndUnusedImagesAreOffered() async throws {
        let fixture = try makeAndroid()
        let group = AndroidScanner.scan(await fixture.context(fixture.environment()))

        let emulator = try #require(group.item("simulators.android.Pixel_8"))
        #expect(emulator.title == "Pixel 8")
        #expect(emulator.actions.map(\.id) == ["wipe", "delete"])
        #expect(!emulator.isRecommended)
        #expect(emulator.detail?.contains("Android 14") == true)

        #expect(group.item("simulators.androidImage.android-30/google_apis/x86_64") != nil)
        #expect(group.item("simulators.androidImage.android-34/google_apis/arm64-v8a") == nil)
    }

    @Test func aRunningEmulatorIsBlocked() async throws {
        let fixture = try makeAndroid()
        let processes = ProcessSnapshot(commandLines: ["/sdk/emulator/qemu/qemu-system-aarch64 -avd Pixel_8 -no-window"])
        let group = AndroidScanner.scan(await fixture.context(fixture.environment(), processes: processes))
        #expect(group.item("simulators.android.Pixel_8")?.isBlocked == true)
    }

    @Test func wipingKeepsTheEmulator() async throws {
        let fixture = try makeAndroid()
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("simulators.android.Pixel_8"))
        _ = await engine.clean([CleanupEngine.Selection(item: item, action: item.action(withID: "wipe"))])
        #expect(!fixture.exists(".android/avd/Pixel_8.avd/userdata-qemu.img.qcow2"))
        #expect(!fixture.exists(".android/avd/Pixel_8.avd/snapshots"))
        #expect(fixture.exists(".android/avd/Pixel_8.avd/config.ini"))
        #expect(fixture.exists(".android/avd/Pixel_8.ini"))
    }
}

// MARK: - Docker

@Suite("Docker")
struct DockerScannerTests {
    private func runner(running: Bool) -> FakeCommandRunner {
        FakeCommandRunner { command in
            guard command.executable == FakeSimctl.dockerURL else { return FakeSimctl().respond(to: command) }
            guard running else {
                return CommandOutput(status: 1, stdout: "", stderr: "Cannot connect to the Docker daemon")
            }
            if command.arguments.starts(with: ["system", "df"]) {
                return CommandOutput(status: 0, stdout: """
                {"Type":"Images","Reclaimable":"1.234GB (47%)"}
                {"Type":"Containers","Reclaimable":"10MB (100%)"}
                {"Type":"Local Volumes","Reclaimable":"2GB (100%)"}
                {"Type":"Build Cache","Reclaimable":"512.5MB"}
                """, stderr: "")
            }
            return CommandOutput(status: 0, stdout: "", stderr: "")
        }
    }

    @Test func offersBuildCacheAndUnusedImagesButNeverVolumes() async throws {
        let fixture = try Fixture()
        let env = fixture.environment(runner: runner(running: true), docker: true)
        let group = await DockerScanner.scan(await fixture.context(env))

        let cache = try #require(group.item("dev.docker.buildCache"))
        #expect(cache.sizeBytes == 512_500_000)
        #expect(!cache.isRecommended)
        let images = try #require(group.item("dev.docker.images"))
        #expect(images.sizeBytes == 1_234_000_000)
        #expect(group.items.count == 2)
        if case .command(let command) = images.defaultAction.operation {
            #expect(command.arguments == ["image", "prune", "--all", "--force"])
        } else {
            Issue.record("Expected a docker command")
        }
    }

    @Test func notRunningLeavesANote() async throws {
        let fixture = try Fixture()
        let env = fixture.environment(runner: runner(running: false), docker: true)
        let group = await DockerScanner.scan(await fixture.context(env))
        #expect(group.items.isEmpty)
        #expect(group.notes.first?.contains("isn't running") == true)
    }

    @Test func parsesDockerSizes() {
        #expect(DockerOutput.bytes(fromHumanSize: "1.234GB (47%)") == 1_234_000_000)
        #expect(DockerOutput.bytes(fromHumanSize: "512kB") == 512_000)
        #expect(DockerOutput.bytes(fromHumanSize: "0B") == 0)
    }
}

// MARK: - Never Clean

@Suite("Never Clean list")
struct NeverCleanTests {
    @Test func protectedCacheFoldersAreLeftOutOfScanAndClean() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.example.app/data", bytes: 600_000)
        try fixture.file("Library/Caches/com.keep.app/data", bytes: 400_000)
        let settings = CleanupSettings(neverClean: NeverCleanList(folders: [fixture.url("Library/Caches/com.keep.app")]))
        let engine = CleanupEngine(env: fixture.environment())

        let result = await engine.scan(settings: settings)
        let caches = try #require(result.item("general.appCaches"))
        #expect(caches.sizeBytes < fixture.size("Library/Caches/com.example.app") + 100_000)
        #expect(caches.note?.contains("Never Clean") == true)

        _ = await engine.clean([CleanupEngine.Selection(item: caches, action: caches.defaultAction)], neverClean: settings.neverClean)
        #expect(fixture.exists("Library/Caches/com.keep.app/data"))
        #expect(!fixture.exists("Library/Caches/com.example.app/data"))
    }

    @Test func aProtectedFolderInsideAClearedFolderSurvives() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/Xcode/DerivedData/Keep-abcdefghijklmnopqrstuvwxyz/Build/a.o", bytes: 300_000)
        try fixture.file("Library/Developer/Xcode/DerivedData/Other-abcdefghijklmnopqrstuvwxyz/Build/b.o", bytes: 300_000)
        let keep = fixture.url("Library/Developer/Xcode/DerivedData/Keep-abcdefghijklmnopqrstuvwxyz")
        let settings = CleanupSettings(neverClean: NeverCleanList(folders: [keep]))
        let engine = CleanupEngine(env: fixture.environment())

        let item = try #require(await engine.scan(settings: settings).item("xcode.derivedData"))
        _ = await engine.clean([CleanupEngine.Selection(item: item, action: item.defaultAction)], neverClean: settings.neverClean)
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/Keep-abcdefghijklmnopqrstuvwxyz/Build/a.o"))
        #expect(!fixture.exists("Library/Developer/Xcode/DerivedData/Other-abcdefghijklmnopqrstuvwxyz"))
    }

    @Test func skippedItemsAndFullyProtectedItemsAreHidden() async throws {
        let fixture = try Fixture()
        try fixture.file(".npm/_cacache/a", bytes: 200_000)
        try fixture.file("Library/Caches/pip/http/b", bytes: 200_000)
        let settings = CleanupSettings(neverClean: NeverCleanList(folders: [fixture.url(".npm")], itemIDs: ["dev.pip"]))

        let result = await CleanupEngine(env: fixture.environment()).scan(settings: settings)
        #expect(result.item("dev.npm") == nil)
        #expect(result.item("dev.pip") == nil)
        let notes = result.groups.first { $0.kind == .developerCaches }?.notes ?? []
        #expect(notes.contains { $0.contains("2 items are hidden") })
    }

    @Test func listedItemsAreSkippedEvenIfSelected() async throws {
        let fixture = try Fixture()
        try fixture.file(".npm/_cacache/a", bytes: 200_000)
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("dev.npm"))
        let report = await engine.clean([CleanupEngine.Selection(item: item, action: item.defaultAction)],
                                        neverClean: NeverCleanList(itemIDs: ["dev.npm"]))
        #expect(report.skipped.count == 1)
        #expect(fixture.exists(".npm/_cacache/a"))
    }
}

// MARK: - Settings the engine follows

@Suite("Cleanup settings")
struct CleanupSettingsTests {
    private func download(bytes: Int64) -> CleanupItem {
        CleanupItem(id: "general.download", group: .general, title: "X", explanation: "", sizeBytes: bytes,
                    actions: [CleanupAction(id: "delete", title: "Delete", operation: .delete([]),
                                            regeneration: .redownloaded, explanation: "")],
                    isRecommended: true)
    }

    @Test func redownloadThresholdIsConfigurable() {
        let item = download(bytes: 60_000_000)
        #expect(RecommendationPolicy.apply(to: item).isRecommended)
        let lower = RecommendationPolicy.apply(to: item, threshold: 50_000_000)
        #expect(!lower.isRecommended)
        #expect(lower.note?.contains("50 MB") == true)
        #expect(RecommendationPolicy.apply(to: download(bytes: 5_000_000_000), threshold: nil).isRecommended)
    }

    @Test func logAgeIsConfigurable() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Logs/ten-days.log", bytes: 20_000, modified: daysAgo(10))
        let env = fixture.environment()
        let week = ScanContext(env: env, processes: .empty, tools: .none, settings: CleanupSettings(logAge: 7 * 86_400))
        let month = ScanContext(env: env, processes: .empty, tools: .none, settings: CleanupSettings(logAge: 30 * 86_400))
        #expect(GeneralScanner.oldLogs(week) != nil)
        #expect(GeneralScanner.oldLogs(month) == nil)
        #expect(GeneralScanner.oldLogs(week)?.explanation.contains("a week") == true)
    }

    @MainActor
    @Test func appSettingsPersistAndMapToTheEngine() throws {
        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))

        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        settings.neverClean(folder: URL(fileURLWithPath: "/tmp/keep"))
        settings.redownloadThreshold = .never
        settings.logAgeDays = 30
        settings.appearance = .dark

        let reloaded = AppSettings(defaults: defaults, canChangeLoginItem: false)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.neverClean.count == 1)
        #expect(reloaded.cleanupSettings.largeDownloadThreshold == nil)
        #expect(reloaded.cleanupSettings.logAge == 30 * 86_400)
        #expect(reloaded.cleanupSettings.neverClean.folders.map(\.path) == ["/tmp/keep"])
    }

    @MainActor
    @Test func menuBarReadingsAreOffByDefaultAndSaved() throws {
        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))

        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        let readings: [ReferenceWritableKeyPath<AppSettings, Bool>] = [
            \.menuBarShowsCPUUsage, \.menuBarShowsMemoryUsage, \.menuBarShowsSSDUsage,
            \.menuBarShowsTemperature, \.menuBarShowsFanSpeed
        ]
        #expect(readings.allSatisfy { !settings[keyPath: $0] })
        #expect(settings.showsAnyMenuBarItem)  // CachePop's own item is on by default

        // Each reading is a menu bar item of its own, shown without CachePop's icon too.
        settings.showMenuBarItem = false
        #expect(!settings.showsAnyMenuBarItem)
        for enabled in readings {
            for key in readings { settings[keyPath: key] = key == enabled }
            #expect(settings.showsAnyMenuBarItem)

            let reloaded = AppSettings(defaults: defaults, canChangeLoginItem: false)
            #expect(!reloaded.showMenuBarItem)
            #expect(reloaded.showsMenuBarReadings)
            #expect(readings.allSatisfy { reloaded[keyPath: $0] == ($0 == enabled) })
        }

        // Tests can't change the login item, so CachePop's item is never locked on here.
        #expect(!settings.menuBarItemIsRequired)
    }
}

// MARK: - Put Back, history, alerts

@Suite("Put Back, history and alerts")
struct PutBackHistoryAlertTests {
    @Test func putBackRefusesToOverwrite() throws {
        let fixture = try Fixture()
        let original = try fixture.file("Downloads/Tool.dmg", bytes: 1_000)
        let trashed = fixture.userTrash.appendingPathComponent("Tool.dmg")
        try FileManager.default.copyItem(at: original, to: trashed)

        let outcome = PutBack.restore([TrashedItem(original: original, trashed: trashed)])
        #expect(outcome.restored.isEmpty)
        #expect(outcome.failures.count == 1)
    }

    @Test func trashMovesFromCleanUpCanBePutBack() async throws {
        let fixture = try Fixture()
        try fixture.file("Downloads/Installer.dmg", bytes: 70_000)
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("general.installers"))
        let report = await engine.clean([CleanupEngine.Selection(item: item, action: item.defaultAction)])
        #expect(!fixture.exists("Downloads/Installer.dmg"))
        #expect(PutBack.restore(report.trashedItems).restored.count == 1)
        #expect(fixture.exists("Downloads/Installer.dmg"))
    }

    @MainActor
    @Test func historyRecordsCleansAndTotals() {
        let history = CleanHistory(inMemory: true)
        let item = CleanupItem(id: "a", group: .general, title: "App caches", explanation: "", sizeBytes: 500,
                               actions: [CleanupAction(id: "delete", title: "Delete", operation: .delete([]), regeneration: .automatic, explanation: "")],
                               isRecommended: true)
        let cleaned = CleanupReport(entries: [CleanupItemReport(item: item, action: item.defaultAction, outcome: .removed(bytes: 500))],
                                    availableBefore: 1_000, availableAfter: 1_400)
        let skipped = CleanupReport(entries: [CleanupItemReport(item: item, action: item.defaultAction, outcome: .skipped(reason: "In use"))])

        history.add(cleaned)
        history.add(cleaned)
        history.add(skipped)
        #expect(history.records.count == 2)
        #expect(history.lifetimeFreedBytes == 800)
        #expect(history.lastClean?.titles == ["App caches"])
        history.clear()
        #expect(history.records.isEmpty)
    }

    @Test func lowSpaceAlertFiresOncePerDropAndAtMostDaily() {
        var rule = LowSpaceRule()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let gb: Int64 = 1_000_000_000
        func check(_ free: Int64, after seconds: TimeInterval) -> Bool {
            rule.evaluate(availableBytes: free * gb, thresholdBytes: 20 * gb, now: start.addingTimeInterval(seconds))
        }

        let results = [
            check(30, after: 0),        // plenty free
            check(15, after: 0),        // drops below: warn
            check(14, after: 600),      // still low: quiet
            check(40, after: 3_600),    // recovers
            check(15, after: 7_200),    // drops again within a day: quiet
            check(40, after: 90_000),   // recovers
            check(15, after: 90_600)    // a day later: warn again
        ]
        #expect(results == [false, true, false, false, false, false, true])
    }

    @Test func tenPercentThresholdFollowsDiskSize() {
        #expect(LowSpaceThreshold.tenPercent.bytes(totalBytes: 500_000_000_000) == 50_000_000_000)
        #expect(LowSpaceThreshold.gb20.bytes(totalBytes: 500_000_000_000) == 20_000_000_000)
    }
}

// MARK: - Large Files and Disk Usage

@Suite("Large Files filters and Disk Usage")
struct FiltersAndDiskUsageTests {
    @Test func fileKinds() {
        #expect(FileKind.of(URL(fileURLWithPath: "/a/clip.mov")) == .videos)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/clip.mp4")) == .videos)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/Tool.dmg")) == .diskImages)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/iPhone.ipsw")) == .diskImages)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/backup.zip")) == .archives)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/song.mp3")) == .audio)
        #expect(FileKind.of(URL(fileURLWithPath: "/a/thesis.pdf")) == .other)
    }

    @Test func ageFilter() {
        let now = Date()
        let old = FoundFile(url: URL(fileURLWithPath: "/a"), size: 1, modified: now.addingTimeInterval(-200 * 86_400))
        let new = FoundFile(url: URL(fileURLWithPath: "/b"), size: 1, modified: now.addingTimeInterval(-10 * 86_400))
        #expect(FileAge.sixMonths.includes(old, now: now))
        #expect(!FileAge.sixMonths.includes(new, now: now))
        #expect(FileAge.any.includes(new, now: now))
    }

    @Test func largeFileThresholdIsConfigurable() throws {
        let fixture = try Fixture()
        try fixture.file("Movies/clip.mov", bytes: 3_000_000)
        let low = LargeFilesScanner.scan(roots: [fixture.url("Movies")], largeThreshold: 2_000_000)
        let high = LargeFilesScanner.scan(roots: [fixture.url("Movies")], largeThreshold: 5_000_000)
        #expect(low.largeFiles.count == 1)
        #expect(high.largeFiles.isEmpty)
    }

    @Test func diskUsageMeasuresEachEntryAndSkipsSymlinks() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/a", bytes: 400_000)
        try fixture.file("Movies/clip.mov", bytes: 900_000)
        try fixture.symlink("Linked", to: fixture.url("Movies"))

        let entries = DiskUsageScanner.entries(in: fixture.home)
        #expect(Set(entries.map(\.name)) == ["Library", "Movies"])

        let collected = Collected()
        await DiskUsageScanner.measure(entries, width: 1) { await collected.add($0) }
        let sizes = await collected.byName
        #expect((sizes["Movies"] ?? 0) >= 900_000)
        #expect((sizes["Library"] ?? 0) >= 400_000)
    }

    private actor Collected {
        var byName: [String: Int64] = [:]
        func add(_ entry: UsageEntry) { byName[entry.name] = entry.bytes }
    }
}
