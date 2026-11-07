import Foundation
import Testing
@testable import CachePop

@Suite("Uninstall leftovers, app names and battery health")
struct AppLeftoversTests {
    /// A throwaway home folder with the given Library entries (a trailing "/" makes a folder).
    private func home(_ entries: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leftovers-\(UUID().uuidString)", isDirectory: true)
        for entry in entries {
            let url = root.appendingPathComponent(entry)
            if entry.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("x".utf8).write(to: url)
            }
        }
        return root
    }

    private func relative(_ candidates: [AppLeftovers.Candidate], in home: URL) -> Set<String> {
        let base = home.standardizedFileURL.path + "/"
        return Set(candidates.map { $0.url.standardizedFileURL.path.replacingOccurrences(of: base, with: "") })
    }

    @Test func findsHelpersGroupContainersAndNameFolders() throws {
        let root = try home([
            "Library/Application Support/com.example.App/",
            "Library/Application Support/Example/",
            "Library/Caches/com.example.App.ShipIt/",
            "Library/Preferences/com.example.App.plist",
            "Library/Containers/com.example.App.Intents/",
            "Library/Group Containers/group.com.example.App.shared/",
            "Library/Group Containers/ABCDE12345.com.example.App.notifications/",
            // Not this app's:
            "Library/Caches/com.example.AppBeta/",
            "Library/Caches/com.example.App.Pro/",
            "Library/Group Containers/group.com.example.family/"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = AppLeftovers.candidates(bundleID: "com.example.App", name: "Example", home: root,
                                            otherBundleIDs: ["com.example.app.pro"])
        #expect(relative(found, in: root) == [
            "Library/Application Support/com.example.App",
            "Library/Application Support/Example",
            "Library/Caches/com.example.App.ShipIt",
            "Library/Preferences/com.example.App.plist",
            "Library/Containers/com.example.App.Intents",
            "Library/Group Containers/group.com.example.App.shared",
            "Library/Group Containers/ABCDE12345.com.example.App.notifications"
        ])
        #expect(found.first { $0.url.lastPathComponent == "com.example.App.ShipIt" }?.category == "Caches")
    }

    @Test func browsersFindTheirVendorFoldersButNeverTheSharedOne() throws {
        let root = try home([
            "Library/Application Support/Google/Chrome/Default/",
            "Library/Application Support/Google/GoogleUpdater/",
            "Library/Caches/Google/Chrome/",
            "Library/Application Support/Google/AndroidStudio2026.1.4/",
            "Library/Caches/Google/AndroidStudio2026.1.4/"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let chrome = relative(AppLeftovers.candidates(bundleID: "com.google.Chrome", name: "Google Chrome", home: root, otherBundleIDs: []), in: root)
        #expect(chrome == ["Library/Application Support/Google/Chrome", "Library/Caches/Google/Chrome"])

        let studio = relative(AppLeftovers.candidates(bundleID: "com.google.android.studio", name: "Android Studio", home: root, otherBundleIDs: []), in: root)
        #expect(studio == ["Library/Application Support/Google/AndroidStudio2026.1.4", "Library/Caches/Google/AndroidStudio2026.1.4"])

        // An app that happens to be called "Google" doesn't claim the shared vendor folder.
        let google = AppLeftovers.candidates(bundleID: "com.example.google", name: "Google", home: root, otherBundleIDs: [])
        #expect(google.isEmpty)
    }

    @Test func appNamesLoseInvisibleFormattingCharacters() {
        #expect(ApplicationDetails.cleanName("\u{200E}WhatsApp") == "WhatsApp")
        #expect(ApplicationDetails.cleanName(" Visual Studio Code\u{200F} ") == "Visual Studio Code")
        #expect(ApplicationDetails.cleanName("\u{200E} ") == nil)
    }

    @Test func batteryHealthComesFromSystemSettingsFigure() throws {
        let json = """
        {"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":{"sppower_battery_cycle_count":351,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"90%"}}]}
        """
        #expect(BatteryHealthReader.parse(Data(json.utf8)) == 0.9)
        #expect(BatteryHealthReader.parse(Data(#"{"SPPowerDataType":[{"_name":"AC"}]}"#.utf8)) == nil)
        #expect(BatteryHealthReader.parse(Data("not json".utf8)) == nil)
    }
}
