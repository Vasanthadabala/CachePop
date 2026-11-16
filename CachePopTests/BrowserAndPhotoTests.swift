import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CachePop

@Suite("Browser history and cookies")
struct BrowserDataTests {
    private let chrome = "Library/Application Support/Google/Chrome"

    @Test func chromeProfilesGiveOneHistoryAndOneCookiesRow() async throws {
        let fixture = try Fixture()
        try fixture.file("\(chrome)/Default/Preferences", bytes: 100)
        let history = try fixture.file("\(chrome)/Default/History", bytes: 40_000)
        let visited = try fixture.file("\(chrome)/Default/Visited Links", bytes: 5_000)
        let cookies = try fixture.file("\(chrome)/Default/Network/Cookies", bytes: 20_000)
        try fixture.file("\(chrome)/Default/Bookmarks", bytes: 9_000)
        try fixture.file("\(chrome)/Profile 1/Preferences", bytes: 100)
        let second = try fixture.file("\(chrome)/Profile 1/History", bytes: 30_000)
        try fixture.file("\(chrome)/Crashpad/History", bytes: 1_000)

        let group = BrowserDataScanner.scan(await fixture.context(fixture.environment()))

        let historyItem = try #require(group.item("browsers.chrome.history"))
        #expect(!historyItem.isRecommended)
        #expect(historyItem.defaultAction.regeneration == .permanent)
        #expect(historyItem.detail == "2 profiles")
        #expect(Set(historyItem.defaultAction.operation.paths) == Set([history, visited, second].map(canonical)))

        let cookieItem = try #require(group.item("browsers.chrome.cookies"))
        #expect(cookieItem.defaultAction.operation.paths == [canonical(cookies)])
        #expect(cookieItem.warning?.contains("Signs you out") == true)

        let open = ProcessSnapshot(runningAppBundleIDs: ["com.google.chrome"])
        let whileOpen = BrowserDataScanner.scan(await fixture.context(fixture.environment(), processes: open))
        #expect(whileOpen.item("browsers.chrome.history")?.isBlocked == true)
    }

    @Test func unreadableBrowserFolderAsksForFullDiskAccess() async throws {
        let fixture = try Fixture()
        try fixture.file("\(chrome)/Default/History")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.url(chrome).path)

        let group = BrowserDataScanner.scan(await fixture.context(fixture.environment()))

