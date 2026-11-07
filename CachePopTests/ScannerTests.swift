import Foundation
import Testing
@testable import CachePop

@Suite("Scanners")
struct ScannerTests {
    // MARK: Xcode

    @Test func xcodeFindsDerivedDataDeviceSupportAndCaches() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyz/Build/app.o", bytes: 300_000)
        try fixture.file("Library/Developer/Xcode/DerivedData/Other-zyxwvutsrqponmlkjihgfedcba/Index/data", bytes: 100_000)
        try fixture.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 26.0 (23A341)/Symbols/dyld", bytes: 200_000)
        try fixture.file("Library/Caches/com.apple.dt.Xcode/Cache.db", bytes: 20_000)

        let group = XcodeScanner.scan(await fixture.context(fixture.environment()))

        let derived = try #require(group.item("xcode.derivedData"))
        #expect(derived.sizeBytes >= 400_000)
        #expect(derived.isRecommended)
        #expect(derived.defaultAction.regeneration == .automatic)
        #expect(derived.detail?.contains("2 projects") == true)
        #expect(derived.detail?.contains("App") == true)
        #expect(derived.defaultAction.operation.paths == [canonical(fixture.url("Library/Developer/Xcode/DerivedData"))])

        let support = try #require(group.item("xcode.deviceSupport.iOS DeviceSupport"))
        #expect(support.title == "iOS device support")
        #expect(support.defaultAction.regeneration == .onDeviceConnect)

