import Foundation
import Testing
@testable import CachePop

@Suite("Application scan progress")
@MainActor
struct AppScanProgressTests {
    @Test func countsEachUniqueCandidateIncludingUnreadableApps() async throws {
        let fixture = try Fixture()
        let folder = try fixture.dir("Applications")
        for index in 0..<3 {
            let plist = try fixture.file("Applications/App\(index).app/Contents/Info.plist", bytes: 0)
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleName": "App \(index)", "CFBundleIdentifier": "com.fixture.progress\(index)",
                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1"
            ], format: .xml, options: 0)
            try data.write(to: plist)
        }
        try fixture.file("Applications/Unreadable.app", bytes: 1)
        let engine = AppUninstallerEngine(home: fixture.home, appDirectories: [folder.path, folder.path])
        var progress: [Double] = []
        let apps = await engine.scanApplications { progress.append($0) }
        #expect(apps.count == 3)
        #expect(progress.first == 0 && progress.last == 1)
        #expect(progress.contains(0.25) && progress.contains(0.5) && progress.contains(0.75))
        #expect(progress == progress.sorted())
    }

    @Test func viewModelPublishesActualProgressAndDiscardsCancelledUpdates() async {
        let engine = GatedAppScan()
        let model = AppsViewModel(engine: engine, catalog: ProgressCatalog())
        model.scan()
        for _ in 0..<100 {
            if engine.progress != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.progress != nil)
        engine.progress?(0.44)
        #expect(model.isScanning && model.scanProgress == 0.44)
        model.resetForNavigation()
        engine.progress?(0.9)
        #expect(!model.isScanning && model.scanProgress == 0)
        engine.finish()
    }
}

@MainActor
private final class GatedAppScan: ApplicationManaging {
    var progress: (@MainActor @Sendable (Double) -> Void)?
    var continuation: CheckedContinuation<[ApplicationDetails], Never>?
    func scanApplications(onProgress: @escaping @MainActor @Sendable (Double) -> Void) async -> [ApplicationDetails] {
        progress = onProgress
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: []); continuation = nil }
    func findRelatedFiles(for app: ApplicationDetails, installedBundleIDs: Set<String>?, priority: TaskPriority) async -> [ApplicationRelatedFile] { [] }
    func isRunning(_ app: ApplicationDetails) -> Bool { false }
    func quitIfRunning(_ app: ApplicationDetails) async -> Bool { true }
    func uninstall(app: ApplicationDetails, removing relatedFiles: [ApplicationRelatedFile]) async throws -> UninstallResult {
        UninstallResult(app: app, bytesFreed: 0, filesRemoved: 0, failedPaths: [])
    }
}

private nonisolated struct ProgressCatalog: AppCataloging {
    func installedBundleIDs() -> Set<String> { [] }
    func isKnown(bundleID: String) -> Bool { false }
}
