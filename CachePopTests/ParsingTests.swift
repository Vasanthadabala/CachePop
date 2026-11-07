import Foundation
import Testing
@testable import CachePop

@Suite("Sizes and tool output")
struct ParsingTests {
    @Test func sizerCountsNestedFilesAndPackageContents() throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/a/one", bytes: 50_000)
        try fixture.file("Library/Caches/a/deep/two", bytes: 50_000)
        try fixture.file("Library/Caches/a/Thing.app/Contents/MacOS/binary", bytes: 50_000)

        let info = DirectorySizer.size(of: fixture.url("Library/Caches/a"))
        #expect(info.fileCount == 3)
        #expect(info.bytes >= 150_000)
    }

    @Test func sizerCountsHardLinksOnceAndIgnoresSymlinks() throws {
        let fixture = try Fixture()
        let original = try fixture.file(".npm/original", bytes: 100_000)
        try FileManager.default.linkItem(at: original, to: fixture.url(".npm/hardlink"))
        let big = try fixture.file("Documents/big", bytes: 500_000)
        try fixture.symlink(".npm/symlink", to: big)

        let info = DirectorySizer.size(of: fixture.url(".npm"))
        #expect(info.fileCount == 1)
        #expect(info.bytes < 200_000)
        #expect(info.hasSharedFiles)
    }

    @Test func sizerOfMissingFolderIsZero() throws {
        let fixture = try Fixture()
        #expect(DirectorySizer.size(of: fixture.url("nope")) == .zero)
    }

    @Test func parsesSimctlDevices() throws {
        let json = FakeSimctl.devicesJSON([
            FakeDevice(udid: "A", name: "iPhone 16", state: "Booted", size: 42),
            FakeDevice(udid: "B", name: "Old iPad", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-0", available: false)
        ])
        let devices = try SimulatorControl.parseDevices(Data(json.utf8))

        let iphone = try #require(devices.first { $0.udid == "A" })
        #expect(iphone.isBooted)
        #expect(iphone.dataPathSize == 42)
        #expect(iphone.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")

        let ipad = try #require(devices.first { $0.udid == "B" })
        #expect(!ipad.available)
        #expect(!ipad.isBooted)
    }

    @Test func parsesRealSimctlRuntimeListShape() throws {
        // Trimmed from `xcrun simctl runtime list -j` on Xcode 27.
        let json = """
        {
          "563DF7AF-005D-4486-9C37-152E2649573B" : {
            "build" : "24A434", "deletable" : true,
            "identifier" : "563DF7AF-005D-4486-9C37-152E2649573B",
            "kind" : "Patchable Cryptex Disk Image",
            "lastUsedAt" : "2026-11-05T13:13:53Z",
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "sizeBytes" : 8067000161, "state" : "Ready", "version" : "27.0"
          }
        }
        """
        let images = try SimulatorControl.parseRuntimeImages(Data(json.utf8))
        #expect(images.count == 1)
        #expect(images[0].sizeBytes == 8_067_000_161)
        #expect(images[0].deletable == true)
    }

    @Test func runtimeNames() {
        #expect(SimulatorControl.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-27-0") == "iOS 27.0")
        #expect(SimulatorControl.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-11-2") == "watchOS 11.2")
        #expect(SimulatorControl.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-2-0") == "visionOS 2.0")
    }

    @Test func homebrewDryRunSummary() {
        let output = """
        Would remove: /Users/me/Library/Caches/Homebrew/node--21.1.0 (25.3MB)
        ==> This operation would free approximately 1.5GB of disk space.
        """
        #expect(HomebrewOutput.reclaimableBytes(fromDryRun: output) == Int64(1.5 * 1_073_741_824))
    }

    @Test func homebrewDryRunWithoutSummaryAddsLines() {
        let output = """
        Would remove: /a (1MB)
        Would remove: /b (512KB)
        """
        #expect(HomebrewOutput.reclaimableBytes(fromDryRun: output) == 1_048_576 + 524_288)
        #expect(HomebrewOutput.reclaimableBytes(fromDryRun: "") == 0)
    }

    @Test func derivedDataProjectNames() {
        #expect(XcodeScanner.projectName("CachePop-aszqbgiyscwhnvbbvpxkjsuycqlx") == "CachePop")
        #expect(XcodeScanner.projectName("My-App-gfhcqbxyzwvutsrqponmlkjihgfe") == "My-App")
        #expect(XcodeScanner.projectName("ModuleCache.noindex") == "ModuleCache.noindex")
    }

    @Test func gradleDaemonAndBuildToolsAreRecognised() {
        var snapshot = ProcessSnapshot()
        #expect(snapshot.runningBuildTool == nil)
        #expect(!snapshot.isGradleDaemonRunning)

        snapshot.executableNames = ["swift-frontend", "Finder"]
        snapshot.commandLines = ["/usr/bin/java -cp gradle-launcher.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.10"]
        #expect(snapshot.runningBuildTool == "swift-frontend")
        #expect(snapshot.isGradleDaemonRunning)
    }

    @Test func appCacheOwnershipMatchesOpenApps() {
        let snapshot = ProcessSnapshot(
            runningAppBundleIDs: ["com.spotify.client", "com.tinyspeck.slackmacgap", "org.mozilla.firefox"],
            runningAppNames: ["com.spotify.client": "Spotify", "com.tinyspeck.slackmacgap": "Slack", "org.mozilla.firefox": "Firefox"]
        )

        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.spotify.client", processes: snapshot) == "Spotify")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.tinyspeck.slackmacgap.ShipIt", processes: snapshot) == "Slack")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Firefox", processes: snapshot) == "Firefox")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.example.closed", processes: snapshot) == nil)
    }
}

