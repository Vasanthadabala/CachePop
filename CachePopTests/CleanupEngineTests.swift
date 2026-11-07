import Foundation
import Testing
@testable import CachePop

@Suite("Cleanup engine")
struct CleanupEngineTests {
    /// A developer Mac in miniature: Xcode, simulators, package caches, app caches, logs,
    /// installers, Trash — plus personal files that must survive.
    private func makeDeveloperMac() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyz/Build/app.o", bytes: 400_000)
        try fixture.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 26.0 (23A341)/Symbols/dyld", bytes: 300_000)
        try fixture.file("Library/Developer/CoreSimulator/Caches/dyld/cache", bytes: 100_000)
        try fixture.file("Library/Developer/XCTestDevices/CLONE/data/file", bytes: 200_000)
        try fixture.file(".npm/_cacache/index-v5/aa", bytes: 150_000)
        try fixture.file(".gradle/caches/modules-2/lib.jar", bytes: 250_000)
        try fixture.file("Library/Caches/org.swift.swiftpm/repositories/pkg", bytes: 50_000)
        try fixture.file("Library/Caches/com.example.app/data", bytes: 60_000)
        try fixture.file("Library/Logs/old.log", bytes: 20_000, modified: daysAgo(40))
        try fixture.file("Library/Logs/new.log", bytes: 20_000, modified: daysAgo(1))
        try fixture.file("Downloads/Installer.dmg", bytes: 70_000)
        try fixture.file(".Trash/thrown-away.zip", bytes: 30_000)

