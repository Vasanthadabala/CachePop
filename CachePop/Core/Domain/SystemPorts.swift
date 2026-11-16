import Foundation

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
    case outputLimitExceeded
    case outputReadFailed(Int32)
}


nonisolated protocol CommandRunning: Sendable {
    func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput
}


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
    /// Unknown process state must not be treated as an idle Mac during a clean.
    var executableListAvailable = true
    var commandLinesAvailable = true

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


nonisolated protocol SpaceMeasuring: Sendable {
    /// Bytes available for important usage on the volume holding the home folder.
    func availableBytes() -> Int64?
    /// Space macOS counts as available but still holds, such as Time Machine snapshots.
    func purgeableBytes() -> Int64?
}


nonisolated extension SpaceMeasuring {
    func purgeableBytes() -> Int64? { nil }
}


nonisolated protocol TrashMoving: Sendable {
    /// Moves `url` to the Trash and returns where it landed, when known.
    func moveToTrash(_ url: URL) throws -> URL?
}


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


/// Which apps are on this Mac, so leftovers of deleted apps can be told apart.
nonisolated protocol AppCataloging: Sendable {
    /// Lowercased bundle identifiers of the apps in the usual app folders.
    func installedBundleIDs() -> Set<String>
    /// Whether macOS knows an app with this identifier anywhere, including other folders and disks.
    func isKnown(bundleID: String) -> Bool
}
