import Darwin
import Foundation
import Observation
import os
import Testing
@testable import CachePop

@Suite("Full resource audit", .serialized)
struct FullResourceAuditTests {
    @Test func metadataReadsHaveABudgetAndSupportBinaryPropertyLists() throws {
        let fixture = try Fixture()
        let oversized = try fixture.file("metadata.json", bytes: MetadataReader.maximumBytes + 1)
        #expect(MetadataReader.data(from: oversized) == nil)
        let small = try fixture.file("small.ini", bytes: 64)
        #expect(MetadataReader.data(from: small, limit: 64)?.count == 64)
        #expect(MetadataReader.data(from: small, limit: 63) == nil)
        let plist = fixture.url("agent.plist")
        try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.audit"], format: .binary, options: 0).write(to: plist)
        #expect(MetadataReader.propertyList(from: plist)?["Label"] as? String == "com.example.audit")
    }

    @Test func metadataReadersRejectNamedPipesAndDirectories() throws {
        let fixture = try Fixture()
        let pipe = fixture.url("workspace.json")
        try #require(mkfifo(pipe.path, 0o600) == 0)
        #expect(MetadataReader.data(from: pipe) == nil, "A configuration named pipe must not block a scan.")
        #expect(MetadataReader.data(from: fixture.home) == nil)
    }

