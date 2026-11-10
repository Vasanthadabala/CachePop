import AppKit
import Foundation

// Everything the cleaner needs from the outside world goes through these small protocols,
// so tests can run the real scanners and cleaners against a temporary folder with fake tools
// instead of the Mac's own data.

// MARK: - Commands

nonisolated struct CommandOutput: Sendable, Equatable {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }

    /// The most useful line to show a person when the command fails.
    var failureSummary: String {
        let text = stderr.isEmpty ? stdout : stderr
        let line = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return line ?? "Exited with status \(status)."
    }
}

nonisolated enum CommandError: Error, Equatable {
    case launchFailed(String)
    case timedOut
}

nonisolated protocol CommandRunning: Sendable {
    func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput
}

/// Runs a tool with `Process`, draining stdout and stderr concurrently so large outputs
/// (simctl's JSON can be hundreds of kilobytes) never fill the pipe and deadlock.
nonisolated struct ProcessCommandRunner: CommandRunning {
    /// Terminates the tool when the waiting task is cancelled (a scan the user cancelled)
    /// instead of letting it run on to its timeout. Throws `CancellationError` then.
    var stopsWhenCancelled = false

    func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
        let running = RunningProcess()
        let stopsWhenCancelled = stopsWhenCancelled
        return try await withTaskCancellationHandler {
            try await launch(command, timeout: timeout, running: running)
        } onCancel: {
            if stopsWhenCancelled { running.stop() }
        }
    }

    private func launch(_ command: ToolCommand, timeout: TimeInterval, running: RunningProcess) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = command.executable
                process.arguments = command.arguments
                if !command.environment.isEmpty {
                    process.environment = ProcessInfo.processInfo.environment
                        .merging(command.environment) { _, new in new }
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                // Set before launch: a tool that exits at once could otherwise finish before the
                // handler exists, and the wait below would always run to the timeout.
                let finished = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in finished.signal() }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                    return
                }
                running.started(process)

                let group = DispatchGroup()
                let outData = DataBox()
                let errData = DataBox()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    outData.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errData.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                if finished.wait(timeout: .now() + timeout) == .timedOut {
                    process.terminate()
                    continuation.resume(throwing: CommandError.timedOut)
                    return
                }
                group.wait()

                if running.wasStopped {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(returning: CommandOutput(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData.data, as: UTF8.self),
                    stderr: String(decoding: errData.data, as: UTF8.self)
                ))
            }
        }
    }

    /// Each pipe is written by exactly one reader before `group.wait()` returns.
    nonisolated private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// The launched tool, so cancellation (from another thread) can stop it. Lock-protected.
    nonisolated private final class RunningProcess: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false
        private var stopped = false

        /// Records the launched tool, stopping it at once if cancellation came first.
        func started(_ process: Process) {
            lock.withLock {
                self.process = process
                if cancelled { terminate() }
            }
        }

        func stop() {
            lock.withLock {
                cancelled = true
                terminate()
            }
        }

        /// True when the tool was terminated because of cancellation.
        var wasStopped: Bool { lock.withLock { stopped } }

        private func terminate() {
            guard let process, process.isRunning else { return }
            stopped = true
            process.terminate()
        }
    }
}

// MARK: - Running processes

/// What's running right now — used to skip anything in use.
nonisolated struct ProcessSnapshot: Sendable, Equatable {
    /// Executable names (last path component), e.g. "swift-frontend".
    var executableNames: Set<String> = []
    /// Full command lines, for spotting JVM-hosted tools such as the Gradle daemon.
    var commandLines: [String] = []
    /// Bundle identifiers of running apps, lowercased.
    var runningAppBundleIDs: Set<String> = []
    /// Display names of running apps, keyed by lowercased bundle identifier.
    var runningAppNames: [String: String] = [:]

    static let empty = ProcessSnapshot()

    /// Executables that only run while something is being compiled or linked.
    static let buildToolNames: Set<String> = [
        "xcodebuild", "swift-frontend", "swift-build", "swift-driver",
        "clang", "ld", "actool", "ibtool", "XCBBuildService-worker"
    ]

    var runningBuildTool: String? {
        Self.buildToolNames.sorted().first { executableNames.contains($0) }
    }

    var isGradleDaemonRunning: Bool {
        commandLines.contains { $0.contains("GradleDaemon") || $0.contains("org.gradle.launcher.daemon") }
    }
}

nonisolated protocol ProcessInspecting: Sendable {
    func snapshot() async -> ProcessSnapshot
}

/// Reads the process list with `ps` and running apps from `NSWorkspace`.
nonisolated struct LiveProcessInspector: ProcessInspecting {
    var runner: any CommandRunning = ProcessCommandRunner()

    func snapshot() async -> ProcessSnapshot {
        var snapshot = ProcessSnapshot()

        let ps = URL(fileURLWithPath: "/bin/ps")
        if let names = try? await runner.run(ToolCommand(executable: ps, arguments: ["-axo", "comm="]), timeout: 10),
           names.succeeded {
            snapshot.executableNames = Set(
                names.stdout
                    .split(separator: "\n")
                    .map { URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespaces)).lastPathComponent }
            )
        }
        if let lines = try? await runner.run(ToolCommand(executable: ps, arguments: ["-axww", "-o", "args="]), timeout: 10),
           lines.succeeded {
            snapshot.commandLines = lines.stdout.split(separator: "\n").map(String.init)
        }

        let apps = await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier?.lowercased() else { return nil }
                return (id, app.localizedName ?? id)
            }
        }
        snapshot.runningAppBundleIDs = Set(apps.map(\.0))
        snapshot.runningAppNames = Dictionary(apps, uniquingKeysWith: { first, _ in first })
        return snapshot
    }
}

