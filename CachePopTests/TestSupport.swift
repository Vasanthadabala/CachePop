import Foundation
@testable import CachePop

/// A throwaway home folder in the temporary directory. Every scanner and cleaner test points
/// `CleanupEnvironment.home` here, so nothing on the real Mac is read for cleaning or removed.
final class Fixture {
    let root: URL
    let home: URL
    /// Stands in for the user's Trash when files are "moved to the Trash".
    let userTrash: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CachePopTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        userTrash = root.appendingPathComponent("moved-to-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userTrash, withIntermediateDirectories: true)
    }

    deinit {
        // Restore permissions changed by tests so the whole tree can be removed.
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }

    @discardableResult
    func file(_ relative: String, bytes: Int = 10_000, modified: Date? = nil) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    func dir(_ relative: String) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func symlink(_ relative: String, to destination: URL) throws {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relative).path)
    }

    func children(_ relative: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url(relative).path)) ?? []).sorted()
    }

    func size(_ relative: String) -> Int64 {
        DirectorySizer.size(of: url(relative)).bytes
    }
}

// MARK: - Fake tools

/// Records every command and answers from a handler, standing in for `simctl` and `brew`.
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ToolCommand] = []
    private let handler: @Sendable (ToolCommand) -> CommandOutput

    init(handler: @escaping @Sendable (ToolCommand) -> CommandOutput) {
        self.handler = handler
    }

    var calls: [ToolCommand] { lock.withLock { recorded } }

    /// Calls other than the read-only list and dry-run commands.
    var mutatingCalls: [[String]] {
        calls.map(\.arguments).filter { arguments in
            !(arguments.contains("list") || arguments.contains("--dry-run"))
        }
    }

    func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
        lock.withLock { recorded.append(command) }
        return handler(command)
    }
}

struct FakeDevice {
    var udid: String
    var name: String
    var runtime = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    var state = "Shutdown"
    var available = true
    var size: Int64 = 1_000_000

    var json: [String: Any] {
        [
            "udid": udid, "name": name, "state": state, "isAvailable": available,
            "dataPathSize": size, "lastUsedAt": "2026-10-01T10:00:00Z",
            "dataPath": "/fake/\(udid)/data"
        ]
    }
}

struct FakeRuntime {
    var identifier: String
    var runtimeIdentifier: String
    var version: String
    var size: Int64
    var deletable = true

    var json: [String: Any] {
        [
            "identifier": identifier, "runtimeIdentifier": runtimeIdentifier, "version": version,
            "build": "24A000", "sizeBytes": size, "deletable": deletable,
            "lastUsedAt": "2026-01-01T10:00:00Z", "state": "Ready"
        ]
    }
}

/// A scripted `simctl` (and optionally `brew`) with fixed devices per device set.
struct FakeSimctl {
    var devices: [FakeDevice] = []
    var testingClones: [FakeDevice] = []
    var previewDevices: [FakeDevice] = []
    var runtimes: [FakeRuntime] = []
    var brewDryRun: String?
    var failingArguments: [String]?

    static let simctlURL = URL(fileURLWithPath: "/fake/Xcode.app/Contents/Developer/usr/bin/simctl")
    static let brewURL = URL(fileURLWithPath: "/fake/homebrew/bin/brew")
    static let dockerURL = URL(fileURLWithPath: "/fake/bin/docker")

    func runner() -> FakeCommandRunner {
        let script = self
        return FakeCommandRunner { command in script.respond(to: command) }
    }

