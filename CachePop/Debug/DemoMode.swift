#if DEBUG
import AppKit
import Foundation

/// Debug-only: run the whole app against a fixture home folder instead of the real one.
///
/// Launch with `-CachePopDemo`. CachePop builds a miniature developer Mac under the temporary
/// folder (derived data, simulators, package caches, logs, Trash…) out of real files, and a
/// scripted `simctl`/`brew` that act on those files. Cleaning really deletes fixture files and
/// really measures the volume, so the flow can be checked end to end without touching the
/// Mac's own data. Never compiled into release builds.
enum DemoMode {
    static let argument = "-CachePopDemo"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CachePopDemo", isDirectory: true)
    static var home: URL { root.appendingPathComponent("home", isDirectory: true) }

    private static var cachedEnvironment: CleanupEnvironment?

    @MainActor
    static func environmentIfRequested() -> CleanupEnvironment? {
        guard isRequested else { return nil }
        if let cachedEnvironment { return cachedEnvironment }

        try? FixtureBuilder.build(home: home)
        let environment = CleanupEnvironment(
            home: home,
            commands: DemoTools(home: home),
            processes: DemoProcesses(),
            tools: DemoToolLocator(),
            space: VolumeSpaceMeter(volumeURL: home),
            trash: DemoTrash(home: home),
            apps: DemoAppCatalog()
        )
        cachedEnvironment = environment
        return environment
    }

    /// Settings in their own defaults suite, reset on every launch, with one Never Clean folder.
    @MainActor
    static func settings() -> AppSettings {
        let suite = "CachePop.demo"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite) ?? .standard, canChangeLoginItem: false)
        settings.neverClean(folder: home.appendingPathComponent("Library/Caches/com.spotify.client"))
        return settings
    }

    /// Login Items switches that only change memory, with a few pretend Open at Login apps.
    static let startupControl = DemoStartupControl(apps: [
        OpenAtLoginApp(name: "Dropbox", path: "/Applications/Dropbox.app"),
        OpenAtLoginApp(name: "Rectangle", path: "/Applications/Rectangle.app"),
        OpenAtLoginApp(name: "Spotify", path: "/Applications/Spotify.app")
    ])

    /// A few past cleans, in memory only.
    @MainActor
    static func history() -> CleanHistory {
        let history = CleanHistory(inMemory: true)
        let now = Date()
        history.insert(CleanRecord(date: now.addingTimeInterval(-41 * 86_400), freedBytes: 6_420_000_000, wasMeasured: true,
                                   itemCount: 9, trashBytes: 0, titles: ["Derived data", "Unavailable simulators", "npm cache"]))
        history.insert(CleanRecord(date: now.addingTimeInterval(-17 * 86_400), freedBytes: 2_180_000_000, wasMeasured: true,
                                   itemCount: 6, trashBytes: 312_000_000, titles: ["iOS 26.0 runtime", "App caches", "Installers in Downloads"]))
        history.insert(CleanRecord(date: now.addingTimeInterval(-3 * 86_400), freedBytes: 845_000_000, wasMeasured: true,
                                   itemCount: 5, trashBytes: 0, titles: ["Derived data", "Xcode caches", "Old logs and crash reports"]))
        return history
    }
}

// MARK: - Fixture

