import Foundation
import Testing
@testable import CachePop

@Suite("Large files and login items")
struct LargeFilesAndLoginItemsTests {
    @Test func findsLargeFilesAndExactDuplicates() throws {
        let fixture = try Fixture()
        // Just over the 100 MB threshold, which is measured as allocated size.
        let big = try fixture.file("Movies/rehearsal.mov", bytes: Int(LargeFilesScanner.largeFileThreshold) + 4096)
        let photo = try fixture.file("Pictures/IMG_1.heic", bytes: 2_000_000)
        try fixture.dir("Desktop")
        try FileManager.default.copyItem(at: photo, to: fixture.url("Desktop/IMG_1 copy.heic"))
        // Same size, different contents: not a duplicate.
        var different = Data(repeating: 0xAB, count: 2_000_000)
        different[1_000_000] = 0x01
        try fixture.dir("Documents")
        try different.write(to: fixture.url("Documents/lookalike.heic"))

        let result = LargeFilesScanner.scan(roots: LargeFilesScanner.homeFolders(home: fixture.home))

        #expect(result.largeFiles.map { canonical($0.url) } == [canonical(big)])
        #expect(result.duplicates.count == 1)
        let set = try #require(result.duplicates.first)
        #expect(Set(set.files.map(\.name)) == ["IMG_1.heic", "IMG_1 copy.heic"])
        #expect(set.extraBytes == set.fileSize)
    }

    @Test func skipsSourceProjectsAndBuildFolders() throws {
        let fixture = try Fixture()
        try fixture.file("Documents/App/.git/HEAD", bytes: 10)
        let inProject = try fixture.file("Documents/App/assets/video.mov", bytes: 2_000_000)
        try FileManager.default.copyItem(at: inProject, to: fixture.url("Documents/App/assets/video copy.mov"))
        let inNodeModules = try fixture.file("Documents/site/node_modules/pkg/blob.bin", bytes: 2_000_000)
        try FileManager.default.copyItem(at: inNodeModules, to: fixture.url("Documents/site/node_modules/pkg/blob2.bin"))

        let result = LargeFilesScanner.scan(roots: [fixture.url("Documents")])

        #expect(result.duplicates.isEmpty)
        #expect(result.scannedFileCount == 0)
    }

    @Test func duplicateSetsKeepNewestFirst() throws {
        let fixture = try Fixture()
        let old = try fixture.file("Downloads/a.pdf", bytes: 1_500_000, modified: daysAgo(30))
        try FileManager.default.copyItem(at: old, to: fixture.url("Downloads/b.pdf"))
        try FileManager.default.setAttributes([.modificationDate: daysAgo(1)], ofItemAtPath: fixture.url("Downloads/b.pdf").path)

        let result = LargeFilesScanner.scan(roots: [fixture.url("Downloads")])

        #expect(result.duplicates.first?.files.first?.name == "b.pdf")
    }

    @Test func loginItemsListThirdPartyAgentsOnly() throws {
        let fixture = try Fixture()
        let agents = try fixture.dir("Library/LaunchAgents")
        let thirdParty: NSDictionary = ["Label": "com.example.updater", "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/updater"]]
        thirdParty.write(to: agents.appendingPathComponent("com.example.updater.plist"), atomically: true)
        let apple: NSDictionary = ["Label": "com.apple.something"]
        apple.write(to: agents.appendingPathComponent("com.apple.something.plist"), atomically: true)
        try fixture.file("Library/LaunchAgents/notes.txt", bytes: 10)

        let items = LoginItemsScanner.launchItems(in: agents, kind: .userAgent)

        #expect(items.map(\.title) == ["Example"])
        #expect(items.first?.path.hasSuffix("com.example.updater.plist") == true)
        #expect(items.first?.label == "com.example.updater")
        #expect(items.first?.appPath == "/Applications/Example.app")
        #expect(items.first?.isOn == true)
    }

    @Test func loginItemNamesFallBackToTheLabel() {
        let name = LoginItemsScanner.displayName(for: URL(fileURLWithPath: "/nonexistent.plist"), fallback: "com.google.keystone.agent")
        #expect(name == "Google Keystone Agent")
    }
}

@Suite("Application sizes")
@MainActor
struct ApplicationSizeTests {
    @Test func fullSizeIncludesLibraryFiles() {
        var app = ApplicationDetails(
            id: "/Applications/Claude.app",
            name: "Claude",
            path: "/Applications/Claude.app",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            icon: nil,
            version: "4.23",
            sizeBytes: 680_900_000,
            lastUsedDate: nil
        )
        #expect(app.totalSizeBytes == 680_900_000, "only the app until the Library is measured")

        let beforeMeasuring = app
        app.librarySizeBytes = 3_780_000_000

        #expect(app.totalSizeBytes == 4_460_900_000)
        #expect(app.formattedTotalSize == ByteSize.string(4_460_900_000))
        #expect(app != beforeMeasuring, "rows must refresh when the Library size arrives")
    }
}
