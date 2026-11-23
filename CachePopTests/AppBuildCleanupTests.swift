import Foundation
import Testing
@testable import CachePop

@Suite("Extra app build cleanup")
struct AppBuildCleanupTests {
    private let bundleID = "com.example.Example"
    private let build = "Projects/Example/build/DerivedData/Build/Products/Debug/Example.app"

    @discardableResult
    private func app(_ fixture: Fixture, _ path: String, id: String = "com.example.Example") throws -> URL {
        let url = try fixture.dir(path)
        let info: [String: String] = [
            "CFBundleIdentifier": id, "CFBundleName": "Example", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2", "CFBundleExecutable": "Example"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try fixture.dir(path + "/Contents")
        try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try fixture.file(path + "/Contents/MacOS/Example", bytes: 20_000)
        return url
    }

    private func catalog(_ urls: [URL]) -> FakeAppCatalog {
        FakeAppCatalog(installed: [bundleID.lowercased()], registered: [bundleID.lowercased(): urls])
    }

    @Test func findsBuildsAndSiblingTestRunnersWithoutDoubleCounting() async throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        let runnerPath = "Projects/Example/build/DerivedData/Build/Products/Debug/ExampleUITests-Runner.app"
        let runner = try app(fixture, runnerPath, id: "com.example.ExampleUITests.xctrunner")
        let installed = try app(fixture, "Applications/Example.app")
        let derived = try app(fixture, "Library/Developer/Xcode/DerivedData/Example/Build/Products/Debug/Example.app")
        let env = fixture.environment(apps: catalog([built, built, installed, derived]))
        let group = XcodeScanner.scan(await fixture.context(env))
        let extras = group.items.filter { $0.id.hasPrefix("xcode.appBuild.") }
        #expect(extras.count == 2)
        #expect(Set(extras.flatMap { $0.defaultAction.operation.paths }) == [canonical(built), canonical(runner)])
        #expect(extras.allSatisfy { !$0.isRecommended && $0.defaultAction.regeneration == .movedToTrash })
        #expect(extras.allSatisfy { $0.detail?.contains("Version 1.2") == true && $0.detail?.contains("/build/") == true })
        #expect(extras.contains { $0.title.contains("test runner") })
        #expect(group.item("xcode.derivedData") != nil)
    }

    @Test func onlyOffersExportsUnderAnXcodeProjectsBuildFolder() async throws {
        let fixture = try Fixture()
        try fixture.dir("Projects/Example/Example.xcodeproj")
        let exported = try app(fixture, "Projects/Example/build/release/notarized/Example.app")
        let random = try app(fixture, "Downloads/build/export/Example.app")
        let archive = try app(fixture, "Projects/Example/build/Example.xcarchive/Products/Applications/Example.app")
        let submission = try app(fixture, "Projects/Example/build/Example.xcarchive/Submissions/123/Example.app")
        let env = fixture.environment(apps: catalog([exported, random, archive, submission]))
        let group = AppBuildScanner.scan(await fixture.context(env))
        #expect(group.items.count == 1)
        #expect(group.items.first?.defaultAction.operation.paths == [canonical(exported)])
    }

    @Test func refusesSymlinksAppleAppsAndInvalidBundles() throws {
        let fixture = try Fixture()
        let installed = try app(fixture, "Applications/Example.app")
        try fixture.symlink(build, to: installed)
        let apple = try app(fixture, "Other/Build/Products/Debug/System.app", id: "com.apple.example")
        let invalid = try fixture.dir("Other/Build/Products/Debug/Invalid.app")
        #expect(!AppBuildScanner.isDisposableBuild(fixture.url(build)))
        #expect(!AppBuildScanner.isDisposableBuild(apple))
        #expect(!AppBuildScanner.isDisposableBuild(invalid))
        #expect(!AppBuildScanner.isDisposableBuild(installed))
    }