        #expect(group.item("xcode.caches") != nil)
        #expect(group.item("xcode.archives") == nil)
    }

    @Test func derivedDataIsBlockedWhileABuildRuns() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/Xcode/DerivedData/App/file", bytes: 50_000)
        let building = ProcessSnapshot(executableNames: ["swift-frontend"])

        let group = XcodeScanner.scan(await fixture.context(fixture.environment(), processes: building))

        let derived = try #require(group.item("xcode.derivedData"))
        #expect(derived.isBlocked)
        #expect(derived.blockedReason?.contains("swift-frontend") == true)
    }

    @Test func onlyOldArchivesAreOfferedAndNeverPreselected() async throws {
        let fixture = try Fixture()
        try writeArchive(fixture, folder: "2025-01-02/Shipped 2025.xcarchive", name: "Shipped", created: daysAgo(300))
        try writeArchive(fixture, folder: "2026-10-30/Recent.xcarchive", name: "Recent", created: daysAgo(6))

        let group = XcodeScanner.scan(await fixture.context(fixture.environment()))

        let archives = try #require(group.item("xcode.archives"))
        #expect(!archives.isRecommended)
        #expect(archives.warning != nil)
        #expect(archives.defaultAction.regeneration == .movedToTrash)
        #expect(archives.defaultAction.operation.paths == [canonical(fixture.url("Library/Developer/Xcode/Archives/2025-01-02/Shipped 2025.xcarchive"))])
        guard case .moveToTrash = archives.defaultAction.operation else { Issue.record("Archives must go to the Trash"); return }
        #expect(archives.detail?.contains("1 archive") == true)
    }

    private func writeArchive(_ fixture: Fixture, folder: String, name: String, created: Date) throws {
        let base = "Library/Developer/Xcode/Archives/\(folder)"
        try fixture.file("\(base)/Products/Applications/\(name).app/binary", bytes: 40_000)
        let plist: NSDictionary = ["Name": name, "CreationDate": created]
        plist.write(to: fixture.url("\(base)/Info.plist"), atomically: true)
    }

    // MARK: Simulators

    @Test func simulatorsListsDevicesClonesRuntimesAndCaches() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/CoreSimulator/Caches/dyld/cache", bytes: 80_000)
        try fixture.file("Library/Developer/XCTestDevices/CLONE-1/data/file", bytes: 120_000)
        try fixture.file("Library/Developer/Xcode/UserData/Previews/Simulator Devices/P1/data", bytes: 60_000)

        let simctl = FakeSimctl(
            devices: [
                FakeDevice(udid: "IPHONE16", name: "iPhone 16", size: 1_030_000_000),
                FakeDevice(udid: "BOOTED", name: "iPhone 18 Pro Max", state: "Booted", size: 268_000_000),
                FakeDevice(udid: "GONE", name: "iPhone 8", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-16-0", available: false, size: 500_000_000)
            ],
            testingClones: [FakeDevice(udid: "CLONE-1", name: "Clone 1 of iPhone 16")],
            previewDevices: [FakeDevice(udid: "P1", name: "iPhone 16 (preview)")],
            runtimes: [
                FakeRuntime(identifier: "RT-27", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", version: "27.0", size: 8_000_000_000),
                FakeRuntime(identifier: "RT-26", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0", version: "26.0", size: 7_000_000_000),
                FakeRuntime(identifier: "RT-LOCKED", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.tvOS-26-0", version: "26.0", size: 3_000_000_000, deletable: false)
            ]
        )
        let env = fixture.environment(simctl: simctl)
        let group = await SimulatorScanner.scan(await fixture.context(env))

        // Bulk items are recommended and use simctl, never direct file deletion.
        let clones = try #require(group.item("simulators.testingClones"))
        #expect(clones.isRecommended && clones.sizeIsUpperBound)
        #expect(clones.defaultAction.operation == .command(ToolCommand(executable: FakeSimctl.simctlURL, arguments: ["--set", "testing", "delete", "all"])))

        let unavailable = try #require(group.item("simulators.unavailable"))
        #expect(unavailable.sizeBytes == 500_000_000)
        #expect(unavailable.defaultAction.operation == .command(ToolCommand(executable: FakeSimctl.simctlURL, arguments: ["delete", "unavailable"])))

        let previews = try #require(group.item("simulators.previews"))
        #expect(previews.defaultAction.operation == .command(ToolCommand(executable: FakeSimctl.simctlURL, arguments: ["--set", "previews", "delete", "all"])))

        // A simulator is booted, so its shared caches must wait.
        let caches = try #require(group.item("simulators.caches"))
        #expect(caches.isBlocked)

        // Only the runtime no simulator uses, and only if it's deletable.
        #expect(group.item("simulators.runtime.RT-26") != nil)
        #expect(group.item("simulators.runtime.RT-27") == nil)
        #expect(group.item("simulators.runtime.RT-LOCKED") == nil)
        #expect(group.item("simulators.runtime.RT-26")?.isRecommended == false)

        // Each simulator: name, runtime, size, state; erase or delete; never preselected.
        let iphone = try #require(group.item("simulators.device.IPHONE16"))
        #expect(iphone.title == "iPhone 16")
        #expect(iphone.detail?.contains("iOS 27.0") == true)
        #expect(iphone.detail?.contains("Shut down") == true)
        #expect(iphone.sizeBytes == 1_030_000_000)
        #expect(iphone.actions.map(\.id) == ["erase", "delete"])
        #expect(!iphone.isRecommended)
        #expect(!iphone.isBlocked)

        let booted = try #require(group.item("simulators.device.BOOTED"))
        #expect(booted.isBlocked)

        // Unavailable devices are only offered through the bulk item.
        #expect(group.item("simulators.device.GONE") == nil)
    }

    @Test func simulatorsWithoutXcodeExplainWhy() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/CoreSimulator/Caches/x", bytes: 10_000)

        let group = await SimulatorScanner.scan(await fixture.context(fixture.environment(simctl: nil)))

        #expect(group.items.map(\.id) == ["simulators.caches"])
        #expect(group.notes.first?.contains("Xcode isn't installed") == true)
    }

    @Test func testingClonesInUseAreBlocked() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/XCTestDevices/C/data", bytes: 10_000)
        let simctl = FakeSimctl(testingClones: [FakeDevice(udid: "C", name: "Clone", state: "Booted")])

        let group = await SimulatorScanner.scan(await fixture.context(fixture.environment(simctl: simctl)))

        #expect(group.item("simulators.testingClones")?.isBlocked == true)
    }

    // MARK: Developer caches

    @Test func developerCachesOnlyIncludeWhatExists() async throws {
        let fixture = try Fixture()
        try fixture.file(".npm/_cacache/content-v2/sha512/aa", bytes: 70_000)
        try fixture.file(".gradle/caches/modules-2/files-2.1/lib.jar", bytes: 90_000)
        try fixture.file("Library/Caches/org.swift.swiftpm/repositories/pkg", bytes: 30_000)
        try fixture.file(".cache/pip/http/cached", bytes: 10_000)
        try fixture.file(".cache/huggingface/models/model.bin", bytes: 200_000)
        try fixture.file(".m2/repository/junit/junit.jar", bytes: 10_000)

        let group = await DeveloperCacheScanner.scan(await fixture.context(fixture.environment()))
        let ids = Set(group.items.map(\.id))

        #expect(ids == ["dev.npm", "dev.gradleCaches", "dev.swiftpm", "dev.xdg.pip", "dev.xdg.huggingface", "dev.maven"])
        #expect(group.item("dev.npm")?.isRecommended == true)
        #expect(group.item("dev.xdg.pip")?.isRecommended == true)
        #expect(group.item("dev.xdg.huggingface")?.isRecommended == false, "unknown ~/.cache folders aren't preselected")
        #expect(group.item("dev.maven")?.isRecommended == false)
        #expect(group.item("dev.gradleCaches")?.defaultAction.regeneration == .redownloaded)
        #expect(group.item("dev.gradleCaches")?.isRecommended == false, "Gradle starts unticked")
        #expect(group.item("dev.homebrew") == nil, "Homebrew isn't installed in this fixture")
    }

    @Test func gradleIsBlockedWhileItsDaemonRuns() async throws {
        let fixture = try Fixture()
        try fixture.file(".gradle/caches/x", bytes: 10_000)
        let daemon = ProcessSnapshot(commandLines: ["java org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.10"])

        let group = await DeveloperCacheScanner.scan(await fixture.context(fixture.environment(), processes: daemon))

        #expect(group.item("dev.gradleCaches")?.isBlocked == true)
    }

    @Test func homebrewUsesDryRunSizeAndBrewCleanup() async throws {
        let fixture = try Fixture()
        let simctl = FakeSimctl(brewDryRun: "==> This operation would free approximately 512.0MB of disk space.")
        let env = fixture.environment(simctl: simctl, withBrew: true)

        let group = await DeveloperCacheScanner.scan(await fixture.context(env))

        let brew = try #require(group.item("dev.homebrew"))
        #expect(brew.sizeBytes == 512 * 1_048_576)
        guard case .command(let command) = brew.defaultAction.operation else {
            Issue.record("Homebrew should run a command")
            return
        }
        #expect(command.arguments == ["cleanup"])
        #expect(command.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    }

    // MARK: App caches, logs, installers, Trash

    @Test func appCachesSkipAppleDeveloperAndOpenApps() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.example.closed/cache.db", bytes: 50_000)
        try fixture.file("Library/Caches/com.spotify.client/data", bytes: 80_000)
        try fixture.file("Library/Caches/com.apple.Safari/x", bytes: 80_000)
        try fixture.file("Library/Caches/CloudKit/x", bytes: 80_000)
        try fixture.file("Library/Caches/org.swift.swiftpm/x", bytes: 80_000)
        let processes = ProcessSnapshot(runningAppBundleIDs: ["com.spotify.client"], runningAppNames: ["com.spotify.client": "Spotify"])

        let group = GeneralScanner.scan(await fixture.context(fixture.environment(), processes: processes))

        let caches = try #require(group.item("general.appCaches"))
        #expect(caches.defaultAction.operation.paths == [canonical(fixture.url("Library/Caches/com.example.closed"))])
        #expect(caches.isRecommended)
        #expect(group.notes.first?.contains("Spotify") == true)
    }

    @Test func onlyLogsOlderThanAWeekAreOffered() async throws {
        let fixture = try Fixture()
        let old = try fixture.file("Library/Logs/DiagnosticReports/crash.ips", bytes: 30_000, modified: daysAgo(30))
        try fixture.file("Library/Logs/App/today.log", bytes: 30_000, modified: daysAgo(1))

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let logs = try #require(group.item("general.logs"))
        #expect(logs.defaultAction.operation.paths == [canonical(old)])
        #expect(logs.detail == "1 file")
    }

    @Test func installersAreMovedToTrashAndNotPreselected() async throws {
        let fixture = try Fixture()
        let dmg = try fixture.file("Downloads/Tool.dmg", bytes: 40_000)
        try fixture.file("Downloads/notes.txt", bytes: 40_000)

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let installers = try #require(group.item("general.installers"))
        #expect(!installers.isRecommended)
        #expect(installers.defaultAction.operation.paths == [canonical(dmg)])
        guard case .moveToTrash = installers.defaultAction.operation else { Issue.record("Installers must go to the Trash"); return }
    }

    @Test func trashIsOfferedButNeverPreselected() async throws {
        let fixture = try Fixture()
        try fixture.file(".Trash/old.zip", bytes: 60_000)

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let trash = try #require(group.item("general.trash"))
        #expect(!trash.isRecommended)
        #expect(trash.defaultAction.regeneration == .permanent)
        #expect(trash.sizeBytes >= 60_000)
    }

    @Test func unreadableTrashAsksForFullDiskAccess() async throws {
        let fixture = try Fixture()
        try fixture.file(".Trash/old.zip")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.url(".Trash").path)

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let trash = try #require(group.item("general.trash"))
        #expect(trash.needsFullDiskAccess)
        #expect(trash.isBlocked)
    }
}

