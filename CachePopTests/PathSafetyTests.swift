import Foundation
import Testing
@testable import CachePop

@Suite("Path safety")
struct PathSafetyTests {
    @Test func allowsFilesInsideCacheRoots() throws {
        let fixture = try Fixture()
        let cache = try fixture.file("Library/Caches/com.example.app/blob")
        let npm = try fixture.file(".npm/_cacache/index")
        let derived = try fixture.dir("Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyz")

        #expect(PathSafety.violation(for: cache, mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: npm, mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: derived, mode: .delete, home: fixture.home) == nil)
    }

    @Test func refusesHomeRootsAndOutsidePaths() throws {
        let fixture = try Fixture()
        let caches = try fixture.dir("Library/Caches")
        let outside = fixture.root.appendingPathComponent("elsewhere.txt")
        try Data("x".utf8).write(to: outside)

        #expect(PathSafety.violation(for: fixture.home, mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: caches, mode: .delete, home: fixture.home) != nil, "a root itself is never removed")
        #expect(PathSafety.violation(for: outside, mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: URL(fileURLWithPath: "/System/Library"), mode: .delete, home: fixture.home) != nil)
    }

    @Test func refusesProtectedPersonalData() throws {
        let fixture = try Fixture()
        let document = try fixture.file("Documents/thesis.pages")
        let mail = try fixture.file("Library/Mail/V10/inbox.mbox")
        let keychain = try fixture.file("Library/Keychains/login.keychain-db")
        let photos = try fixture.file("Library/Caches/Pictures Library.photoslibrary/database")
        let source = try fixture.file(".cache/project/.git/HEAD")

        for url in [document, mail, keychain, photos, source] {
            #expect(PathSafety.violation(for: url, mode: .delete, home: fixture.home) != nil, "\(url.path)")
            #expect(PathSafety.violation(for: url, mode: .trash, home: fixture.home) != nil, "\(url.path)")
        }
    }

    @Test func dotDotCannotEscapeACacheFolder() throws {
        let fixture = try Fixture()
        try fixture.file("Documents/keep.txt")
        try fixture.dir(".cache")
        let sneaky = fixture.url(".cache/../Documents/keep.txt")

        #expect(PathSafety.violation(for: sneaky, mode: .delete, home: fixture.home) != nil)
    }

    @Test func symlinkedParentCannotEscapeACacheFolder() throws {
        let fixture = try Fixture()
        let documents = try fixture.dir("Documents")
        try fixture.file("Documents/keep.txt")
        try fixture.symlink(".cache/linked", to: documents)

        let throughLink = fixture.url(".cache/linked/keep.txt")
        #expect(PathSafety.violation(for: throughLink, mode: .delete, home: fixture.home) != nil)

        // The link itself lives in the cache folder, and removing a link never touches its target.
        #expect(PathSafety.violation(for: fixture.url(".cache/linked"), mode: .delete, home: fixture.home) == nil)
    }

    @Test func downloadsAreTrashOnly() throws {
        let fixture = try Fixture()
        let installer = try fixture.file("Downloads/Setup.dmg")

        #expect(PathSafety.violation(for: installer, mode: .trash, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: installer, mode: .delete, home: fixture.home) != nil)
    }

    @Test func archivesAreTrashOnly() throws {
        let fixture = try Fixture()
        let archive = try fixture.dir("Library/Developer/Xcode/Archives/2025-01-01/App.xcarchive")

        #expect(PathSafety.violation(for: archive, mode: .trash, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: archive, mode: .delete, home: fixture.home) != nil)
    }

    @Test func simulatorDevicesAreOnlyRemovedThroughSimctl() throws {
        let fixture = try Fixture()
        let device = try fixture.file("Library/Developer/CoreSimulator/Devices/ABC/data/file")

        #expect(PathSafety.violation(for: device, mode: .delete, home: fixture.home) != nil)
    }
}
