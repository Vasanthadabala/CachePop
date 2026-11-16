import AppKit
import Foundation
import Darwin
import Testing
@testable import CachePop

@Suite("Resource lifetimes", .serialized)
struct ResourceRegressionTests {
    actor Sampler: SystemSampling {
        private(set) var readings = 0
        private(set) var detailed: [Bool] = []
        func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot {
            readings += 1
            detailed.append(includeDetails)
            return SystemSnapshot()
        }
    }

    @MainActor
    @Test func monitorIsReleasedWhileItsPollingTaskSleeps() async throws {
        let sampler = Sampler()
        var monitor: SystemMonitorViewModel? = SystemMonitorViewModel(sampler: sampler)
        weak let released = monitor
        // Also clean up when running this regression against the leaking implementation.
        defer { released?.end(SystemMonitorViewModel.menuBarClient) }
        monitor?.begin(SystemMonitorViewModel.menuBarClient)
        for _ in 0..<100 where monitor?.snapshot == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(monitor?.snapshot != nil)
        monitor = nil
        for _ in 0..<20 where released != nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(released == nil, "The polling loop must not own the monitor between readings.")
    }

    @MainActor
    @Test func menuBarPollingSkipsDetailedIOAndRecordingRequestsIt() async throws {
        let sampler = Sampler()
        let monitor = SystemMonitorViewModel(sampler: sampler)
        monitor.begin(SystemMonitorViewModel.menuBarClient)
        defer { monitor.stopRecording(); monitor.end(SystemMonitorViewModel.menuBarClient) }
        for _ in 0..<100 where monitor.snapshot == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await sampler.detailed == [false])
        monitor.startRecording()
        for _ in 0..<100 {
            if await sampler.detailed.contains(true) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await sampler.detailed.contains(true))
    }

    @Test func commandReaderDrainsBothPipesWithoutDeadlocking() async throws {
        let command = ToolCommand(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [
            "-c", "i=0; while [ $i -lt 4000 ]; do printf 'stdout-line\\n'; printf 'stderr-line\\n' >&2; i=$((i+1)); done"
        ])
        let result = try await ProcessCommandRunner().run(command, timeout: 10)
        #expect(result.succeeded)
        #expect(result.stdout.split(separator: "\n").count == 4000)
        #expect(result.stderr.split(separator: "\n").count == 4000)
    }

    @Test func noisyCommandCannotGrowOutputWithoutBound() async throws {
        let command = ToolCommand(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: ["test"])
        await #expect(throws: CommandError.outputLimitExceeded) {
            _ = try await ProcessCommandRunner(maximumOutputBytes: 8192).run(command, timeout: 5)
        }
    }

    @Test func timeoutReapsAChildThatIgnoresSIGTERM() async throws {
        let fixture = try Fixture()
        let file = fixture.home.appendingPathComponent("pid")
        let script = #"trap '' TERM; printf '%s' "$$" > "$CACHEPOP_TEST_PID_FILE"; exec /bin/sleep 30"#
        let command = ToolCommand(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
                                  environment: ["CACHEPOP_TEST_PID_FILE": file.path])
        await #expect(throws: CommandError.timedOut) {
            _ = try await ProcessCommandRunner().run(command, timeout: 0.2)
        }
        let pid = try #require(Int32(String(contentsOf: file, encoding: .utf8)))
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(kill(pid, 0) != 0 && errno == ESRCH)
    }

    @MainActor
    @Test func cancelledFileScanCannotPublishAnOldProgressCallback() async throws {
        let fixture = try Fixture()
        let model = LargeFilesViewModel(home: fixture.home)
        model.scan()
        model.cancelScan()
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.phase == .start)
        #expect(model.currentPath.isEmpty)
    }

    @Test func directoryPermissionProbeHandlesEmptyAndNonDirectoryPaths() throws {
        let fixture = try Fixture()
        #expect(FullDiskAccessProbe.canListDirectory(fixture.home.path))
        let file = try fixture.file("not-a-folder", bytes: 1)
        #expect(!FullDiskAccessProbe.canListDirectory(file.path))
    }

    @Test func replyGateResumesOnlyOnceAfterItsTimeout() async throws {
        enum Timeout: Error { case expired }
        await #expect(throws: Timeout.expired) {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce<Int>(continuation)
                let timer = Task {
                    try? await Task.sleep(for: .milliseconds(10))
                    #expect(once.resume(with: .failure(Timeout.expired)))
                    #expect(!once.resume(with: .success(42)))
                }
                once.installTimeout(timer)
            }
        }
    }

    @MainActor
    @Test func putBackRunsAsynchronouslyAndCannotOverlapARescan() async throws {
        let fixture = try Fixture()
        try fixture.file("Downloads/Installer.dmg", bytes: 1024)
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("general.installers"))
        let report = await engine.clean([CleanupEngine.Selection(item: item, action: item.defaultAction)])
        let model = CleanUpViewModel(engine: engine)
        model.finishCleaning(report)
        #expect(!fixture.exists("Downloads/Installer.dmg"))
        model.putBack()
        #expect(model.isPuttingBack)
        #expect(!model.canPutBack)
        model.putBack()
        model.scan()
        model.startOver()
        #expect(model.phase == .done)
        for _ in 0..<200 where model.isPuttingBack { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isPuttingBack)
        #expect(fixture.exists("Downloads/Installer.dmg"))
        #expect(model.putBackMessage == "Put back \(report.trashedItems.count) item from the Trash.")
    }

    @MainActor
    @Test func backgroundTrimmingKeepsReviewStateAndRecording() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.example.fixture/data", bytes: 1024)
        let suite = "CachePop.memory.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: suite)), canChangeLoginItem: false)
        let model = AppModel(environment: fixture.environment(), settings: settings,
                             history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                             fanController: InertFanController(), startupControl: DemoStartupControl())
        model.cleanUp.apply(await CleanupEngine(env: fixture.environment()).scan())
        let selection = model.cleanUp.selectedIDs
        #expect(!selection.isEmpty)
        model.monitor.startRecording()
        defer { model.monitor.stopRecording() }
        model.monitor.apply(SystemSnapshot(temperatures: TemperatureSample(chip: 40),
                                           fans: [FanSample(index: 0, rpm: 1800, minimum: 1200, maximum: 5800)],
                                           processes: [ProcessUsage(pid: 123, name: "Fixture", cpuPercent: 1, memoryBytes: 1024)]))
        let records = model.monitor.logRecords.count
        model.suspendMainWindowContent()
        model.trimTransientMemory()
        #expect(!model.isMainWindowContentActive)
        #expect(model.cleanUp.phase == .review)
        #expect(model.cleanUp.selectedIDs == selection)
        #expect(model.monitor.processes.isEmpty)
        #expect(model.monitor.snapshot?.processes == nil)
        #expect(model.monitor.snapshot?.temperatures.chip == 40)
        #expect(model.monitor.snapshot?.fans.first?.rpm == 1800)
        #expect(model.monitor.isRecording && model.monitor.logRecords.count == records)
        model.resumeMainWindowContent()
        #expect(model.isMainWindowContentActive)
        #expect(model.cleanUp.selectedIDs == selection)
    }

    @MainActor
    @Test func diskTrimmingKeepsCurrentListingAndOverview() async throws {
        let fixture = try Fixture()
        let applications = try fixture.dir("Applications")
        let folders = try (0..<6).map { index -> URL in
            try fixture.file("Folder\(index)/data", bytes: 1024)
            return fixture.url("Folder\(index)")
        }
        let model = DiskUsageViewModel(home: fixture.home, applications: applications)
        model.start()
        for _ in 0..<200 where model.isMeasuringCurrent { try await Task.sleep(for: .milliseconds(5)) }
        for folder in folders {
            model.open(UsageEntry(url: folder, isDirectory: true))
            for _ in 0..<200 where model.isMeasuringCurrent { try await Task.sleep(for: .milliseconds(5)) }
            model.goBack(to: nil)
        }
        #expect(model.listings.count > 2)
        let current = try #require(folders.last)
        model.open(UsageEntry(url: current, isDirectory: true))
        let entries = model.currentEntries
        model.releaseInactiveListings()
        #expect(Set(model.listings.keys) == [DiskUsageViewModel.overviewKey, current.path])
        #expect(model.currentEntries == entries)
        #expect(model.path.last == current)
    }

    @MainActor
    @Test func scanningAppsDoesNotRetainPreRenderedIcons() async throws {
        let fixture = try Fixture()
        let applications = try fixture.dir("Applications")
        for index in 0..<20 {
            let contents = try fixture.dir("Applications/Fixture\(index).app/Contents")
            let info: NSDictionary = ["CFBundleName": "Fixture \(index)",
                                      "CFBundleIdentifier": "com.example.memory.\(index)",
                                      "CFBundlePackageType": "APPL", "CFBundleExecutable": "fixture"]
            #expect(info.write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
            try fixture.file("Applications/Fixture\(index).app/Contents/MacOS/fixture", bytes: 1)
        }
        let apps = await AppUninstallerEngine(home: fixture.home, appDirectories: [applications.path]).scanApplications()
        #expect(apps.count == 20)
        let transferred = await Task.detached { apps }.value
        #expect(transferred == apps, "App records cross concurrency boundaries as values; icons are loaded by presentation.")
    }

    actor DiskReader {
        private(set) var calls = 0
        private var pending: [Int: AsyncStream<DiskInfo>.Continuation] = [:]
        func read() async -> DiskInfo {
            calls += 1
            let id = calls
            let (stream, continuation) = AsyncStream<DiskInfo>.makeStream(bufferingPolicy: .bufferingNewest(1))
            pending[id] = continuation
            defer { pending[id] = nil }
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() ?? .empty
        }
        func finish(_ id: Int) {
            pending[id]?.yield(DiskInfo(totalBytes: 100, availableBytes: Int64(id)))
            pending[id]?.finish()
        }
        var pendingCount: Int { pending.count }
    }

    @MainActor
    @Test func repeatedDiskRefreshesCoalesceInsteadOfStartingMoreIO() async throws {
        let fixture = try Fixture()
        let suite = "CachePop.resource.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let reader = DiskReader()
        let model = AppModel(environment: fixture.environment(),
                             settings: AppSettings(defaults: try #require(UserDefaults(suiteName: suite)), canChangeLoginItem: false),
                             history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                             fanController: InertFanController(), startupControl: DemoStartupControl(),
                             diskReader: { _ in await reader.read() })
        for _ in 0..<50 { model.refreshDisk() }
        for _ in 0..<100 {
            if await reader.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await reader.calls == 1)
        await reader.finish(1)
        for _ in 0..<100 {
            if await reader.calls == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await reader.calls == 2)
        await reader.finish(2)
        for _ in 0..<100 where model.disk.availableBytes != 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.disk.availableBytes == 2)
        #expect(await reader.pendingCount == 0)
    }

    @MainActor
    @Test func appModelReleasesAndCancelsAnInFlightDiskRead() async throws {
        let fixture = try Fixture()
        let suite = "CachePop.resource.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let reader = DiskReader()
        var model: AppModel? = AppModel(environment: fixture.environment(),
                                       settings: AppSettings(defaults: try #require(UserDefaults(suiteName: suite)), canChangeLoginItem: false),
                                       history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                                       fanController: InertFanController(), startupControl: DemoStartupControl(),
                                       diskReader: { _ in await reader.read() })
        weak let released = model
        model?.startMonitoring()
        for _ in 0..<100 {
            if await reader.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        model = nil
        for _ in 0..<100 {
            if released == nil, await reader.pendingCount == 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(released == nil)
        #expect(await reader.pendingCount == 0)
    }

    actor HeldStartupControl: StartupControlling {
        private(set) var calls = 0
        private var pending: [Int: CheckedContinuation<[OpenAtLoginApp], any Error>] = [:]
        func overrides() async -> LaunchOverrides { LaunchOverrides() }
        func openAtLoginApps() async throws -> [OpenAtLoginApp] {
            try await withCheckedThrowingContinuation { continuation in
                calls += 1
                pending[calls] = continuation
            }
        }
        func set(_ item: LoginItem, on: Bool) async throws {}
        func finish(_ id: Int, apps: [OpenAtLoginApp] = []) { pending.removeValue(forKey: id)?.resume(returning: apps) }
    }

    @MainActor
    @Test func loginItemsReleaseWhileTheSystemListIsPending() async throws {
        let fixture = try Fixture()
        let control = HeldStartupControl()
        var model: LoginItemsViewModel? = LoginItemsViewModel(control: control, home: fixture.home)
        weak let released = model
        model?.scan()
        for _ in 0..<100 where await control.calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await control.calls == 1)
        model = nil
        #expect(released == nil)
        await control.finish(1)
    }

    @MainActor
    @Test func replacedLoginScanCannotChangeTheRememberedApps() async throws {
        let fixture = try Fixture()
        let control = HeldStartupControl()
        let model = LoginItemsViewModel(control: control, home: fixture.home)
        var writes = 0
        model.setRememberedOffApps = { _ in writes += 1 }
        model.scan()
        for _ in 0..<100 where await control.calls < 1 { try await Task.sleep(for: .milliseconds(5)) }
        model.scan()
        for _ in 0..<100 where await control.calls < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await control.calls == 2)
        await control.finish(2, apps: [OpenAtLoginApp(name: "Current", path: "/fixture/Current.app")])
        for _ in 0..<100 where !model.hasScanned { try await Task.sleep(for: .milliseconds(5)) }
        #expect(writes == 1)
        await control.finish(1, apps: [OpenAtLoginApp(name: "Stale", path: "/fixture/Stale.app")])
        try await Task.sleep(for: .milliseconds(30))
        #expect(writes == 1)
        #expect(model.apps.map(\.title) == ["Current"])
    }

    nonisolated final class FeatureCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var maximum = 0
        func add() { lock.withLock { count += 1; maximum = max(maximum, count) } }
        func remove() { lock.withLock { count -= 1 } }
        var live: Int { lock.withLock { count } }
        var peak: Int { lock.withLock { maximum } }
    }

    nonisolated final class Feature {
        let counter: FeatureCounter
        let vector = Data(repeating: 1, count: 16_384)
        init(_ counter: FeatureCounter) { self.counter = counter; counter.add() }
        deinit { counter.remove() }
    }

    private static func photo(_ index: Int, date: Date?) -> AnalyzedPhoto {
        AnalyzedPhoto(id: String(index), location: .library(String(index)), name: String(index), date: date,
                      pixelWidth: 1000, pixelHeight: 1000, bytes: nil, isFavorite: false,
                      metrics: PhotoMetrics(sharpness: 1, brightness: 0.5, shadows: 0, highlights: 0), issue: .blurry)
    }

    @Test func photoGroupingReleasesFeatureVectorsAsTheWindowAdvances() {
        let counter = FeatureCounter()
        var builder = PhotoGroupBuilder<Feature>()
        for index in 0..<5000 {
            builder.append(Self.photo(index, date: Date(timeIntervalSince1970: Double(index))),
                           feature: Feature(counter)) { _, _ in 1 }
        }
        #expect(counter.peak <= PhotoAnalyzer.neighbours + 1)
        let result = builder.finish()
        #expect(counter.live == 0)
        #expect(result.analyzedCount == 5000)
        #expect(result.photos(with: .blurry).count == 5000)
    }

    @Test func streamingPhotoGroupsMatchTheOriginalNeighbourAndTimeWindowRules() {
        let dates: [Date?] = (0..<240).map { index in
            index.isMultiple(of: 17) ? nil : Date(timeIntervalSince1970: Double(max(index - 100, 0) * 30))
        }
        let features: [Int?] = dates.indices.map { $0.isMultiple(of: 13) ? nil : $0 }
        let comparableDates = dates.indices.map { features[$0] == nil ? nil : dates[$0] }
        func distance(_ first: Int, _ second: Int) -> Float? { first % 11 == second % 11 ? 0.1 : 1 }
        let expected = PhotoGroupingReference.similarGroups(dates: comparableDates, distance: distance)
        var builder = PhotoGroupBuilder<Int>()
        for index in dates.indices.sorted(by: { (dates[$0] ?? .distantPast) < (dates[$1] ?? .distantPast) }) {
            builder.append(Self.photo(index, date: dates[index]), feature: features[index], distance: distance)
        }
        let result = builder.finish()
        #expect(Set(result.similar.map { Set($0.photos.map(\.id)) }) == Set(expected.map { Set($0.map(String.init)) }))
    }
}
