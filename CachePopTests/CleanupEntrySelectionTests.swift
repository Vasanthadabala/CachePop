import Foundation
import Testing
@testable import CachePop

@Suite("Individual cleanup entries")
@MainActor
struct CleanupEntrySelectionTests {
    @Test func eachCloneIsAnIndependentTargetAndLegacyExclusionsStillApply() async throws {
        let fixture = try Fixture()
        for id in ["C1", "C2", "C3"] { try fixture.file("Library/Developer/XCTestDevices/\(id)/data/file") }
        let simctl = FakeSimctl(testingClones: [FakeDevice(udid: "C1", name: "Clone 1"),
                                               FakeDevice(udid: "C2", name: "Clone 2"),
                                               FakeDevice(udid: "C3", name: "Clone 3")])
        let runner = simctl.runner()
        let engine = CleanupEngine(env: fixture.environment(simctl: simctl, runner: runner))
        let result = await engine.scan()
        let clones = result.allItems.filter { $0.parentID == "simulators.testingClones" }
        #expect(clones.count == 3)
        #expect(result.item("simulators.testingClones") == nil)
        let selected = try #require(clones.first { $0.id.hasSuffix(".C2") })
        _ = await engine.clean([CleanupSelection(item: selected, action: selected.defaultAction)])
        #expect(runner.mutatingCalls == [["--set", "testing", "delete", "C2"]])
        var never = NeverCleanList()
        never.itemIDs.insert("simulators.testingClones")
        let excluded = await engine.scan(settings: CleanupSettings(neverClean: never))
        #expect(!excluded.allItems.contains { $0.parentID == "simulators.testingClones" })
    }

    @Test func eightProjectsAreListedAndOnlyTheChosenProjectsAreRemoved() async throws {
        let fixture = try Fixture()
        for index in 1...8 {
            try fixture.file("Library/Developer/Xcode/DerivedData/Project\(index)-abcdefghijklmnopqrst/Build/output", bytes: index * 8_192)
        }
        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let item = try #require(result.item("xcode.derivedData"))
        #expect(item.entries.count == 8)
        #expect(Set(item.entries.map(\.title)) == Set((1...8).map { "Project\($0)" }))
        let model = CleanUpViewModel(engine: engine)
        model.apply(result)
        for group in result.groups { model.setAll(in: group, selected: false) }
        let selected = item.entries.filter { ["Project2", "Project7"].contains($0.title) }
        for entry in selected { model.setSelected(entry, in: item, true) }
        #expect(model.selectionState(for: item) == .mixed)
        #expect(model.selectionState(in: result.groups.first { $0.kind == .xcode }!) == .mixed)
        #expect(model.selectedBytes == selected.reduce(0) { $0 + ($1.sizeBytes ?? 0) })
        #expect(model.selections.count == 1, "File operations stay batched for one fresh process check.")
        #expect(model.selections[0].item.entries.map(\.id) == selected.map(\.id))
        // A new project appearing after scan must never enter a saved selection.
        try fixture.file("Library/Developer/Xcode/DerivedData/NewProject/Build/output")
        let report = await engine.clean(model.selections)
        #expect(report.failed.isEmpty)
        for index in 1...8 {
            #expect(fixture.exists("Library/Developer/Xcode/DerivedData/Project\(index)-abcdefghijklmnopqrst/Build/output") == ![2, 7].contains(index))
        }
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/NewProject/Build/output"))
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData"))
    }

