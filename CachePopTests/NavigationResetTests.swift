import Foundation
import Testing
@testable import CachePop

@Suite("Section navigation resets", .serialized)
@MainActor
struct NavigationResetTests {
    @MainActor
    private final class Harness {
        let fixture: Fixture
        let suite = "CachePop.navigation.\(UUID().uuidString)"
        let model: AppModel

        init(control: any StartupControlling = DemoStartupControl()) throws {
            fixture = try Fixture()
            let defaults = try #require(UserDefaults(suiteName: suite))
            model = AppModel(environment: fixture.environment(),
                             settings: AppSettings(defaults: defaults, canChangeLoginItem: false),
                             history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                             fanController: InertFanController(), startupControl: control)
        }

        isolated deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    private func waitFor(_ predicate: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        let completed = await predicate()
        try #require(completed, "The fixture operation did not finish.")
    }

    @Test func cleanupReviewResetsOnlyWhenTheSectionChanges() async throws {
        let h = try Harness()
        try h.fixture.file("Library/Caches/com.example.navigation/data", bytes: 1024)
        let model = h.model
        model.cleanUp.apply(await CleanupEngine(env: h.fixture.environment()).scan())
        try #require(!model.cleanUp.result.allItems.isEmpty)
        let selection = model.cleanUp.selectedIDs
        model.cleanUp.collapsedGroups = Set(CleanupGroupKind.allCases)
        model.cleanUp.isConfirming = true
        model.isShowingHistory = true
        model.section = .cleanUp
        #expect(model.cleanUp.phase == .review)
        #expect(model.cleanUp.selectedIDs == selection)

        model.section = .largeFiles
        #expect(model.cleanUp.phase == .start)
        #expect(model.cleanUp.result.allItems.isEmpty)
        #expect(model.cleanUp.finishedGroups.isEmpty)
        #expect(model.cleanUp.selectedIDs.isEmpty)
        #expect(model.cleanUp.chosenActionIDs.isEmpty)
        #expect(model.cleanUp.collapsedGroups.isEmpty)
        #expect(!model.cleanUp.isConfirming && !model.isShowingHistory)
        model.section = .cleanUp
        #expect(model.cleanUp.phase == .start)
    }

    @Test func everyScannedSectionDropsItsResultsAndTemporaryFilters() async throws {
        let h = try Harness(control: DemoStartupControl(apps: [OpenAtLoginApp(name: "Fixture", path: "/fixture/app")]))
        let model = h.model
        try h.fixture.file("Downloads/movie.mov", bytes: 2_097_152)
        model.settings.largeFileMinimumMB = 1
        model.section = .largeFiles
        model.largeFiles.scan()
        try await waitFor { model.largeFiles.phase == .results }
        try #require(!model.largeFiles.result.largeFiles.isEmpty)
        model.largeFiles.selectedIDs = Set(model.largeFiles.result.largeFiles.map(\.id))
        model.largeFiles.kindFilter = .videos
        model.largeFiles.ageFilter = .threeMonths
        model.largeFiles.tab = .duplicates
        model.largeFiles.isConfirming = true
        model.section = .photos
        #expect(model.largeFiles.phase == .start && model.largeFiles.result.largeFiles.isEmpty)
        #expect(model.largeFiles.selectedIDs.isEmpty && !model.largeFiles.isConfirming)
        #expect(model.largeFiles.kindFilter == nil && model.largeFiles.ageFilter == .any)
        #expect(model.largeFiles.tab == .large)

        model.photos.scan()
        try await waitFor { model.photos.phase == .results }
        model.photos.selectedIDs = ["old photo"]
        model.photos.tab = .dark
        model.photos.isConfirming = true
        model.section = .diskUsage
        #expect(model.photos.phase == .start && model.photos.result.allPhotos.isEmpty)
        #expect(model.photos.selectedIDs.isEmpty && !model.photos.isConfirming)
        #expect(model.photos.tab == .similar && model.photos.scope == .folders)
        #expect(model.photos.measured == 0 && model.photos.total == 0)

        model.diskUsage.start()
        try await waitFor { model.diskUsage.phase == .ready }
        try #require(!model.diskUsage.listings.isEmpty)
        model.section = .apps
        #expect(model.diskUsage.phase == .start && model.diskUsage.listings.isEmpty)
        #expect(model.diskUsage.path.isEmpty && model.diskUsage.measuringFolders.isEmpty)

        model.apps.scan()
        try await waitFor { model.apps.hasScanned }
        model.apps.filter = .unused
        model.apps.sortOrder = .name
        model.apps.errorMessage = "Old message"
        model.apps.selectedRelatedFileIDs = ["old file"]
        model.section = .loginItems
        #expect(!model.apps.hasScanned && !model.apps.isScanning)
        #expect(model.apps.applications.isEmpty && model.apps.relatedFiles.isEmpty)
        #expect(model.apps.selectedAppID == nil && model.apps.selectedRelatedFileIDs.isEmpty)
        #expect(model.apps.filter == .all && model.apps.sortOrder == .size)
        #expect(model.apps.errorMessage == nil)

        model.loginItems.scan()
        try await waitFor { model.loginItems.hasScanned }
        try #require(!model.loginItems.items.isEmpty)
        model.loginItems.message = "Old message"
        model.section = .cleanUp
        #expect(!model.loginItems.hasScanned && model.loginItems.items.isEmpty)
        #expect(model.loginItems.appsAccess == .unknown && model.loginItems.message == nil)
        #expect(model.settings.largeFileMinimumMB == 1)
    }

