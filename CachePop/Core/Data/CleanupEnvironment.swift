import AppKit
import Darwin
import Foundation

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