nonisolated private enum FixtureBuilder {
    static let megabyte = 1_048_576

    static func build(home: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: home.path) {
            try fileManager.removeItem(at: home)
        }

        func file(_ path: String, mb: Double, daysOld: Double? = nil) throws {
            let url = home.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x5A, count: Int(mb * Double(megabyte))).write(to: url)
            if let daysOld {
                try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(-daysOld * 86_400)], ofItemAtPath: url.path)
            }
        }

        func spread(_ folder: String, totalMB: Double, files: Int) throws {
            for index in 0..<files {
                try file("\(folder)/part-\(index).bin", mb: totalMB / Double(files))
            }
        }

        // Xcode
        try spread("Library/Developer/Xcode/DerivedData/CachePop-aszqbgiyscwhnvbbvpxkjsuycqlx/Build", totalMB: 64, files: 8)
        try spread("Library/Developer/Xcode/DerivedData/Daietto-gfhcqbxyzwvutsrqponmlkjihg/Index.noindex", totalMB: 46, files: 6)
        try spread("Library/Developer/Xcode/DerivedData/ModuleCache.noindex", totalMB: 14, files: 4)
        try spread("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 26.0 (23A341)/Symbols", totalMB: 24, files: 3)
        try spread("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,1 26.1 (23B85)/Symbols", totalMB: 22, files: 3)
        try spread("Library/Caches/com.apple.dt.Xcode", totalMB: 6, files: 2)
        let archive = "Library/Developer/Xcode/Archives/2025-03-14/Daietto 14-03-2025, 10.12.xcarchive"
        try spread("\(archive)/Products/Applications/Daietto.app", totalMB: 16, files: 2)
        let archiveInfo: NSDictionary = ["Name": "Daietto", "CreationDate": Date().addingTimeInterval(-235 * 86_400)]
        archiveInfo.write(to: home.appendingPathComponent("\(archive)/Info.plist"), atomically: true)

        // Simulators
        try spread("Library/Developer/CoreSimulator/Caches/dyld", totalMB: 12, files: 2)
        for clone in 1...3 {
            try spread("Library/Developer/XCTestDevices/CLONE-\(clone)/data", totalMB: 15, files: 3)
        }
        for device in DemoTools.devices {
            try spread("Library/Developer/CoreSimulator/Devices/\(device.udid)/data", totalMB: device.megabytes, files: 3)
        }

        // Developer caches
        try spread(".npm/_cacache/content-v2", totalMB: 36, files: 6)
        try spread(".gradle/caches/modules-2", totalMB: 52, files: 6)
        try spread(".gradle/wrapper/dists/gradle-8.10-bin", totalMB: 18, files: 2)
        try spread("Library/Caches/org.swift.swiftpm/repositories", totalMB: 15, files: 3)
        try spread("Library/Caches/CocoaPods/Pods", totalMB: 8, files: 2)
        try spread("Library/Caches/Homebrew/downloads", totalMB: 11, files: 2)
        try spread(".cache/pip/http", totalMB: 5, files: 2)
        try spread(".cache/huggingface/hub", totalMB: 30, files: 2)

        // App caches, logs, installers, Trash
        try spread("Library/Caches/com.spotify.client/Data", totalMB: 26, files: 3)
        try spread("Library/Caches/com.google.Chrome/Default/Cache", totalMB: 19, files: 3)
        try spread("Library/Caches/com.tinyspeck.slackmacgap/Cache", totalMB: 12, files: 2)
        try file("Library/Logs/DiagnosticReports/Xcode-2026-09-01.ips", mb: 3, daysOld: 60)
        try file("Library/Logs/CoreSimulator/old.log", mb: 3, daysOld: 30)
        try file("Library/Logs/CoreSimulator/today.log", mb: 1, daysOld: 0)
        try file("Downloads/Figma-2026.dmg", mb: 25)
        try file("Downloads/OldTool.pkg", mb: 9)
        try file(".Trash/Screen Recording 2026-10-02.mov", mb: 14)
        try file(".Trash/export-final.zip", mb: 4)

        // Large and duplicate files (for the Large Files screen)
        try file("Movies/Keynote rehearsal.mov", mb: 140)
        try file("Downloads/Android SDK backup.zip", mb: 108)
        try file("Pictures/IMG_2041.heic", mb: 3.2)
        try fileManager.createDirectory(at: home.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: home.appendingPathComponent("Pictures/IMG_2041.heic"), to: home.appendingPathComponent("Desktop/IMG_2041 copy.heic"))
        try file("Documents/Invoices/Invoice-0412.pdf", mb: 1.6)
        try fileManager.copyItem(at: home.appendingPathComponent("Documents/Invoices/Invoice-0412.pdf"), to: home.appendingPathComponent("Downloads/Invoice-0412.pdf"))
        try fileManager.copyItem(at: home.appendingPathComponent("Documents/Invoices/Invoice-0412.pdf"), to: home.appendingPathComponent("Downloads/Invoice-0412 (1).pdf"))
        try file("Projects/App/Sources/main.swift", mb: 0.01)

        // iPhone and iPad
        let backup = "Library/Application Support/MobileSync/Backup/00008110-001A2B3C4D5E6F70"
        try spread(backup, totalMB: 38, files: 4)
        let backupInfo: NSDictionary = [
            "Device Name": "iPhone 13 mini", "Product Version": "17.6.1",
            "Last Backup Date": Date().addingTimeInterval(-290 * 86_400)
        ]
        backupInfo.write(to: home.appendingPathComponent("\(backup)/Info.plist"), atomically: true)
        try file("Library/iTunes/iPhone Software Updates/iPhone14,4_18.1_22B83_Restore.ipsw", mb: 46)

        // Leftovers of apps that are no longer installed
        try spread("Library/Application Support/com.figma.Desktop/IndexedDB", totalMB: 18, files: 3)
        try spread("Library/Containers/com.figma.Desktop/Data/Library", totalMB: 4, files: 2)
        try file("Library/Preferences/com.figma.Desktop.plist", mb: 0.01)
        try spread("Library/Application Support/com.electron.zoomus/data", totalMB: 7, files: 2)
        try file("Library/Preferences/com.sketchup.SketchUp.2021.plist", mb: 0.02)
        try file("Library/Preferences/net.whatsapp.WhatsApp.plist", mb: 0.01)
        try spread("Library/Application Support/com.spotify.client/Users", totalMB: 3, files: 1)
        for path in ["Library/Application Support/com.figma.Desktop", "Library/Containers/com.figma.Desktop",
                     "Library/Preferences/com.figma.Desktop.plist", "Library/Application Support/com.electron.zoomus",
                     "Library/Preferences/com.sketchup.SketchUp.2021.plist", "Library/Preferences/net.whatsapp.WhatsApp.plist"] {
            age(home.appendingPathComponent(path), days: 160)
        }

        // Android
        try file(".android/avd/Pixel_8_API_34.ini", mb: 0.001)
        let avd = ".android/avd/Pixel_8_API_34.avd"
        try file("\(avd)/userdata-qemu.img.qcow2", mb: 26)
        try file("\(avd)/cache.img.qcow2", mb: 4)
        try "avd.ini.displayname=Pixel 8 API 34\nimage.sysdir.1=system-images/android-34/google_apis_playstore/arm64-v8a/\n"
            .write(to: home.appendingPathComponent("\(avd)/config.ini"), atomically: true, encoding: .utf8)
        try file("Library/Android/sdk/system-images/android-34/google_apis_playstore/arm64-v8a/system.img", mb: 22)
        try file("Library/Android/sdk/system-images/android-30/google_apis/x86_64/system.img", mb: 31)
    }

    /// Back-dates a file or folder and everything in it.
    static func age(_ url: URL, days: Double) {
        let date = Date().addingTimeInterval(-days * 86_400)
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let child as URL in enumerator {
                try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: child.path)
            }
        }
        try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