    @Test(arguments: [AppSection.cleanUp, .largeFiles, .photos, .diskUsage, .apps, .loginItems])
    func leavingAnInFlightScanPreventsLateResults(_ section: AppSection) async throws {
        let h = try Harness()
        let model = h.model
        model.section = section
        model.rescanCurrentSection()
        model.section = .settings
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.cleanUp.phase == .start && model.cleanUp.finishedGroups.isEmpty)
        #expect(model.largeFiles.phase == .start && model.largeFiles.currentPath.isEmpty)
        #expect(model.photos.phase == .start && model.photos.measured == 0)
        #expect(model.diskUsage.phase == .start && model.diskUsage.listings.isEmpty)
        #expect(!model.apps.isScanning && !model.apps.hasScanned)
        #expect(!model.loginItems.isScanning && !model.loginItems.hasScanned)
    }

    @Test func aCleanFinishesAndRecordsHistoryBeforeTheDeferredReset() async throws {
        let h = try Harness()
        try h.fixture.file("Downloads/Installer.dmg", bytes: 1024)
        let model = h.model
        let scanned = await CleanupEngine(env: h.fixture.environment()).scan()
        let installer = try #require(scanned.item("general.installers"))
        model.cleanUp.apply(scanned)
        for item in scanned.allItems { model.cleanUp.setSelected(item, false) }
        model.cleanUp.setSelected(installer, true)
        model.cleanUp.confirmClean()
        try #require(model.cleanUp.phase == .cleaning)
        model.section = .largeFiles
        // Returning while the original operation runs must not allow a second clean.
        model.section = .cleanUp
        #expect(model.cleanUp.phase == .cleaning)
        try await waitFor { model.cleanUp.phase == .start }
        #expect(model.history.records.count == 1)
        #expect(!h.fixture.exists("Downloads/Installer.dmg"))
        #expect(model.cleanUp.report == nil && model.cleanUp.result.allItems.isEmpty)
    }

    @Test func puttingFilesBackFinishesBeforeLeavingReleasesTheReport() async throws {
        let h = try Harness()
        try h.fixture.file("Downloads/Installer.dmg", bytes: 1024)
        let engine = CleanupEngine(env: h.fixture.environment())
        let item = try #require(await engine.scan().item("general.installers"))
        let report = await engine.clean([CleanupEngine.Selection(item: item, action: item.defaultAction)])
        let model = h.model
        model.cleanUp.finishCleaning(report)
        model.cleanUp.putBack()
        try #require(model.cleanUp.isPuttingBack)
        model.section = .photos
        try await waitFor { !model.cleanUp.isPuttingBack }
        #expect(h.fixture.exists("Downloads/Installer.dmg"))
        #expect(model.cleanUp.phase == .start && model.cleanUp.report == nil)
        #expect(model.cleanUp.putBackMessage == nil)
        #expect(model.history.records.count == 1)
    }