        let history = try #require(group.item("browsers.chrome.history"))
        #expect(history.needsFullDiskAccess)
        #expect(history.isBlocked)
    }

    @Test func safariHistoryAndCookies() async throws {
        let fixture = try Fixture()
        let history = try fixture.file("Library/Safari/History.db", bytes: 50_000)
        let wal = try fixture.file("Library/Safari/History.db-wal", bytes: 5_000)
        try fixture.file("Library/Safari/Bookmarks.plist", bytes: 5_000)
        let cookies = try fixture.file("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies", bytes: 8_000)

        let group = BrowserDataScanner.scan(await fixture.context(fixture.environment()))

        let historyItem = try #require(group.item("browsers.safari.history"))
        #expect(Set(historyItem.defaultAction.operation.paths) == Set([history, wal].map(canonical)))
        #expect(historyItem.note?.contains("iCloud") == true)
        let cookieItem = try #require(group.item("browsers.safari.cookies"))
        #expect(cookieItem.defaultAction.operation.paths == [canonical(cookies)])
    }

    @Test func firefoxHistoryIsClearedInsideItsDatabase() async throws {
        let fixture = try Fixture()
        let profile = "Library/Application Support/Firefox/Profiles/ab12.default-release"
        let places = try fixture.file("\(profile)/places.sqlite", bytes: 60_000)
        let cookies = try fixture.file("\(profile)/cookies.sqlite", bytes: 10_000)

        let group = BrowserDataScanner.scan(await fixture.context(fixture.environment()))

        let history = try #require(group.item("browsers.firefox.history.ab12.default-release"))
        guard case .command(let command) = history.defaultAction.operation else {
            Issue.record("Firefox history must be cleared with sqlite3, not deleted")
            return
        }
        #expect(command.executable.path == "/usr/bin/sqlite3")
        #expect(command.arguments.first == "-bail")
        #expect(canonical(URL(fileURLWithPath: command.arguments[1])) == canonical(places))
        let cookieItem = try #require(group.item("browsers.firefox.cookies"))
        #expect(cookieItem.defaultAction.operation.paths == [canonical(cookies)])
    }

    @Test func firefoxSQLKeepsBookmarks() async throws {
        let fixture = try Fixture()
        let database = fixture.url("places.sqlite")
        let runner = ProcessCommandRunner()
        let schema = """
        CREATE TABLE moz_origins (id INTEGER PRIMARY KEY, host TEXT);
        CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER, last_visit_date INTEGER, foreign_count INTEGER DEFAULT 0, origin_id INTEGER);
        CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER);
        CREATE TABLE moz_inputhistory (place_id INTEGER, input TEXT);
        CREATE TABLE moz_annos (id INTEGER PRIMARY KEY, place_id INTEGER);
        CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, fk INTEGER);
        INSERT INTO moz_origins VALUES (1, 'kept.example'), (2, 'visited.example');
        INSERT INTO moz_places VALUES (1, 'https://kept.example/', 5, 99, 1, 1), (2, 'https://visited.example/', 3, 99, 0, 2);
        INSERT INTO moz_bookmarks VALUES (1, 1);
        INSERT INTO moz_historyvisits VALUES (1, 1), (2, 2), (3, 2);
        INSERT INTO moz_inputhistory VALUES (2, 'vis');
        INSERT INTO moz_annos VALUES (1, 2);
        """
        let create = try await runner.run(ToolCommand(executable: BrowserDataScanner.sqlite, arguments: [database.path, schema]), timeout: 30)
        try #require(create.succeeded)

        let clear = try await runner.run(ToolCommand(executable: BrowserDataScanner.sqlite,
                                                     arguments: ["-bail", database.path, BrowserDataScanner.firefoxClearHistorySQL]), timeout: 30)
        #expect(clear.succeeded, "\(clear.failureSummary)")

        let check = try await runner.run(ToolCommand(executable: BrowserDataScanner.sqlite, arguments: [
            database.path,
            "SELECT url || ',' || visit_count FROM moz_places; SELECT count(*) FROM moz_historyvisits; SELECT count(*) FROM moz_inputhistory; SELECT count(*) FROM moz_annos; SELECT host FROM moz_origins;"
        ]), timeout: 30)
        #expect(check.stdout.split(separator: "\n") == ["https://kept.example/,0", "0", "0", "0", "kept.example"])
    }

    @Test func onlyHistoryAndCookieFilesMayBeRemoved() throws {
        let fixture = try Fixture()
        let allowed = [
            "Library/Safari/History.db", "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
            "\(chrome)/Default/History", "\(chrome)/Profile 2/Network/Cookies",
            "Library/Application Support/Firefox/Profiles/ab12.default/cookies.sqlite"
        ]
        let refused = [
            "Library/Safari/Bookmarks.plist", "\(chrome)/Default/Bookmarks", "\(chrome)/Default/Login Data",
            "\(chrome)/Local State", "Library/Application Support/Firefox/Profiles/ab12.default/places.sqlite",
            "Library/Application Support/Firefox/Profiles/ab12.default/logins.json"
        ]
        for path in allowed + refused { try fixture.file(path, bytes: 10) }

        for path in allowed {
            #expect(PathSafety.violation(for: fixture.url(path), mode: .delete, home: fixture.home) == nil, "\(path)")
        }
        for path in refused {
            #expect(PathSafety.violation(for: fixture.url(path), mode: .delete, home: fixture.home) != nil, "\(path)")
        }
    }

    @Test func clearingChromeHistoryLeavesBookmarks() async throws {
        let fixture = try Fixture()
        try fixture.file("\(chrome)/Default/Preferences", bytes: 100)
        try fixture.file("\(chrome)/Default/History", bytes: 40_000)
        try fixture.file("\(chrome)/Default/Bookmarks", bytes: 9_000)
        let engine = CleanupEngine(env: fixture.environment())

        let item = try #require(await engine.scan().item("browsers.chrome.history"))
        let report = await engine.clean([.init(item: item, action: item.defaultAction)])

        #expect(report.failed.isEmpty)
        #expect(!fixture.exists("\(chrome)/Default/History"))
        #expect(fixture.exists("\(chrome)/Default/Bookmarks"))
        #expect(fixture.exists("\(chrome)/Default/Preferences"))
    }
}

@Suite("Photo analysis")
struct PhotoAnalysisTests {
    @Test func measuresSharpnessAndExposure() {
        let side = 64
        let checker = (0..<(side * side)).map { index -> UInt8 in ((index % side) / 4 + (index / side) / 4) % 2 == 0 ? 30 : 220 }
        let sharp = PhotoAnalyzer.metrics(gray: checker, width: side, height: side)
        #expect(sharp.sharpness > PhotoAnalyzer.blurrySharpness)
        #expect(PhotoAnalyzer.issue(for: sharp) == nil)

        let flat = PhotoAnalyzer.metrics(gray: [UInt8](repeating: 128, count: side * side), width: side, height: side)
        #expect(PhotoAnalyzer.issue(for: flat) == .blurry)

        let black = PhotoAnalyzer.metrics(gray: [UInt8](repeating: 4, count: side * side), width: side, height: side)
        #expect(PhotoAnalyzer.issue(for: black) == .dark, "dark is reported, not blurry")

        let white = PhotoAnalyzer.metrics(gray: [UInt8](repeating: 252, count: side * side), width: side, height: side)
        #expect(PhotoAnalyzer.issue(for: white) == .overexposed)
    }

    @Test func aSharpSubjectOnASoftBackgroundIsSharp() {
        let side = 64
        var pixels = [UInt8](repeating: 120, count: side * side)
        for y in 0..<16 { for x in 0..<16 { pixels[y * side + x] = (x + y) % 2 == 0 ? 20 : 235 } }
        #expect(PhotoAnalyzer.issue(for: PhotoAnalyzer.metrics(gray: pixels, width: side, height: side)) == nil)
    }