@Suite("Scanner edge cases")
struct ScannerEdgeCaseTests {
    @Test func emptyTestingDeviceSetIsNotOffered() async throws {
        let fixture = try Fixture()
        // What an empty XCTestDevices folder holds after `simctl --set testing delete all`.
        try fixture.file("Library/Developer/XCTestDevices/device_set.plist", bytes: 400)

        let group = await SimulatorScanner.scan(await fixture.context(fixture.environment(simctl: FakeSimctl())))

        #expect(group.item("simulators.testingClones") == nil)
    }
}

@Suite("Default selection")
struct RecommendationPolicyTests {
    private func item(_ id: String, bytes: Int64, regeneration: Regeneration, recommended: Bool = true) -> CleanupItem {
        CleanupItem(
            id: id,
            group: .developerCaches,
            title: id,
            explanation: "",
            sizeBytes: bytes,
            actions: [CleanupAction(id: "delete", title: "Delete", operation: .deleteContents([]), regeneration: regeneration, explanation: "")],
            isRecommended: recommended
        )
    }

    @Test func largeRedownloadsStartUnticked() {
        let big = RecommendationPolicy.apply(to: item("npm", bytes: 150_000_000, regeneration: .redownloaded))
        #expect(!big.isRecommended)
        #expect(big.note?.contains("100 MB") == true)
    }

