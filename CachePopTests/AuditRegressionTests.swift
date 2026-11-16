import Foundation
import Testing
@testable import CachePop

@Suite("Codebase audit regressions")
struct AuditRegressionTests {
    @MainActor
    @Test func lowSpaceAlertCooldownSurvivesRelaunch() throws {
        let suite = "CachePop.alerts.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        let now = Date()
        var rule = settings.savedLowSpaceRule
        let first = rule.evaluate(availableBytes: 0, thresholdBytes: 100, now: now)
        #expect(first)
        settings.savedLowSpaceRule = rule
        let reloaded = AppSettings(defaults: defaults, canChangeLoginItem: false)
        var restored = reloaded.savedLowSpaceRule
        #expect(restored == rule)
        let repeated = restored.evaluate(availableBytes: 0, thresholdBytes: 100, now: now.addingTimeInterval(60))
        #expect(!repeated)
    }

    @Test func unavailableProcessListsKeepInUseChecksBlocked() async {
        let runner = FakeCommandRunner { _ in CommandOutput(status: 1, stdout: "", stderr: "Unavailable") }
        let snapshot = await LiveProcessInspector(runner: runner).snapshot()
        #expect(!snapshot.executableListAvailable && !snapshot.commandLinesAvailable)
        #expect(inUseReason(for: .buildTools, processes: snapshot) != nil)
        #expect(inUseReason(for: .gradleDaemon, processes: snapshot) != nil)
        #expect(inUseReason(for: .androidEmulator(name: "Test"), processes: snapshot) != nil)
        #expect(inUseReason(for: .none, processes: snapshot) == nil)
    }

    @Test func commandTimeoutAlsoCoversInheritedOutputPipes() async throws {
        let command = ToolCommand(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 2 & exit 0"])
        await #expect(throws: CommandError.timedOut) {
            _ = try await ProcessCommandRunner().run(command, timeout: 0.2)
        }
    }