// MARK: - Free space

nonisolated protocol SpaceMeasuring: Sendable {
    /// Bytes available for important usage on the volume holding the home folder.
    func availableBytes() -> Int64?
    /// Space macOS counts as available but still holds, such as Time Machine snapshots.
    func purgeableBytes() -> Int64?
}

extension SpaceMeasuring {
    func purgeableBytes() -> Int64? { nil }
}

/// Reads `volumeAvailableCapacityForImportantUsage` — the figure Finder and Storage settings
/// use. `du`-style sums double-count APFS clones (simulators especially), so the cleaner
/// reports the change in this number as the real amount freed.
nonisolated struct VolumeSpaceMeter: SpaceMeasuring {
    let volumeURL: URL

    func availableBytes() -> Int64? {
        // Resource values are cached per URL instance; a fresh URL forces a new read.
        let url = URL(fileURLWithPath: volumeURL.path)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Available for important usage minus what's free outright.
    func purgeableBytes() -> Int64? {
        let url = URL(fileURLWithPath: volumeURL.path)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]),
              let important = values.volumeAvailableCapacityForImportantUsage,
              let free = values.volumeAvailableCapacity else { return nil }
        return max(important - Int64(free), 0)
    }
}

// MARK: - Trash

nonisolated protocol TrashMoving: Sendable {
    /// Moves `url` to the Trash and returns where it landed, when known.
    func moveToTrash(_ url: URL) throws -> URL?
}

nonisolated struct FinderTrash: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

// MARK: - Tools

/// Where the command-line tools live on this Mac, or nil when they're missing.
nonisolated struct ToolPaths: Sendable, Equatable {
    var simctl: URL?
    var brew: URL?
    var docker: URL?

    static let none = ToolPaths()
}

nonisolated protocol ToolLocating: Sendable {
    func locate() async -> ToolPaths
}

/// Finds `simctl` inside the selected Xcode instead of going through `/usr/bin/xcrun`, which
/// pops up the "install developer tools" dialog on Macs without Xcode.
nonisolated struct LiveToolLocator: ToolLocating {
    var runner: any CommandRunning = ProcessCommandRunner()

    func locate() async -> ToolPaths {
        var paths = ToolPaths()

        let xcodeSelect = ToolCommand(executable: URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"])
        if let output = try? await runner.run(xcodeSelect, timeout: 10), output.succeeded {
            let developerDir = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let simctl = URL(fileURLWithPath: developerDir).appendingPathComponent("usr/bin/simctl")
            if FileManager.default.isExecutableFile(atPath: simctl.path) {
                paths.simctl = simctl
            }
        }

        for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            paths.brew = URL(fileURLWithPath: candidate)
            break
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker", "\(home)/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker", "\(home)/.orbstack/bin/docker"
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            paths.docker = URL(fileURLWithPath: candidate)
            break
        }

        return paths
    }
}

// MARK: - Installed apps

/// Which apps are on this Mac, so leftovers of deleted apps can be told apart.
nonisolated protocol AppCataloging: Sendable {
    /// Lowercased bundle identifiers of the apps in the usual app folders.
    func installedBundleIDs() -> Set<String>
    /// Whether macOS knows an app with this identifier anywhere, including other folders and disks.
    func isKnown(bundleID: String) -> Bool
}

nonisolated struct LiveAppCatalog: AppCataloging {
    func installedBundleIDs() -> Set<String> {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let folders = [
            "/Applications", "/Applications/Utilities", "/System/Applications",
            "/System/Applications/Utilities", "/System/Library/CoreServices", "\(home)/Applications"
        ]
        var ids = Set<String>()
        func add(_ url: URL) {
            if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id.lowercased()) }
        }
        for folder in folders {
            for child in fileManager.children(of: URL(fileURLWithPath: folder)) {
                if child.pathExtension == "app" {
                    add(child)
                } else if fileManager.isDirectory(child) {
                    // One level of subfolders: "Setapp", "JetBrains Toolbox", vendor suites.
                    for nested in fileManager.children(of: child) where nested.pathExtension == "app" {
                        add(nested)
                    }
                }
            }
        }
        return ids
    }

    func isKnown(bundleID: String) -> Bool {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL] else {
            return false
        }
        return urls.contains { FileManager.default.fileExists(atPath: $0.path) && !$0.path.contains("/.Trash/") }
    }
}

// MARK: - Environment

/// Everything a scan or clean touches. `.live` is the real Mac; tests build their own.
nonisolated struct CleanupEnvironment: Sendable {
    /// The user's home folder. Every path the cleaner touches is derived from this.
    var home: URL
    var commands: any CommandRunning
    var processes: any ProcessInspecting
    var tools: any ToolLocating
    var space: any SpaceMeasuring
    var trash: any TrashMoving
    var apps: any AppCataloging = LiveAppCatalog()
    var now: @Sendable () -> Date = { Date() }
    /// How long to wait for APFS to hand back freed space before measuring.
    var settleTimeout: TimeInterval = 6
    var settleInterval: TimeInterval = 0.5

    static var live: CleanupEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // A cancelled scan stops its tools (brew's dry run can take a minute); the engine runs
        // clean commands in their own task, so Stop never kills one half way.
        let runner = ProcessCommandRunner(stopsWhenCancelled: true)
        return CleanupEnvironment(
            home: home,
            commands: runner,
            processes: LiveProcessInspector(runner: runner),
            tools: LiveToolLocator(runner: runner),
            space: VolumeSpaceMeter(volumeURL: home),
            trash: FinderTrash()
        )
    }

    func path(_ relative: String) -> URL {
        home.appendingPathComponent(relative, isDirectory: true)
    }
}