        // Personal data, plus a symlink from a cache to it.
        let documents = try fixture.dir("Documents")
        try fixture.file("Documents/thesis.pages", bytes: 10_000)
        try fixture.file("Projects/App/Sources/main.swift", bytes: 1_000)
        try fixture.symlink(".npm/_cacache/link-to-documents", to: documents)
        return fixture
    }

    private func developerSimctl(bootedUDID: String? = nil) -> FakeSimctl {
        FakeSimctl(
            devices: [
                FakeDevice(udid: "IPHONE16", name: "iPhone 16", state: bootedUDID == "IPHONE16" ? "Booted" : "Shutdown"),
                FakeDevice(udid: "GONE", name: "iPhone 8", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-16-0", available: false, size: 400_000_000)
            ],
            testingClones: [FakeDevice(udid: "CLONE", name: "Clone 1 of iPhone 16")]
        )
    }

    private func recommendedSelections(_ result: CleanupScanResult) -> [CleanupEngine.Selection] {
        result.allItems
            .filter { $0.isRecommended && !$0.isBlocked }
            .map { CleanupEngine.Selection(item: $0, action: $0.defaultAction) }
    }

    @Test func scanThenCleanRecommendedEndToEnd() async throws {
        let fixture = try makeDeveloperMac()
        let simctl = developerSimctl()
        let runner = simctl.runner()
        let space = FakeSpaceMeter([10_000_000, 10_000_000, 11_200_000, 11_500_000, 11_500_000, 11_500_000])
        let engine = CleanupEngine(env: fixture.environment(simctl: simctl, space: space, runner: runner))

        let result = await engine.scan()
        #expect(result.groups.map(\.kind) == CleanupGroupKind.allCases)

        // Preselected: regenerable things only.
        let recommended = Set(result.allItems.filter(\.isRecommended).map(\.id))
        #expect(recommended.isSuperset(of: [
            "xcode.derivedData", "xcode.deviceSupport.iOS DeviceSupport", "simulators.caches",
            "simulators.testingClones", "simulators.unavailable", "dev.npm",
            "dev.swiftpm", "general.appCaches", "general.logs"
        ]))
        #expect(!recommended.contains("dev.gradleCaches"), "Gradle is slow to rebuild, so it starts unticked")
        #expect(!recommended.contains("general.trash"))
        #expect(!recommended.contains("general.installers"))
        #expect(!recommended.contains("simulators.device.IPHONE16"))

        let report = await engine.clean(recommendedSelections(result))

        // Caches are emptied but their folders stay.
        #expect(fixture.children("Library/Developer/Xcode/DerivedData").isEmpty)
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData"))
        #expect(fixture.children("Library/Developer/Xcode/iOS DeviceSupport").isEmpty)
        #expect(fixture.children(".npm").isEmpty)
        #expect(!fixture.children(".gradle/caches").isEmpty, "unticked, so left alone")
        #expect(fixture.children("Library/Caches/com.example.app").isEmpty)
        #expect(!fixture.exists("Library/Logs/old.log"))
        #expect(fixture.exists("Library/Logs/new.log"))

        // Unselected and personal data are untouched; the symlink went, its target didn't.
        #expect(fixture.exists("Downloads/Installer.dmg"))
        #expect(fixture.exists(".Trash/thrown-away.zip"))
        #expect(fixture.exists("Documents/thesis.pages"))
        #expect(fixture.exists("Projects/App/Sources/main.swift"))

        // Simulators go through simctl only.
        #expect(runner.mutatingCalls.contains(["--set", "testing", "delete", "all"]))
        #expect(runner.mutatingCalls.contains(["delete", "unavailable"]))
        #expect(!runner.mutatingCalls.contains { $0.contains("IPHONE16") })

        // Every selection succeeded, and the headline number is the measured one.
        #expect(report.failed.isEmpty)
        #expect(report.skipped.isEmpty)
        #expect(report.availableBefore == 10_000_000)
        #expect(report.measuredFreedBytes == 1_500_000)
        #expect(report.estimatedFreedBytes > 0)
    }

    @Test func bootedSimulatorIsNeverErasedEvenIfItBootedAfterTheScan() async throws {
        let fixture = try Fixture()
        let scanRunner = developerSimctl().runner()
        let scanEngine = CleanupEngine(env: fixture.environment(simctl: developerSimctl(), runner: scanRunner))
        let item = try #require(await scanEngine.scan().item("simulators.device.IPHONE16"))
        #expect(!item.isBlocked)

        // By clean time the simulator has booted.
        let bootedSimctl = developerSimctl(bootedUDID: "IPHONE16")
        let cleanRunner = bootedSimctl.runner()
        let engine = CleanupEngine(env: fixture.environment(simctl: bootedSimctl, runner: cleanRunner))
        let erase = item.action(withID: "erase")
        let report = await engine.clean([.init(item: item, action: erase)])

        #expect(report.skipped.count == 1)
        #expect(cleanRunner.mutatingCalls.isEmpty)
    }

    @Test func eraseAndDeleteIssueTheChosenSimctlCommand() async throws {
        let fixture = try Fixture()
        let simctl = developerSimctl()
        let runner = simctl.runner()
        let engine = CleanupEngine(env: fixture.environment(simctl: simctl, runner: runner))
        let item = try #require(await engine.scan().item("simulators.device.IPHONE16"))

        _ = await engine.clean([.init(item: item, action: item.action(withID: "erase"))])
        _ = await engine.clean([.init(item: item, action: item.action(withID: "delete"))])

        #expect(runner.mutatingCalls == [["erase", "IPHONE16"], ["delete", "IPHONE16"]])
    }

    @Test func buildStartedAfterScanSkipsDerivedData() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/Xcode/DerivedData/App/file", bytes: 50_000)
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes))
        let item = try #require(await engine.scan().item("xcode.derivedData"))

        processes.set(ProcessSnapshot(executableNames: ["xcodebuild"]))
        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(report.skipped.count == 1)
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/App/file"))
    }

    @Test func appOpenedAfterScanKeepsItsCache() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.example.closed/data", bytes: 40_000)
        try fixture.file("Library/Caches/com.example.reopened/data", bytes: 40_000)
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes))
        let item = try #require(await engine.scan().item("general.appCaches"))

        processes.set(ProcessSnapshot(runningAppBundleIDs: ["com.example.reopened"], runningAppNames: ["com.example.reopened": "Reopened"]))
        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(!fixture.exists("Library/Caches/com.example.closed/data"))
        #expect(fixture.exists("Library/Caches/com.example.reopened/data"))
        guard case .failed(let message, let removed) = report.entries.first?.outcome else {
            Issue.record("Expected a partial result")
            return
        }
        #expect(message.contains("Reopened"))
        #expect(removed > 0)
    }

    @Test func installersAndArchivesGoToTheTrashNotDeleted() async throws {
        let fixture = try Fixture()
        try fixture.file("Downloads/Big.pkg", bytes: 70_000)
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("general.installers"))

        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(!fixture.exists("Downloads/Big.pkg"))
        #expect(FileManager.default.fileExists(atPath: fixture.userTrash.appendingPathComponent("Big.pkg").path))
        #expect(report.movedToTrashBytes == item.sizeBytes)
        #expect(report.estimatedFreedBytes == 0, "moving to the Trash frees nothing yet")
    }

    @Test func emptyingTheTrashDeletesItsContents() async throws {
        let fixture = try Fixture()
        try fixture.file(".Trash/a.zip", bytes: 20_000)
        try fixture.file(".Trash/folder/b.mov", bytes: 20_000)
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("general.trash"))

        _ = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(fixture.children(".Trash").isEmpty)
        #expect(fixture.exists(".Trash"))
    }

    @Test func readOnlyCacheFoldersAreStillRemoved() async throws {
        let fixture = try Fixture()
        try fixture.file(".npm/_cacache/locked/file", bytes: 20_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.url(".npm/_cacache/locked").path)
        let engine = CleanupEngine(env: fixture.environment())
        let item = try #require(await engine.scan().item("dev.npm"))

        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(report.failed.isEmpty)
        #expect(fixture.children(".npm").isEmpty)
    }

    @Test func tamperedSelectionOutsideCacheRootsIsRefused() async throws {
        let fixture = try Fixture()
        let document = try fixture.file("Documents/keep.txt")
        let forged = CleanupItem(
            id: "forged",
            group: .general,
            title: "Forged",
            explanation: "",
            sizeBytes: 1,
            actions: [CleanupAction(id: "delete", title: "Delete", operation: .delete([document]), regeneration: .automatic, explanation: "")],
            isRecommended: true
        )
        let engine = CleanupEngine(env: fixture.environment())

        let report = await engine.clean([.init(item: forged, action: forged.defaultAction)])

        #expect(report.failed.count == 1)
        #expect(fixture.exists("Documents/keep.txt"))
    }

    @Test func failedSimctlCommandIsReported() async throws {
        let fixture = try Fixture()
        var simctl = developerSimctl()
        simctl.failingArguments = ["delete", "unavailable"]
        let engine = CleanupEngine(env: fixture.environment(simctl: simctl))
        let item = try #require(await engine.scan().item("simulators.unavailable"))

        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        guard case .failed(let message, _) = report.entries.first?.outcome else {
            Issue.record("Expected a failure")
            return
        }
        #expect(message.contains("simctl delete unavailable"))
    }

    @Test func freedSpaceIsMeasuredAfterAPFSSettles() async throws {
        let fixture = try Fixture()
        // Before, then readings that keep rising before they settle.
        let space = FakeSpaceMeter([5_000, 5_000, 6_000, 7_000, 7_500, 7_500, 7_500])
        let engine = CleanupEngine(env: fixture.environment(space: space))

        let report = await engine.clean([])

        #expect(report.measuredFreedBytes == 2_500)
    }

    @Test func measuredFreedSpaceNeverGoesNegative() {
        let report = CleanupReport(entries: [], availableBefore: 10_000, availableAfter: 9_000)
        #expect(report.measuredFreedBytes == 0)
    }
}