nonisolated private struct DemoAppCatalog: AppCataloging {
    func installedBundleIDs() -> Set<String> {
        ["com.spotify.client", "com.google.chrome", "com.tinyspeck.slackmacgap", "com.apple.dt.xcode"]
    }

    func isKnown(bundleID: String) -> Bool { false }
}

// MARK: - Scripted tools

nonisolated private struct DemoToolLocator: ToolLocating {
    func locate() async -> ToolPaths {
        ToolPaths(simctl: DemoTools.simctl, brew: DemoTools.brew, docker: DemoTools.docker)
    }
}

nonisolated private struct DemoProcesses: ProcessInspecting {
    func snapshot() async -> ProcessSnapshot {
        ProcessSnapshot(
            runningAppBundleIDs: ["com.tinyspeck.slackmacgap"],
            runningAppNames: ["com.tinyspeck.slackmacgap": "Slack"]
        )
    }
}

nonisolated private struct DemoTrash: TrashMoving {
    let home: URL

    func moveToTrash(_ url: URL) throws -> URL? {
        let trash = home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var destination = trash.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = trash.appendingPathComponent("\(UUID().uuidString.prefix(6)) \(url.lastPathComponent)")
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

/// Answers like `simctl` and `brew`, and applies their effects to the fixture's files.
nonisolated struct DemoTools: CommandRunning {
    let home: URL

    static let simctl = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl")
    static let brew = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    static let docker = URL(fileURLWithPath: "/usr/local/bin/docker")

    nonisolated struct Device: Sendable {
        let udid: String
        let name: String
        let runtime: String
        let state: String
        let available: Bool
        let megabytes: Double
    }

    static let devices = [
        Device(udid: "E9C85F67-806B-464B-A730-5FBAE48D9CBA", name: "iPhone 16", runtime: "iOS-27-0", state: "Shutdown", available: true, megabytes: 42),
        Device(udid: "572E0B26-B22C-478A-9C1A-E3C709719022", name: "iPhone 18 Pro Max", runtime: "iOS-27-0", state: "Booted", available: true, megabytes: 24),
        Device(udid: "17683FA7-D185-4E5D-9221-AFB71BD3FD25", name: "Apple Watch SE 3 (40mm)", runtime: "watchOS-27-0", state: "Shutdown", available: true, megabytes: 18),
        Device(udid: "0B1C2D3E-4F50-6172-8394-A5B6C7D8E9F0", name: "iPhone 8", runtime: "iOS-16-0", state: "Shutdown", available: false, megabytes: 33),
        Device(udid: "1A2B3C4D-5E6F-7081-92A3-B4C5D6E7F801", name: "iPad (6th generation)", runtime: "iOS-16-0", state: "Shutdown", available: false, megabytes: 21)
    ]

    private var devicesFolder: URL { home.appendingPathComponent("Library/Developer/CoreSimulator/Devices") }

    func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
        try? await Task.sleep(for: .milliseconds(250))
        let arguments = command.arguments

        if command.executable == Self.brew {
            let downloads = home.appendingPathComponent("Library/Caches/Homebrew/downloads")
            if arguments.contains("--dry-run") {
                let megabytes = Double(DirectorySizer.size(of: downloads).bytes) / 1_048_576
                return ok(megabytes > 0 ? "==> This operation would free approximately \(String(format: "%.1f", megabytes))MB of disk space." : "")
            }
            try? FileManager.default.removeItem(at: downloads)
            return ok("Removing old downloads")
        }

        if command.executable == Self.docker {
            let pruned = home.appendingPathComponent(".demo-docker-pruned")
            if arguments.starts(with: ["system", "df"]) {
                let done = FileManager.default.fileExists(atPath: pruned.path)
                return ok("""
                {"Active":"2","Reclaimable":"\(done ? "0B" : "642.3MB (58%)")","Size":"1.1GB","TotalCount":"7","Type":"Images"}
                {"Active":"1","Reclaimable":"0B","Size":"12.1kB","TotalCount":"2","Type":"Containers"}
                {"Active":"1","Reclaimable":"0B","Size":"84MB","TotalCount":"1","Type":"Local Volumes"}
                {"Active":"0","Reclaimable":"\(done ? "0B" : "212.6MB")","Size":"212.6MB","TotalCount":"31","Type":"Build Cache"}
                """)
            }
            try? Data().write(to: pruned)
            return ok("Total reclaimed space: 212.6MB")
        }

        switch arguments {
        case ["list", "devices", "-j"]:
            return ok(devicesJSON())
        case ["--set", "testing", "list", "devices", "-j"]:
            let clones = FileManager.default.children(of: home.appendingPathComponent("Library/Developer/XCTestDevices"))
            return ok(listJSON(clones.map { ["udid": $0.lastPathComponent, "name": "Clone of iPhone 16", "state": "Shutdown", "isAvailable": true] }, runtime: "iOS-27-0"))
        case ["--set", "previews", "list", "devices", "-j"]:
            return ok(listJSON([], runtime: "iOS-27-0"))
        case ["runtime", "list", "-j"]:
            return ok(runtimesJSON())
        case ["--set", "testing", "delete", "all"]:
            for clone in FileManager.default.children(of: home.appendingPathComponent("Library/Developer/XCTestDevices")) {
                try? FileManager.default.removeItem(at: clone)
            }
            return ok("")
        case ["delete", "unavailable"]:
            for device in Self.devices where !device.available {
                try? FileManager.default.removeItem(at: devicesFolder.appendingPathComponent(device.udid))
            }
            return ok("")
        default:
            if arguments.count == 2, arguments[0] == "erase" {
                for item in FileManager.default.children(of: devicesFolder.appendingPathComponent("\(arguments[1])/data")) {
                    try? FileManager.default.removeItem(at: item)
                }
                return ok("")
            }
            if arguments.count == 2, arguments[0] == "delete" {
                try? FileManager.default.removeItem(at: devicesFolder.appendingPathComponent(arguments[1]))
                return ok("")
            }
            if arguments.starts(with: ["runtime", "delete"]) {
                try? FileManager.default.createDirectory(at: home.appendingPathComponent(".demo-runtime-deleted"), withIntermediateDirectories: true)
                return ok("")
            }
            return CommandOutput(status: 1, stdout: "", stderr: "Unknown demo command")
        }
    }

    private func ok(_ stdout: String) -> CommandOutput {
        CommandOutput(status: 0, stdout: stdout, stderr: "")
    }

    private func devicesJSON() -> String {
        var byRuntime: [String: [[String: Any]]] = [:]
        for device in Self.devices {
            let folder = devicesFolder.appendingPathComponent(device.udid)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            byRuntime["com.apple.CoreSimulator.SimRuntime.\(device.runtime)", default: []].append([
                "udid": device.udid,
                "name": device.name,
                "state": device.state,
                "isAvailable": device.available,
                "dataPath": folder.appendingPathComponent("data").path,
                "dataPathSize": DirectorySizer.size(of: folder).bytes,
                "lastUsedAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 86_400))
            ])
        }
        return json(["devices": byRuntime])
    }

    private func listJSON(_ devices: [[String: Any]], runtime: String) -> String {
        json(["devices": ["com.apple.CoreSimulator.SimRuntime.\(runtime)": devices]])
    }

    private func runtimesJSON() -> String {
        var runtimes: [String: Any] = [
            "563DF7AF-005D-4486-9C37-152E2649573B": [
                "identifier": "563DF7AF-005D-4486-9C37-152E2649573B",
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "version": "27.0", "build": "24A434", "sizeBytes": 8_067_000_161, "deletable": true,
                "lastUsedAt": "2026-11-05T13:13:53Z", "state": "Ready"
            ]
        ]
        if !FileManager.default.fileExists(atPath: home.appendingPathComponent(".demo-runtime-deleted").path) {
            runtimes["9F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"] = [
                "identifier": "9F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0",
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                "version": "26.0", "build": "23A339", "sizeBytes": 7_412_000_000, "deletable": true,
                "lastUsedAt": "2026-05-20T09:00:00Z", "state": "Ready"
            ]
        }
        return json(runtimes)
    }

    private func json(_ object: Any) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
    }
}
#endif
