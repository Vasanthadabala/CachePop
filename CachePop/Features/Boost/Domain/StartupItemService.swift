import AppKit
import Foundation

/// What CachePop is able to do about a given startup item, based on where it lives.
enum StartupItemRemovability {
    /// A launch agent inside the user's own `~/Library/LaunchAgents` — safe to unload and trash.
    case removable
    /// A running third-party background app with no user-owned plist — can be asked to quit.
    case quittable
    /// Lives in `/Library/LaunchAgents` or `/Library/LaunchDaemons`; changing it needs root,
    /// which CachePop deliberately does not request.
    case requiresAdmin

    var actionTitle: String {
        switch self {
        case .removable:     "Remove"
        case .quittable:     "Quit"
        case .requiresAdmin: "Locked"
        }
    }

    var explanation: String {
        switch self {
        case .removable:
            "Will be disabled and moved to the Trash."
        case .quittable:
            "Running app — will be asked to quit. It may relaunch at next login."
        case .requiresAdmin:
            "System-level item. Needs administrator rights, so CachePop won't change it."
        }
    }
}

struct StartupItemRemovalResult {
    var removedCount = 0
    var quitCount = 0
    var skippedAdminCount = 0
    var failedPaths: [String] = []

    var totalHandled: Int { removedCount + quitCount }
    var hasFailures: Bool { !failedPaths.isEmpty }

    var summary: String {
        var parts: [String] = []
        if removedCount > 0 {
            parts.append("\(removedCount) startup item\(removedCount == 1 ? "" : "s") disabled")
        }
        if quitCount > 0 {
            parts.append("\(quitCount) background app\(quitCount == 1 ? "" : "s") quit")
        }
        if parts.isEmpty {
            return "Nothing was changed."
        }
        return parts.joined(separator: " · ")
    }
}

enum StartupItemService {
    private static var userLaunchAgentsPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .path
    }

    static func removability(for item: CareScanDetailItem) -> StartupItemRemovability {
        let path = item.path

        if path.hasPrefix(userLaunchAgentsPath) && path.hasSuffix(".plist") {
            return .removable
        }

        if path.hasPrefix("/Library/LaunchAgents") || path.hasPrefix("/Library/LaunchDaemons") {
            return .requiresAdmin
        }

        // Running background apps are recorded with their bundle path rather than a plist.
        if path.hasSuffix(".app") || !path.hasSuffix(".plist") {
            return .quittable
        }

        return .requiresAdmin
    }

    static func canAct(on item: CareScanDetailItem) -> Bool {
        removability(for: item) != .requiresAdmin
    }

    /// Disables the given startup items.
    ///
    /// User launch agents are unloaded with `launchctl` and then moved to the Trash, so they
    /// neither run now nor come back at the next login. Running background apps are asked to
    /// quit. System-level items are skipped — CachePop never escalates to root.
    static func remove(items: [CareScanDetailItem]) async -> StartupItemRemovalResult {
        var result = StartupItemRemovalResult()
        var plistPathsToTrash: [String] = []

        for item in items {
            switch removability(for: item) {
            case .removable:
                unloadLaunchAgent(at: item.path)
                plistPathsToTrash.append(item.path)

            case .quittable:
                if await quitApp(at: item.path, named: item.title) {
                    result.quitCount += 1
                } else {
                    result.failedPaths.append(item.path)
                }

            case .requiresAdmin:
                result.skippedAdminCount += 1
            }
        }

        if !plistPathsToTrash.isEmpty {
            let trashResult = await FileActionService.shared.moveToTrash(paths: plistPathsToTrash)
            result.removedCount = trashResult.itemsRemoved
            result.failedPaths.append(contentsOf: trashResult.errors.map(\.path).filter { !$0.isEmpty })
        }

        return result
    }

    /// Best-effort `launchctl unload` so the agent stops immediately rather than at next login.
    /// A failure here is not fatal: trashing the plist still prevents it from loading again.
    private static func unloadLaunchAgent(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // launchctl is unavailable or refused; the Trash move below is still effective.
        }
    }

    @MainActor
    private static func quitApp(at path: String, named name: String) async -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            if let bundlePath = app.bundleURL?.path, bundlePath == path {
                return true
            }
            return app.localizedName == name || app.bundleIdentifier == path
        }

        guard !running.isEmpty else { return false }

        for app in running {
            app.terminate()
        }

        // Allow a moment for a graceful shutdown, then confirm it actually exited before
        // reporting success — some apps refuse or prompt to save.
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(250))
            if running.allSatisfy(\.isTerminated) {
                return true
            }
        }

        return running.allSatisfy(\.isTerminated)
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