    @Test func similarShotsMustBeCloseInTimeAndLook() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let dates: [Date?] = [base, base.addingTimeInterval(30), base.addingTimeInterval(60), base.addingTimeInterval(3_600), nil]
        // 0, 1 and 3 look alike; 2 doesn't; 3 is an hour later; 4 has no date.
        let looks = [0, 0, 9, 0, 0]
        var builder = PhotoGroupBuilder<Int>()
        for index in dates.indices.sorted(by: { (dates[$0] ?? .distantPast) < (dates[$1] ?? .distantPast) }) {
            let photo = AnalyzedPhoto(id: String(index), location: .library(String(index)), name: String(index),
                                      date: dates[index], pixelWidth: 100, pixelHeight: 100, bytes: nil,
                                      isFavorite: false,
                                      metrics: PhotoMetrics(sharpness: 1, brightness: 0.5, shadows: 0, highlights: 0),
                                      issue: nil)
            builder.append(photo, feature: looks[index]) { $0 == $1 ? 0.1 : 1.0 }
        }
        let groups = builder.finish().similar.map { Set($0.photos.map(\.id)) }
        #expect(groups == [Set(["0", "1"])])
    }

    @Test func favouritesAndCleanShotsAreKept() {
        func photo(_ id: String, favourite: Bool = false, issue: PhotoIssue? = nil, sharpness: Double) -> AnalyzedPhoto {
            AnalyzedPhoto(id: id, location: .library(id), name: id, date: nil, pixelWidth: 100, pixelHeight: 100, bytes: nil,
                          isFavorite: favourite, metrics: PhotoMetrics(sharpness: sharpness, brightness: 0.5, shadows: 0, highlights: 0),
                          issue: issue)
        }
        let sharp = photo("sharp", sharpness: 900)
        let favourite = photo("favourite", favourite: true, sharpness: 100)
        let blurry = photo("blurry", issue: .blurry, sharpness: 2_000)
        #expect([sharp, blurry, favourite].sorted(by: PhotoScanner.isBetter).map(\.id) == ["favourite", "sharp", "blurry"])

        var result = PhotoScanResult(similar: [SimilarGroup(id: "g", photos: [sharp, blurry])], issues: [.blurry: [photo("other", issue: .blurry, sharpness: 1)]])
        #expect(result.reviewCount == 2)
        result.remove(["blurry", "other"])
        #expect(result.similar.isEmpty, "a group of one isn't a group")
        #expect(result.photos(with: .blurry).isEmpty)
    }

    @Test func onlyCameraPhotosInFoldersAreChecked() throws {
        let fixture = try Fixture()
        try writePhoto(fixture.url("Pictures/trip.jpg"), width: 800, height: 600)
        try writePhoto(fixture.url("Desktop/screenshot.png"), width: 800, height: 600, camera: false, type: .png)
        try writePhoto(fixture.url("Downloads/icon.jpg"), width: 300, height: 300)
        try writePhoto(fixture.url("Documents/app/node_modules/sample.jpg"), width: 800, height: 600)

        let candidates = PhotoScanner.fileCandidates(in: PhotoScanner.photoFolders(home: fixture.home))

        #expect(candidates.map(\.name) == ["trip.jpg"])
        #expect(candidates.first?.date == ISO8601DateFormatter().date(from: "2026-07-14T13:02:05Z").map { date in
            // EXIF dates have no time zone and are read as local time.
            date.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT(for: date)))
        })
    }

    @Test func folderScanGroupsRetakesAndFlagsBlur() async throws {
        let fixture = try Fixture()
        try writePhoto(fixture.url("Pictures/a.jpg"), width: 800, height: 600, date: "2026:07:14 13:02:05")
        try writePhoto(fixture.url("Pictures/b.jpg"), width: 800, height: 600, date: "2026:07:14 13:02:40")
        try writePhoto(fixture.url("Pictures/fog.jpg"), width: 800, height: 600, date: "2026:07:14 18:00:00", flat: true)

        let result = await PhotoScanner.scan(folders: PhotoScanner.photoFolders(home: fixture.home), includeLibrary: false) { _, _ in }

        #expect(result.analyzedCount == 3)
        #expect(result.similar.count == 1)
        #expect(Set(result.similar.first?.photos.map(\.name) ?? []) == ["a.jpg", "b.jpg"])
        #expect(result.photos(with: .blurry).map(\.name) == ["fog.jpg"])
    }

    // MARK: Helpers

    /// Writes an image with a sharp pattern (or a flat grey one), with camera EXIF unless told not to.
    private func writePhoto(_ url: URL, width: Int, height: Int, date: String = "2026:07:14 13:02:05",
                            camera: Bool = true, flat: Bool = false, type: UTType = .jpeg) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = flat ? 128 : (((x / 10) + (y / 10)) % 2 == 0 ? 25 : 230)
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = flat ? 128 : UInt8((x * 255) / width)
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        let image = try #require(pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        })
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if camera {
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"]
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: date]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }
}