    @Test func customBuildExceptionIsTrashOnlyAndRechecksIdentifier() throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        #expect(PathSafety.violation(for: built, mode: .trash, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: built, mode: .trash, home: fixture.home, appBuildBundleID: bundleID) == nil)
        #expect(PathSafety.violation(for: built, mode: .delete, home: fixture.home, appBuildBundleID: bundleID) != nil)
        #expect(PathSafety.violation(for: built, mode: .trash, home: fixture.home, appBuildBundleID: "com.other.app") != nil)
    }

    @Test func permitsOnlyReviewedBundlesOutsideHome() throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        let separateHome = try fixture.dir("OtherHome")
        #expect(PathSafety.violation(for: built, mode: .trash, home: separateHome) != nil)
        #expect(PathSafety.violation(for: built, mode: .trash, home: separateHome, appBuildBundleID: bundleID) == nil)
        #expect(PathSafety.violation(for: built, mode: .delete, home: separateHome, appBuildBundleID: bundleID) != nil)
    }

    @Test func installedCopyCanStayOpenButRunningBuildAndUnknownStateAreBlocked() throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        let check = InUseCheck.appBuild(bundleID: bundleID.lowercased(), path: canonical(built))
        var processes = ProcessSnapshot(runningAppBundleIDs: [bundleID.lowercased()])
        #expect(inUseReason(for: check, processes: processes) != nil)
        processes.runningAppPaths = [bundleID.lowercased(): ["/Applications/Example.app"]]
        #expect(inUseReason(for: check, processes: processes) == nil)
        processes.runningAppPaths[bundleID.lowercased()]?.insert(canonical(built))
        #expect(inUseReason(for: check, processes: processes) != nil)
        #expect(inUseReason(for: check, processes: ProcessSnapshot(executableNames: ["xcodebuild"])) != nil)
        #expect(inUseReason(for: check, processes: ProcessSnapshot(executableListAvailable: false)) != nil)
        #expect(inUseReason(for: check, processes: ProcessSnapshot(commandLinesAvailable: false)) != nil)
        #expect(inUseReason(for: check, processes: ProcessSnapshot(commandLines: [canonical(built) + "/Contents/MacOS/Example -test"])) != nil)
    }

    @Test func trashesOnlySelectedBuildAndSupportsPutBack() async throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        try fixture.file("Projects/Example/Sources/App.swift")
        try app(fixture, "Applications/Example.app")
        let engine = CleanupEngine(env: fixture.environment(apps: catalog([built])))
        let item = try #require(await engine.scan().allItems.first { $0.id.hasPrefix("xcode.appBuild.") })
        let report = await engine.clean([CleanupSelection(item: item, action: item.defaultAction)])
        #expect(report.failed.isEmpty)
        #expect(report.entries.first?.outcome == .movedToTrash(bytes: item.sizeBytes))
        #expect(report.estimatedFreedBytes == 0)
        #expect(report.trashedItems.count == 1)
        #expect(!fixture.exists(build))
        #expect(fixture.exists("Projects/Example/Sources/App.swift"))
        #expect(fixture.exists("Applications/Example.app"))
        #expect(PutBack.restore(report.trashedItems).failures.isEmpty)
        #expect(fixture.exists(build))
    }

    @Test func appOrBuildStartedAfterScanAndNeverCleanAreRespected() async throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        let processes = FakeProcessInspector()
        let engine = CleanupEngine(env: fixture.environment(processes: processes, apps: catalog([built])))
        let item = try #require(await engine.scan().allItems.first { $0.id.hasPrefix("xcode.appBuild.") })
        let selection = CleanupSelection(item: item, action: item.defaultAction)
        processes.set(ProcessSnapshot(runningAppBundleIDs: [bundleID.lowercased()], runningAppPaths: [bundleID.lowercased(): [canonical(built)]]))
        let opened = await engine.clean([selection])
        #expect(opened.skipped.count == 1)
        processes.set(ProcessSnapshot(executableNames: ["swift-frontend"]))
        #expect(await engine.clean([selection]).skipped.count == 1)
        processes.set(.empty)
        var never = NeverCleanList()
        never.folders = [built]
        _ = await engine.clean([selection], neverClean: never)
        #expect(fixture.exists(build))
    }

    @Test func changedBundleOrSymlinkAfterScanIsNotTrashed() async throws {
        let fixture = try Fixture()
        let built = try app(fixture, build)
        let engine = CleanupEngine(env: fixture.environment(apps: catalog([built])))
        let item = try #require(await engine.scan().allItems.first { $0.id.hasPrefix("xcode.appBuild.") })
        let selection = CleanupSelection(item: item, action: item.defaultAction)
        try app(fixture, build, id: "com.other.App")
        #expect(await engine.clean([selection]).failed.count == 1)
        try FileManager.default.removeItem(at: built)
        let installed = try app(fixture, "Applications/Example.app")
        try fixture.symlink(build, to: installed)
        #expect(await engine.clean([selection]).failed.count == 1)
        #expect(fixture.exists("Applications/Example.app"))
    }
}