    @Test func cancelledLogAndProjectScansDoNotKeepReading() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Logs/old.log", bytes: 4_096, modified: daysAgo(100))
        let folder = try fixture.dir("Library/Application Support/Code/User/workspaceStorage/a")
        try Data("{\"folder\":\"file:///missing-cachepop-audit-project\"}".utf8)
            .write(to: folder.appendingPathComponent("workspace.json"))
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            let logs = OldFiles.find(in: fixture.url("Library/Logs"), before: Date())
            let projects = ProjectLeftoversScanner.workspaceStorage(home: fixture.home, editorFolder: "Code")
            return (logs.files.count, projects.count, MetadataReader.data(from: folder.appendingPathComponent("workspace.json")))
        }
        task.cancel()
        let result = await task.value
        #expect(result.0 == 0 && result.1 == 0 && result.2 == nil)
    }

    @Test func diskOverviewDoesNotListTheSameApplicationsFolderTwice() throws {
        let fixture = try Fixture()
        let applications = try fixture.dir("Applications")
        try fixture.dir("Documents")
        let entries = DiskUsageScanner.entries(in: fixture.home, adding: [.init(url: applications, isDirectory: true)])
        #expect(entries.filter { $0.url == applications }.count == 1)
        #expect(Set(entries.map(\.id)).count == entries.count)
    }

    @Test func arbitraryFileExtensionsCannotGrowTheCacheWithoutBound() {
        FileKind.clearCache()
        defer { FileKind.clearCache() }
        for index in 0..<(FileKind.maximumCachedExtensions * 2 + 1) {
            _ = FileKind.of(URL(fileURLWithPath: "/tmp/a.cachepopaudit\(index)"))
        }
        #expect(FileKind.cachedExtensionCount <= FileKind.maximumCachedExtensions)
        #expect(FileKind.of(URL(fileURLWithPath: "/tmp/a.dmg")) == .diskImages)
        #expect(FileKind.of(URL(fileURLWithPath: "/tmp/a.zip")) == .archives)
    }

    @MainActor
    @Test func aReplacementFileIsKeptEvenWhenItsSizeAndModificationDateMatch() async throws {
        let fixture = try Fixture()
        let file = try fixture.file("reviewed.bin", bytes: 64)
        let identity = try #require(FileReviewIdentity.read(file))
        let date = try #require(file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let replacement = try fixture.file("replacement.bin", bytes: 64)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: replacement.path)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: replacement, to: file)
        let outcome = await FileActionService.shared.moveToTrash(paths: [file.path], reviewed: [file.path: identity])
        #expect(outcome.itemsRemoved == 0 && outcome.bytesFreed == 0)
        #expect(outcome.errors.first?.changedSinceScan == true)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func inPlaceEditsAndSymlinkReplacementsInvalidateAReview() async throws {
        let fixture = try Fixture()
        let file = try fixture.file("reviewed.bin", bytes: 64)
        let identity = try #require(FileReviewIdentity.read(file))
        try await Task.sleep(for: .milliseconds(5))
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data(repeating: 0x42, count: 64))
        try handle.close()
        #expect(!identity.matches(file))
        let updated = try #require(FileReviewIdentity.read(file))
        let target = try fixture.file("new.bin", bytes: 64)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(!updated.matches(file))
    }

    @Test func scansCarryTheReviewedIdentityIntoFileAndPhotoResults() throws {
        let fixture = try Fixture()
        let file = try fixture.file("Downloads/photo.jpg", bytes: 4_096)
        let result = LargeFilesScanner.scan(roots: [fixture.url("Downloads")], largeThreshold: 1)
        let found = try #require(result.largeFiles.first)
        #expect(found.identity?.matches(file) == true)
        let candidate = PhotoScanner.Candidate(location: .file(file), name: "photo.jpg", date: nil,
                                               pixelWidth: 1_000, pixelHeight: 1_000, bytes: 4_096,
                                               isFavorite: false, identity: found.identity)
        let photo = PhotoScanner.photo(candidate, metrics: PhotoMetrics(sharpness: 100, brightness: 0.5, shadows: 0, highlights: 0))
        #expect(photo.identity == found.identity)
    }

    @Test func hardLinksAreNotReportedAsExtraDuplicateCopies() throws {
        let fixture = try Fixture()
        let original = try fixture.file("Downloads/original.bin", bytes: 1_500_000)
        try FileManager.default.linkItem(at: original, to: fixture.url("Downloads/link.bin"))
        var result = LargeFilesScanner.scan(roots: [fixture.url("Downloads")])
        #expect(result.duplicates.isEmpty)
        try FileManager.default.copyItem(at: original, to: fixture.url("Downloads/copy.bin"))
        result = LargeFilesScanner.scan(roots: [fixture.url("Downloads")])
        #expect(result.duplicates.count == 1)
        #expect(result.duplicates.first?.files.count == 2)
    }

    @Test func putBackRefreshesOnlyTheFilesItActuallyRestored() async throws {
        let fixture = try Fixture()
        let file = try fixture.file("reviewed.jpg", bytes: 64)
        let original = try #require(FileReviewIdentity.read(file))
        let photo = AnalyzedPhoto(id: "file:" + file.path, location: .file(file), name: "reviewed.jpg", date: nil,
                                  pixelWidth: 1_000, pixelHeight: 1_000, bytes: 64, isFavorite: false,
                                  metrics: PhotoMetrics(sharpness: 0, brightness: 0.5, shadows: 0, highlights: 0),
                                  issue: .blurry, identity: original)
        let trashed = fixture.userTrash.appendingPathComponent("reviewed.jpg")
        try await Task.sleep(for: .milliseconds(5))
        try FileManager.default.moveItem(at: file, to: trashed)
        let restored = await PutBack.restoreInBackground([TrashedItem(original: file, trashed: trashed)])
        #expect(restored.failures.isEmpty)
        #expect(restored.identities[file.path]?.matches(file) == true)
        var result = PhotoScanResult(issues: [.blurry: [photo]])
        result.refreshRestoredIdentities(restored.identities)
        #expect(result.issues[.blurry]?.first?.identity?.matches(file) == true)
    }

    @MainActor
    @Test func unchangedSensorPeaksDoNotInvalidateObservers() {
        let monitor = SystemMonitorViewModel()
        monitor.apply(SystemSnapshot(temperatures: .from([("CPU", 40)])))
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = monitor.sensorMaximums
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        monitor.apply(SystemSnapshot(temperatures: .from([("CPU", 40)])))
        monitor.apply(SystemSnapshot(temperatures: .from([("CPU", 35)])))
        #expect(changes.withLock { $0 } == 0)
        monitor.apply(SystemSnapshot(temperatures: .from([("CPU", 50)])))
        #expect(changes.withLock { $0 } == 1)
    }

    @MainActor
    final class GatedFans: FanControlling {
        var status: FanHelperStatus = .ready
        var onHelperRestarted: () -> Void = {}
        var releaseCount = 0
        var replies: [CheckedContinuation<Void, Never>] = []
        func install() throws {}
        func uninstall() async throws {}
        func openApprovalSettings() {}
        func setSpeed(fan: Int, rpm: Double) async throws {}
        func setAllAutomatic() async throws {
            releaseCount += 1
            await withCheckedContinuation { replies.append($0) }
        }
        func finish() {
            let pending = replies
            replies = []
            pending.forEach { $0.resume() }
        }
    }

    @MainActor
    @Test func frequentHeatReadingsShareOnePendingSafetyRelease() async {
        let controller = GatedFans()
        let control = FanControlViewModel(controller: controller)
        await control.apply([FanSample(index: 0, rpm: 1_800, minimum: 1_200, maximum: 5_800)])
        #expect(control.mode == .custom)
        let checks = (0..<40).map { _ in Task { await control.checkSafety(temperatures: TemperatureSample(chipMax: 98), thermalState: .nominal) } }
        for _ in 0..<100 { await Task.yield() }
        #expect(controller.releaseCount == 1, "A slow helper must not accumulate one request per temperature reading.")
        controller.finish()
        for check in checks { await check.value }
        #expect(control.mode == .automatic)
    }
}