    @Test func smallRedownloadsStayTicked() {
        let small = RecommendationPolicy.apply(to: item("npm", bytes: 50_000_000, regeneration: .redownloaded))
        #expect(small.isRecommended)
        #expect(small.note == nil)

        let boundary = RecommendationPolicy.apply(to: item("npm", bytes: 100_000_000, regeneration: .redownloaded))
        #expect(boundary.isRecommended, "exactly 100 MB isn't more than 100 MB")
    }

    @Test func thingsThatRebuildLocallyStayTickedWhateverTheirSize() {
        #expect(RecommendationPolicy.apply(to: item("derived", bytes: 5_000_000_000, regeneration: .automatic)).isRecommended)
        #expect(RecommendationPolicy.apply(to: item("support", bytes: 4_000_000_000, regeneration: .onDeviceConnect)).isRecommended)
        #expect(RecommendationPolicy.apply(to: item("unavailable", bytes: 2_000_000_000, regeneration: .unusable)).isRecommended)
    }

    @Test func groupKeepsTickedItemsFirst() {
        let group = CleanupGroup(kind: .developerCaches, items: [
            item("big", bytes: 900_000_000, regeneration: .redownloaded),
            item("small", bytes: 20_000_000, regeneration: .redownloaded)
        ])

        let updated = RecommendationPolicy.apply(to: group)

        #expect(updated.items.map(\.id) == ["small", "big"])
        #expect(updated.items.map(\.isRecommended) == [true, false])
    }

    @Test func scanAppliesTheRule() async throws {
        let fixture = try Fixture()
        try fixture.file(".npm/_cacache/index", bytes: 20_000)
        let simctl = FakeSimctl(brewDryRun: "==> This operation would free approximately 1.2GB of disk space.")
        let engine = CleanupEngine(env: fixture.environment(simctl: simctl, withBrew: true))

        let result = await engine.scan()

        let brew = try #require(result.item("dev.homebrew"))
        #expect(!brew.isRecommended)
        #expect(brew.note != nil)
        #expect(result.item("dev.npm")?.isRecommended == true)
    }
}
