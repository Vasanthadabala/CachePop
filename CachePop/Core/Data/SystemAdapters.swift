import AppKit
import Darwin
import Foundation

/// Runs a tool with `Process`, draining stdout and stderr concurrently so large outputs
/// (simctl's JSON can be hundreds of kilobytes) never fill the pipe and deadlock.
nonisolated struct ProcessCommandRunner: CommandRunning {
    /// Terminates the tool when the waiting task is cancelled (a scan the user cancelled)
    /// instead of letting it run on to its timeout. Throws `CancellationError` then.
    var stopsWhenCancelled = false
    /// A malformed or noisy tool must not grow the app without bound.
    var maximumOutputBytes = 16 * 1_024 * 1_024

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
        let outputLimit = max(1, maximumOutputBytes)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                func execute() throws -> CommandOutput {
                    guard timeout.isFinite, timeout > 0 else { throw CommandError.timedOut }
                    let process = Process()
                    let deadline = DispatchTime.now() + timeout
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
                    let finished = DispatchSemaphore(value: 0)
                    process.terminationHandler = { _ in finished.signal() }
                    defer {
                        // No readDataToEndOfFile workers remain blocked on inherited pipes.
                        try? outPipe.fileHandleForReading.close()
                        try? errPipe.fileHandleForReading.close()
                        try? outPipe.fileHandleForWriting.close()
                        try? errPipe.fileHandleForWriting.close()
                        if process.isRunning {
                            process.terminate()
                            if finished.wait(timeout: .now() + .milliseconds(200)) == .timedOut,
                               process.isRunning {
                                // This is only the child we launched, and only after SIGTERM failed.
                                kill(process.processIdentifier, SIGKILL)
                                _ = finished.wait(timeout: .now() + .seconds(1))
                            }
                        }
                    }
                    guard !running.wasStopped else { throw CancellationError() }
                    do { try process.run() }
                    catch { throw CommandError.launchFailed(error.localizedDescription) }
                    running.started(process)
                    try? outPipe.fileHandleForWriting.close()
                    try? errPipe.fileHandleForWriting.close()
                    return try Self.collect(
                        process: process, stdout: outPipe.fileHandleForReading.fileDescriptor,
                        stderr: errPipe.fileHandleForReading.fileDescriptor, deadline: deadline,
                        finished: finished, running: running, outputLimit: outputLimit
                    )
                }
                // Finish closing pipes and reaping the child before callers can launch another.
                continuation.resume(with: Result { try execute() })
            }
        }
    }

    /// One bounded reader owns both nonblocking descriptors. Closing them on return
    /// releases all reader resources even if a grandchild keeps its pipe ends open.
    private static func collect(
        process: Process, stdout: Int32, stderr: Int32, deadline: DispatchTime,
        finished: DispatchSemaphore, running: RunningProcess, outputLimit: Int
    ) throws -> CommandOutput {
        var streams = [pollfd(fd: stdout, events: Int16(POLLIN), revents: 0),
                       pollfd(fd: stderr, events: Int16(POLLIN), revents: 0)]
        for stream in streams {
            let flags = fcntl(stream.fd, F_GETFL)
            guard flags >= 0, fcntl(stream.fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                throw CommandError.outputReadFailed(errno)
            }
        }
        var output = [Data(), Data()]
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if running.wasStopped { throw CancellationError() }
            if streams.allSatisfy({ $0.fd < 0 }), !process.isRunning { break }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline.uptimeNanoseconds else { throw CommandError.timedOut }
            let wait = Int32(min(max((deadline.uptimeNanoseconds - now) / 1_000_000, 1), 100))
            if streams.allSatisfy({ $0.fd < 0 }) {
                _ = finished.wait(timeout: .now() + .milliseconds(Int(wait)))
                continue
            }
            let ready = poll(&streams, nfds_t(streams.count), wait)
            if ready < 0 {
                if errno == EINTR { continue }
                throw CommandError.outputReadFailed(errno)
            }
            for index in streams.indices where streams[index].fd >= 0 && streams[index].revents != 0 {
                let count = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(streams[index].fd, bytes.baseAddress!, bytes.count)
                }
                if count > 0 {
                    guard count <= outputLimit - output[0].count - output[1].count else {
                        throw CommandError.outputLimitExceeded
                    }
                    output[index].append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    streams[index].fd = -1
                } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    throw CommandError.outputReadFailed(errno)
                }
            }
        }
        return CommandOutput(status: process.terminationStatus,
                             stdout: String(decoding: output[0], as: UTF8.self),
                             stderr: String(decoding: output[1], as: UTF8.self))
    }

    /// The launched tool, so cancellation (from another thread) can stop it. Lock-protected.
    nonisolated private final class RunningProcess: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

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
        var wasStopped: Bool { lock.withLock { cancelled } }

        private func terminate() {
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }
}

// MARK: - Running processes


/// Reads the process list with `ps` and running apps from `NSWorkspace`.
nonisolated struct LiveProcessInspector: ProcessInspecting {
    var runner: any CommandRunning = ProcessCommandRunner()

    func snapshot() async -> ProcessSnapshot {
        var snapshot = ProcessSnapshot(executableListAvailable: false, commandLinesAvailable: false)

        let ps = URL(fileURLWithPath: "/bin/ps")
        if let names = try? await runner.run(ToolCommand(executable: ps, arguments: ["-axo", "comm="]), timeout: 10),
           names.succeeded {
            snapshot.executableListAvailable = true
            snapshot.executableNames = Set(
                names.stdout
                    .split(separator: "\n")
                    .map { URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespaces)).lastPathComponent }
            )
        }
        if let lines = try? await runner.run(ToolCommand(executable: ps, arguments: ["-axww", "-o", "args="]), timeout: 10),
           lines.succeeded {
            snapshot.commandLinesAvailable = true
            snapshot.commandLines = lines.stdout.split(separator: "\n").map(String.init)
        }

        let apps = await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app -> (String, String, String?)? in
                guard !app.isTerminated, let id = app.bundleIdentifier?.lowercased() else { return nil }
                return (id, app.localizedName ?? id, app.bundleURL?.resolvingSymlinksInPath().path)
            }
        }
        snapshot.runningAppBundleIDs = Set(apps.map(\.0))
        snapshot.runningAppNames = Dictionary(apps.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        for app in apps {
            // A missing path must keep the identifier blocked, even if another copy has a path.
            snapshot.runningAppPaths[app.0, default: []].insert(app.2 ?? "")
        }
        return snapshot
    }
}

// MARK: - Free space


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


nonisolated struct FinderTrash: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

// MARK: - Tools


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
            guard !Task.isCancelled else { return ids }
            for child in fileManager.children(of: URL(fileURLWithPath: folder)) {
                guard !Task.isCancelled else { return ids }
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
        applicationURLs(bundleID: bundleID).contains { FileManager.default.fileExists(atPath: $0.path) && !$0.path.contains("/.Trash/") }
    }

    func applicationURLs(bundleID: String) -> [URL] {
        LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL] ?? []
    }
}

// MARK: - Environment