    @Test func selectionPersistsAndParentControlsSelectAllOrNone() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Logs/a.log", modified: daysAgo(30))
        try fixture.file("Library/Logs/b.log", modified: daysAgo(30))
        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let item = try #require(result.item("general.logs"))
        let first = try #require(item.entries.first)
        let model = CleanUpViewModel(engine: engine)
        model.apply(result)
        model.setSelected(first, in: item, false)
        #expect(model.selectedEntries(for: item).count == 1)
        #expect(model.selectionState(for: item) == .mixed)
        model.toggle(item)
        #expect(model.selectedEntries(for: item).count == 2)
        model.toggle(item)
        #expect(model.selectedEntries(for: item).isEmpty)
        #expect(model.selections.isEmpty)
        model.setSelected(first, in: item, true)
        model.apply(result)
        #expect(model.selectedEntryIDs.isEmpty)
        #expect(model.selectedEntries(for: item).count == 2)
        model.startOver()
        #expect(model.selectedEntryIDs.isEmpty && model.selectedIDs.isEmpty)
    }

    @Test func browserDatabaseAndItsCompanionFilesAreSelectedTogether() async throws {
        let fixture = try Fixture()
        let base = "Library/Application Support/Google/Chrome"
        for profile in ["Default", "Profile 1"] {
            try fixture.file("\(base)/\(profile)/Preferences")
            for file in ["History", "History-wal", "History-shm"] { try fixture.file("\(base)/\(profile)/\(file)") }
        }
        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let item = try #require(result.item("browsers.chrome.history"))
        #expect(item.entries.count == 2)
        let entry = try #require(item.entries.first { $0.title == "Profile 1" })
        guard case .delete(let urls) = entry.operations["delete"] else { Issue.record("Expected a profile delete operation"); return }
        #expect(Set(urls.map(\.lastPathComponent)) == ["History", "History-wal", "History-shm"])
        let model = CleanUpViewModel(engine: engine)
        model.apply(result)
        model.setSelected(entry, in: item, true)
        let report = await engine.clean(model.selections)
        #expect(report.failed.isEmpty)
        #expect(fixture.exists("\(base)/Default/History"))
        #expect(!fixture.exists("\(base)/Profile 1/History"))
        #expect(!fixture.exists("\(base)/Profile 1/History-wal"))
        #expect(!fixture.exists("\(base)/Profile 1/History-shm"))
        #expect(fixture.exists("\(base)/Profile 1/Preferences"))
    }

    @Test func appCachesListEachAppAndRecheckItsOwnerBeforeCleaning() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.example.alpha/cache")
        try fixture.file("Library/Caches/com.example.beta/cache")
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes))
        let result = await engine.scan()
        let item = try #require(result.item("general.appCaches"))
        #expect(item.entries.count == 2)
        let alpha = try #require(item.entries.first { $0.title == "com.example.alpha" })
        let model = CleanUpViewModel(engine: engine)
        model.apply(result)
        model.setSelected(item, false)
        model.setSelected(alpha, in: item, true)
        processes.set(ProcessSnapshot(runningAppBundleIDs: ["com.example.alpha"]))
        _ = await engine.clean(model.selections)
        #expect(fixture.exists("Library/Caches/com.example.alpha/cache"))
        #expect(fixture.exists("Library/Caches/com.example.beta/cache"))
        processes.set(.empty)
        _ = await engine.clean(model.selections)
        #expect(!fixture.exists("Library/Caches/com.example.alpha/cache"))
        #expect(fixture.exists("Library/Caches/com.example.alpha"))
        #expect(fixture.exists("Library/Caches/com.example.beta/cache"))
    }

    @Test func onlyChosenInstallersMoveToTrashWithRecoveryLocations() async throws {
        let fixture = try Fixture()
        let original = try fixture.file("Downloads/A.dmg").resolvingSymlinksInPath()
        try fixture.file("Downloads/B.pkg")
        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let item = try #require(result.item("general.installers"))
        let entry = try #require(item.entries.first { $0.title == "A.dmg" })
        let selected = item.scopedSelections(entryIDs: [entry.id], actionID: "trash")
        let report = await engine.clean(selected)
        #expect(report.trashedItems.count == 1)
        let recovery = try #require(report.trashedItems.first)
        #expect(recovery.original.lastPathComponent == original.lastPathComponent)
        #expect(PathSafety.canonicalPath(recovery.original.deletingLastPathComponent())
                == PathSafety.canonicalPath(original.deletingLastPathComponent()))
        #expect(fixture.exists("Downloads/B.pkg"))
        #expect(!fixture.exists("Downloads/A.dmg"))
    }

    @Test func neverCleanAppliesBothAtScanAndAfterIndividualSelection() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Developer/Xcode/DerivedData/Keep/Build/output")
        try fixture.file("Library/Developer/Xcode/DerivedData/Delete/Build/output")
        let engine = CleanupEngine(env: fixture.environment())
        var never = NeverCleanList()
        never.folders = [fixture.url("Library/Developer/Xcode/DerivedData/Keep")]
        let result = await engine.scan(settings: CleanupSettings(neverClean: never))
        let item = try #require(result.item("xcode.derivedData"))
        #expect(item.entries.map(\.title) == ["Delete"])
        let model = CleanUpViewModel(engine: engine)
        model.apply(result)
        never.folders.append(fixture.url("Library/Developer/Xcode/DerivedData/Delete"))
        _ = await engine.clean(model.selections, neverClean: never)
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/Keep/Build/output"))
        #expect(fixture.exists("Library/Developer/Xcode/DerivedData/Delete/Build/output"))
    }

    @Test func selectedSimulatorUsesItsExactIdentifierAndParentNeverCleanRule() async throws {
        let fixture = try Fixture()
        let simctl = FakeSimctl(devices: [FakeDevice(udid: "A", name: "First", available: false),
                                          FakeDevice(udid: "B", name: "Second", available: false)])
        let runner = simctl.runner()
        let engine = CleanupEngine(env: fixture.environment(simctl: simctl, runner: runner))
        let result = await engine.scan()
        let items = result.allItems.filter { $0.parentID == "simulators.unavailable" }
        #expect(items.count == 2)
        let second = try #require(items.first { $0.id.hasSuffix(".B") })
        let one = [CleanupSelection(item: second, action: second.defaultAction)]
        #expect(one.first?.action.operation == .command(ToolCommand(executable: FakeSimctl.simctlURL, arguments: ["delete", "B"])))
        _ = await engine.clean(one)
        #expect(runner.mutatingCalls == [["delete", "B"]])
        let all = items.map { CleanupSelection(item: $0, action: $0.defaultAction) }
        var never = NeverCleanList()
        never.itemIDs.insert("simulators.unavailable")
        let report = await engine.clean(all, neverClean: never)
        #expect(report.skipped.count == 2)
        #expect(runner.mutatingCalls == [["delete", "B"]])

    }

    @Test func unrecognizedEntryIDsDoNotExpandASelection() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Logs/old.log", modified: daysAgo(30))
        let engine = CleanupEngine(env: fixture.environment())
        let result = await engine.scan()
        let item = try #require(result.item("general.logs"))
        #expect(item.scopedSelections(entryIDs: ["not-scanned"], actionID: "delete").isEmpty)
        #expect(item.scopedSelections(entryIDs: [], actionID: "delete").isEmpty)
    }

    @Test func snapshotsUseIndividualDatesWithoutInventingPerSnapshotSizes() async throws {
        let fixture = try Fixture()
        let runner = FakeCommandRunner { command in
            CommandOutput(status: 0, stdout: command.arguments.first == "listlocalsnapshotdates"
                          ? "Snapshot dates for disk /:\n2026-11-01-120000\n2026-11-02-120000\n" : "", stderr: "")
        }
        let env = fixture.environment(runner: runner)
        let context = await fixture.context(env)
        let group = await TimeMachineScanner.scan(context)
        let item = try #require(group.items.first)
        #expect(item.entries.count == 2)
        #expect(item.entries.allSatisfy { $0.sizeBytes == nil })
        let model = CleanUpViewModel(engine: CleanupEngine(env: env))
        model.apply(CleanupScanResult(groups: [group]))
        let entry = try #require(item.entries.first { $0.id == "2026-11-02-120000" })
        model.setSelected(entry, in: item, true)
        #expect(model.selectionHasUnknownSizes)
        #expect(model.selectionSummary.contains("Size unavailable"))
        #expect(model.selections.first?.action.operation == .command(ToolCommand(executable: TimeMachineScanner.tmutil,
                                                                                arguments: ["deletelocalsnapshots", entry.id])))
    }

    @Test func blockedItemsCannotBeSelectedThroughTheirDetails() async throws {
        let fixture = try Fixture()
        let item = CleanupItem(id: "blocked", group: .general, title: "Private data", explanation: "", sizeBytes: 0,
                               actions: [CleanupAction(id: "delete", title: "Delete", operation: .delete([]),
                                                       regeneration: .automatic, explanation: "")],
                               isRecommended: false, blockedReason: "Access required", needsFullDiskAccess: true)
        let model = CleanUpViewModel(engine: CleanupEngine(env: fixture.environment()))
        model.apply(CleanupScanResult(groups: [CleanupGroup(kind: .general, items: [item])]))
        model.setSelected(item.inspectionEntries[0], in: item, true)
        model.setSelected(item, true)
        #expect(model.selections.isEmpty)
    }

    @Test func protectingADatabaseCompanionKeepsTheWholeProfile() async throws {
        let fixture = try Fixture()
        let base = "Library/Application Support/Google/Chrome"
        for profile in ["Default", "Profile 1"] {
            try fixture.file("\(base)/\(profile)/Preferences")
            for file in ["History", "History-wal", "History-shm"] { try fixture.file("\(base)/\(profile)/\(file)") }
        }
        let engine = CleanupEngine(env: fixture.environment())
        var never = NeverCleanList()
        never.folders = [fixture.url("\(base)/Profile 1/History-wal")]
        let filtered = await engine.scan(settings: CleanupSettings(neverClean: never))
        let filteredItem = try #require(filtered.item("browsers.chrome.history"))
        #expect(filteredItem.entries.map(\.title) == ["Default"])
        let original = await engine.scan()
        let item = try #require(original.item("browsers.chrome.history"))
        let entry = try #require(item.entries.first { $0.title == "Default" })
        never.folders = [fixture.url("\(base)/Default/History-wal")]
        let report = await engine.clean(item.scopedSelections(entryIDs: [entry.id], actionID: "delete"), neverClean: never)
        #expect(report.skipped.count == 1)
        for profile in ["Default", "Profile 1"] {
            for file in ["History", "History-wal", "History-shm"] {
                #expect(fixture.exists("\(base)/\(profile)/\(file)"))
            }
        }
    }
}