@Suite("Open-app detection for caches")
struct AppCacheOwnershipTests {
    private func snapshot(_ apps: [String: String]) -> ProcessSnapshot {
        ProcessSnapshot(runningAppBundleIDs: Set(apps.keys), runningAppNames: apps)
    }

    @Test func recognisesBrowsersWhoseCacheFoldersDontMatchTheirIDs() {
        let browsers = snapshot([
            "com.brave.browser": "Brave Browser",
            "com.microsoft.edgemac": "Microsoft Edge",
            "com.google.chrome": "Google Chrome",
            "company.thebrowser.browser": "Arc",
            "org.mozilla.firefox": "Firefox",
            "com.vivaldi.vivaldi": "Vivaldi"
        ])

        #expect(AppCacheOwnership.runningOwner(ofFolder: "BraveSoftware", processes: browsers) == "Brave Browser")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Microsoft Edge", processes: browsers) == "Microsoft Edge")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Google", processes: browsers) == "Google Chrome")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.google.Chrome", processes: browsers) == "Google Chrome")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "company.thebrowser.Browser", processes: browsers) == "Arc")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Arc", processes: browsers) == "Arc")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Firefox", processes: browsers) == "Firefox")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.vivaldi.Vivaldi", processes: browsers) == "Vivaldi")
    }

    @Test func closedBrowsersAreNotProtected() {
        let onlyChrome = snapshot(["com.google.chrome": "Google Chrome"])

        #expect(AppCacheOwnership.runningOwner(ofFolder: "BraveSoftware", processes: onlyChrome) == nil)
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Microsoft Edge", processes: onlyChrome) == nil)
    }

    @Test func unrelatedCachesAreNotSkippedBecauseOfSystemAgents() {
        let systemAgents = snapshot([
            "com.apple.controlcenter": "Control Center",
            "com.apple.windowmanager": "WindowManager",
            "com.apple.dock": "Dock",
            "com.apple.textinputmenuagent": "TextInputMenuAgent",
            "com.example.other": "Other"
        ])

        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.spotify.client", processes: systemAgents) == nil)
        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.example.closed", processes: systemAgents) == nil)
        #expect(AppCacheOwnership.runningOwner(ofFolder: "JNA", processes: systemAgents) == nil)
    }

    @Test func helperFoldersBelongToTheirApp() {
        let slack = snapshot(["com.tinyspeck.slackmacgap": "Slack"])

        #expect(AppCacheOwnership.runningOwner(ofFolder: "com.tinyspeck.slackmacgap.ShipIt", processes: slack) == "Slack")
        #expect(AppCacheOwnership.runningOwner(ofFolder: "Slack", processes: slack) == "Slack")
    }

    @Test func openBraveCacheIsLeftAloneAtScanAndCleanTime() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/data_1", bytes: 60_000)
        try fixture.file("Library/Caches/com.example.closed/cache.db", bytes: 40_000)
        let brave = snapshot(["com.brave.browser": "Brave Browser"])
        let processes = FakeProcessInspector(brave)
        let engine = CleanupEngine(env: fixture.environment(processes: processes))

        let result = await engine.scan()
        let caches = try #require(result.item("general.appCaches"))
        #expect(caches.defaultAction.operation.paths == [canonical(fixture.url("Library/Caches/com.example.closed"))])
        #expect(result.groups.first { $0.kind == .general }?.notes.first?.contains("Brave Browser") == true)

        _ = await engine.clean([.init(item: caches, action: caches.defaultAction)])
        #expect(fixture.exists("Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/data_1"))
        #expect(!fixture.exists("Library/Caches/com.example.closed/cache.db"))
    }
}