    @Test func invalidFanNumbersCannotReachTheSMC() {
        let types = ["F0Tg": "flt ", "F0Md": "ui8 ", "Ftst": "ui8 "]
        for value in [Double.nan, .infinity, -.infinity] {
            for type in ["flt ", "fpe2", "ui8 ", "ui16"] { #expect(SMC.encode(value, type: type) == nil) }
            #expect(FanWritePlan.manual(fan: 0, rpm: value, minimum: 1200, maximum: 5800, keyTypes: types) == nil)
        }
        #expect(SMC.encode(.greatestFiniteMagnitude, type: "flt ") == nil)
        #expect(SMC.encode(.greatestFiniteMagnitude, type: "ui16") == [255, 255])
        #expect(SMC.decode(type: "flt ", bytes: [0, 0, 192, 127]) == nil)
        #expect(FanWritePlan.manual(fan: -1, rpm: 2000, minimum: 1200, maximum: 5800, keyTypes: types) == nil)
        #expect(FanWritePlan.automatic(fan: -1, othersManual: false, keyTypes: ["FS! ": "ui16"]).isEmpty)
        #expect(FanWritePlan.manual(fan: 0, rpm: 2000, minimum: 6000, maximum: 5800, keyTypes: types) == nil)
    }

    @Test func aPartialReadCannotBecomeADuplicateDigest() throws {
        enum ReadFailure: Error { case interrupted }
        var reads = 0
        let failed = LargeFilesScanner.hashContents {
            reads += 1
            if reads == 1 { return Data("shared prefix".utf8) }
            throw ReadFailure.interrupted
        }
        #expect(failed == nil)

        let fixture = try Fixture()
        let file = try fixture.file("Downloads/readable", bytes: 8192)
        var finished = false
        let complete = LargeFilesScanner.hashContents {
            defer { finished = true }
            return finished ? nil : Data(repeating: 0xAB, count: 8192)
        }
        #expect(complete != nil)
        #expect(complete == LargeFilesScanner.fullHash(file))
    }

    @Test func largeDuplicateCopiesAreCountedOnceInTheHeadline() {
        let newest = FoundFile(url: URL(fileURLWithPath: "/a"), size: 200, modified: Date())
        let copy = FoundFile(url: URL(fileURLWithPath: "/b"), size: 200, modified: nil)
        let small = FoundFile(url: URL(fileURLWithPath: "/c"), size: 20, modified: Date())
        let smallCopy = FoundFile(url: URL(fileURLWithPath: "/d"), size: 20, modified: nil)
        let result = LargeFilesResult(largeFiles: [newest, copy], duplicates: [
            DuplicateSet(id: "big", files: [newest, copy]), DuplicateSet(id: "small", files: [small, smallCopy])
        ])
        #expect(result.reviewBytes == 420)
        #expect(result.otherLargeFiles == [newest])
        #expect(result.duplicateExtraBytes == 220)
    }

    @Test func incompleteScansAreReported() throws {
        let fixture = try Fixture()
        for name in ["a", "b", "c"] { try fixture.file("Downloads/\(name)") }
        let limited = LargeFilesScanner.scan(roots: [fixture.url("Downloads")], maximumFiles: 2)
        #expect(limited.scannedFileCount == 2)
        #expect(limited.wasLimited)
        let missing = LargeFilesScanner.scan(roots: [fixture.url("Disconnected Drive")])
        #expect(missing.scannedFileCount == 0)
        #expect(missing.unreadableCount == 1)
    }

    @MainActor
    @Test func missingCustomFoldersDoNotExpandTheSearch() async throws {
        let fixture = try Fixture()
        try fixture.file("Downloads/private.dat", bytes: 2_000_000)
        let suite = "CachePop.audit.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        settings.largeFileMinimumMB = 1
        settings.largeFileFolders = [fixture.url("Offline Drive").path]
        let model = LargeFilesViewModel(home: fixture.home, settings: settings)
        model.scan()
        for _ in 0..<200 where model.phase != .results { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.phase == .results)
        #expect(model.result.scannedFileCount == 0)
        #expect(model.result.largeFiles.isEmpty)
        #expect(model.result.unreadableCount == 1)
    }

    @Test func aCompletelyFullDiskStillTriggersAnAlert() {
        var rule = LowSpaceRule()
        let now = Date()
        let invalid = rule.evaluate(availableBytes: -1, thresholdBytes: 100, now: now)
        let full = rule.evaluate(availableBytes: 0, thresholdBytes: 100, now: now)
        let repeated = rule.evaluate(availableBytes: 0, thresholdBytes: 100, now: now)
        #expect(!invalid && full && !repeated)
    }

    @Test func putBackRestoresDanglingLinksAndProtectsOccupiedDestinations() throws {
        let fixture = try Fixture()
        let original = fixture.url("Downloads/link")
        let trashed = fixture.userTrash.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: trashed, withDestinationURL: fixture.url("missing-target"))
        let item = TrashedItem(original: original, trashed: trashed)
        let restored = PutBack.restore([item])
        #expect(restored.restored == [item])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: original.path) == fixture.url("missing-target").path)

        try FileManager.default.createSymbolicLink(at: trashed, withDestinationURL: fixture.url("another-target"))
        let blocked = PutBack.restore([item])
        #expect(blocked.restored.isEmpty)
        #expect(blocked.failures.count == 1)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: original.path) == fixture.url("missing-target").path)
    }

    @Test func aBuildStartedDuringCleaningKeepsItsDerivedData() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Logs/old.log", modified: daysAgo(60))
        try fixture.file("Library/Developer/Xcode/DerivedData/App/file")
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes))
        let scan = await engine.scan()
        let logs = try #require(scan.item("general.logs"))
        let build = try #require(scan.item("xcode.derivedData"))
        let selections = [logs, build].map { CleanupEngine.Selection(item: $0, action: $0.defaultAction) }
        let report = await engine.clean(selections) { index, _ in
            if index == 1 { processes.set(ProcessSnapshot(executableNames: ["xcodebuild"])) }
        }
        #expect(!fixture.exists("Library/Logs/old.log"))
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/App/file"))
        #expect(report.skipped.count == 1)
    }

    @MainActor
    @Test func theApplicationsEngineUsesItsInjectedHome() async throws {
        let fixture = try Fixture()
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.cachepop.auditdemo", "CFBundleName": "Audit Demo", "CFBundleShortVersionString": "1.0"
        ], format: .xml, options: 0)
        let plist = try fixture.file("Applications/Audit Demo.app/Contents/Info.plist", bytes: 0)
        try info.write(to: plist)
        try fixture.file("Library/Caches/com.cachepop.auditdemo/cache")
        let engine = AppUninstallerEngine(home: fixture.home, appDirectories: [fixture.url("Applications").path])
        let apps = await engine.scanApplications()
        #expect(apps.count == 1)
        let app = try #require(apps.first)
        #expect(app.bundleIdentifier == "com.cachepop.auditdemo")
        let files = await engine.findRelatedFiles(for: app, installedBundleIDs: [])
        #expect(!files.isEmpty)
        let home = try #require(PathSafety.canonicalPath(fixture.home))
        #expect(files.allSatisfy { $0.path.hasPrefix(home + "/") })
    }
}