    func respond(to command: ToolCommand) -> CommandOutput {
        let arguments = command.arguments
        if let failingArguments, arguments == failingArguments {
            return CommandOutput(status: 1, stdout: "", stderr: "An error was encountered processing the command.")
        }

        if command.executable == Self.brewURL {
            if arguments.contains("--dry-run") {
                return CommandOutput(status: 0, stdout: brewDryRun ?? "", stderr: "")
            }
            return CommandOutput(status: 0, stdout: "Removing old versions", stderr: "")
        }

        if Array(arguments.suffix(3)) == ["list", "devices", "-j"] {
            let set: [FakeDevice]
            if arguments.starts(with: ["--set", "testing"]) {
                set = testingClones
            } else if arguments.starts(with: ["--set", "previews"]) {
                set = previewDevices
            } else {
                set = devices
            }
            return CommandOutput(status: 0, stdout: Self.devicesJSON(set), stderr: "")
        }

        if arguments == ["runtime", "list", "-j"] {
            let dictionary = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.identifier, $0.json) })
            return CommandOutput(status: 0, stdout: Self.jsonString(dictionary), stderr: "")
        }

        return CommandOutput(status: 0, stdout: "", stderr: "")
    }

    static func devicesJSON(_ devices: [FakeDevice]) -> String {
        var byRuntime: [String: [[String: Any]]] = [:]
        for device in devices {
            byRuntime[device.runtime, default: []].append(device.json)
        }
        return jsonString(["devices": byRuntime])
    }

    static func jsonString(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

final class FakeProcessInspector: ProcessInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var current: ProcessSnapshot

    init(_ snapshot: ProcessSnapshot = .empty) {
        current = snapshot
    }

    func set(_ snapshot: ProcessSnapshot) {
        lock.withLock { current = snapshot }
    }

    func snapshot() async -> ProcessSnapshot {
        lock.withLock { current }
    }
}

struct FakeToolLocator: ToolLocating {
    var paths: ToolPaths

    func locate() async -> ToolPaths { paths }
}

/// Returns a scripted sequence of free-space readings; the last one repeats.
final class FakeSpaceMeter: SpaceMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [Int64?]

    init(_ readings: [Int64?]) {
        self.readings = readings
    }

    func availableBytes() -> Int64? {
        lock.withLock {
            if readings.count > 1 { return readings.removeFirst() }
            return readings.first ?? nil
        }
    }
}

/// "Moves to the Trash" by moving into the fixture's own folder.
struct FixtureTrash: TrashMoving {
    let folder: URL

    /// Like the real Trash, a second item with the same name gets a new name.
    func moveToTrash(_ url: URL) throws -> URL? {
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        var copy = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(url.lastPathComponent) \(copy)")
            copy += 1
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

/// Installed apps for the leftovers scanner, instead of the Mac's own.
struct FakeAppCatalog: AppCataloging {
    var installed: Set<String> = []
    var known: Set<String> = []

    func installedBundleIDs() -> Set<String> { installed }
    func isKnown(bundleID: String) -> Bool { known.contains(bundleID.lowercased()) }
}

let fixedNow = ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z")!

func daysAgo(_ days: Double) -> Date {
    fixedNow.addingTimeInterval(-days * 86_400)
}

extension Fixture {
    func environment(
        simctl: FakeSimctl? = FakeSimctl(),
        withBrew: Bool = false,
        processes: FakeProcessInspector = FakeProcessInspector(),
        space: FakeSpaceMeter = FakeSpaceMeter([1_000, 1_000]),
        runner: FakeCommandRunner? = nil,
        apps: FakeAppCatalog = FakeAppCatalog(),
        docker: Bool = false
    ) -> CleanupEnvironment {
        let commandRunner = runner ?? (simctl ?? FakeSimctl()).runner()
        return CleanupEnvironment(
            home: home,
            commands: commandRunner,
            processes: processes,
            tools: FakeToolLocator(paths: ToolPaths(
                simctl: simctl == nil ? nil : FakeSimctl.simctlURL,
                brew: withBrew ? FakeSimctl.brewURL : nil,
                docker: docker ? FakeSimctl.dockerURL : nil
            )),
            space: space,
            trash: FixtureTrash(folder: userTrash),
            apps: apps,
            now: { fixedNow },
            settleTimeout: 0.3,
            settleInterval: 0.01
        )
    }

    func context(_ env: CleanupEnvironment, processes: ProcessSnapshot = .empty) async -> ScanContext {
        ScanContext(env: env, processes: processes, tools: await env.tools.locate())
    }
}

extension CleanupScanResult {
    func item(_ id: String) -> CleanupItem? {
        allItems.first { $0.id == id }
    }
}

extension CleanupGroup {
    func item(_ id: String) -> CleanupItem? {
        items.first { $0.id == id }
    }
}

/// Canonical path, so `/var` vs `/private/var` and trailing slashes don't matter.
func canonical(_ url: URL) -> String {
    url.resolvingSymlinksInPath().path
}

extension CleanupOperation {
    /// The paths this operation touches, canonicalised for comparison in tests.
    var paths: [String] {
        switch self {
        case .delete(let urls), .deleteContents(let urls), .moveToTrash(let urls):
            urls.map(canonical)
        case .command:
            []
        }
    }
}