    actor HeldStartupControl: StartupControlling {
        var pendingRead: CheckedContinuation<[OpenAtLoginApp], any Error>?
        var pendingChange: CheckedContinuation<Void, Never>?
        var apps: [OpenAtLoginApp] = []
        var holdReads = false
        func configure(apps: [OpenAtLoginApp] = [], holdReads: Bool = false) {
            self.apps = apps
            self.holdReads = holdReads
        }
        func overrides() async -> LaunchOverrides { LaunchOverrides() }
        func openAtLoginApps() async throws -> [OpenAtLoginApp] {
            if holdReads {
                return try await withCheckedThrowingContinuation { pendingRead = $0 }
            }
            return apps
        }
        func set(_ item: LoginItem, on: Bool) async throws {
            await withCheckedContinuation { pendingChange = $0 }
            if !on { apps.removeAll { $0.path == item.path } }
        }
        func finishRead() { pendingRead?.resume(returning: apps); pendingRead = nil }
        func finishChange() { pendingChange?.resume(); pendingChange = nil }
    }

    @Test func aLateSystemReplyCannotRestoreAnAbandonedLoginList() async throws {
        let control = HeldStartupControl()
        await control.configure(apps: [OpenAtLoginApp(name: "Stale", path: "/fixture/stale")], holdReads: true)
        let h = try Harness(control: control)
        h.model.section = .loginItems
        h.model.loginItems.scan()
        try await waitFor { await control.pendingRead != nil }
        h.model.section = .cleanUp
        await control.finishRead()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!h.model.loginItems.hasScanned && h.model.loginItems.items.isEmpty)
        #expect(!h.model.loginItems.isScanning)
    }

    @Test func aLoginChangeFinishesAndKeepsTheSavedOffStateAfterNavigation() async throws {
        let control = HeldStartupControl()
        let h = try Harness(control: control)
        let app = try h.fixture.dir("Applications/Fixture.app")
        await control.configure(apps: [OpenAtLoginApp(name: "Fixture", path: app.path)])
        let model = h.model
        model.section = .loginItems
        model.loginItems.scan()
        try await waitFor { model.loginItems.hasScanned }
        let item = try #require(model.loginItems.apps.first)
        model.loginItems.set(item, on: false)
        try await waitFor { await control.pendingChange != nil }
        model.section = .cleanUp
        #expect(!model.loginItems.busyIDs.isEmpty)
        await control.finishChange()
        try await waitFor { model.loginItems.busyIDs.isEmpty }
        #expect(model.settings.loginAppsTurnedOff == [app.path])
        #expect(!model.loginItems.hasScanned && model.loginItems.items.isEmpty)
        model.section = .loginItems
        model.loginItems.scan()
        try await waitFor { model.loginItems.hasScanned }
        #expect(model.loginItems.apps.first?.isOn == false)
    }

    @Test func navigationResetsMonitorAndSettingsPresentationWhileKeepingSavedState() throws {
        let h = try Harness()
        let model = h.model
        model.section = .systemMonitor
        model.monitor.startRecording()
        defer { model.monitor.stopRecording() }
        model.monitor.apply(SystemSnapshot(temperatures: TemperatureSample(chip: 42)))
        model.monitor.processSort = .memory
        model.monitor.scrollToProcesses = true
        model.monitor.processToQuit = ProcessUsage(pid: 123, name: "Fixture", cpuPercent: 1, memoryBytes: 1024)
        model.section = .settings
        #expect(model.monitor.processSort == .cpu && !model.monitor.scrollToProcesses)
        #expect(model.monitor.processToQuit == nil)
        #expect(model.monitor.isRecording && model.monitor.logRecords.count == 1)
        #expect(model.monitor.snapshot?.temperatures.chip == 42)
        model.settings.selectedTab = .menuBar
        model.settings.logAgeDays = 14
        model.section = .cleanUp
        #expect(model.settings.selectedTab == .general)
        #expect(model.settings.logAgeDays == 14)
    }
}
