import Foundation
import AppKit

struct ApplicationDetails: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String
    let icon: NSImage?
    let version: String
    let sizeBytes: Int64
    let lastUsedDate: Date?
    var relatedFiles: [ApplicationRelatedFile] = []

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    /// Apple-supplied and system-located apps can't be removed by moving files to the Trash —
    /// they're protected by SIP — so the UI must not offer to uninstall them.
    var isProtected: Bool {
        bundleIdentifier.lowercased().hasPrefix("com.apple.")
            || path.hasPrefix("/System/")
            || bundleIdentifier == Bundle.main.bundleIdentifier
    }

    var isRunning: Bool {
        guard !bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var lastUsedText: String {
        guard let lastUsedDate else { return "Unknown" }
        let days = Calendar.current.dateComponents([.day], from: lastUsedDate, to: Date()).day ?? 0
        switch days {
        case ..<1:   return "Today"
        case 1:      return "Yesterday"
        case 2..<30: return "\(days) days ago"
        case 30..<365:
            let months = days / 30
            return months == 1 ? "1 month ago" : "\(months) months ago"
        default:
            let years = days / 365
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
    }

    /// Apps untouched for 60+ days are surfaced as uninstall candidates.
    var isUnused: Bool {
        guard let lastUsedDate, !isProtected else { return false }
        let days = Calendar.current.dateComponents([.day], from: lastUsedDate, to: Date()).day ?? 0
        return days >= 60
    }

    static func == (lhs: ApplicationDetails, rhs: ApplicationDetails) -> Bool {
        lhs.id == rhs.id
    }
}

struct ApplicationRelatedFile: Identifiable, Equatable {
    let id: String
    let path: String
    let sizeBytes: Int64
    /// e.g. "Preferences", "Caches", "Application Support"
    let category: String

    var name: String { URL(fileURLWithPath: path).lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static func == (lhs: ApplicationRelatedFile, rhs: ApplicationRelatedFile) -> Bool {
        lhs.id == rhs.id
    }
}

enum UninstallError: LocalizedError {
    case appIsProtected(String)
    case appIsRunning(String)

    var errorDescription: String? {
        switch self {
        case .appIsProtected(let name):
            "\(name) is a protected system application and can't be uninstalled."
        case .appIsRunning(let name):
            "\(name) is still running. Quit it first, then try again."
        }
    }
}

struct UninstallResult {
    let app: ApplicationDetails
    let bytesFreed: Int64
    let filesRemoved: Int
    let failedPaths: [String]

    var formattedBytesFreed: String {
        ByteCountFormatter.string(fromByteCount: bytesFreed, countStyle: .file)
    }
}

final class AppUninstallerEngine: Sendable {
    static let shared = AppUninstallerEngine()

    private init() {}

    func scanApplications() async -> [ApplicationDetails] {
        await Task.detached(priority: .userInitiated) {
            var apps: [ApplicationDetails] = []
            let fileManager = FileManager.default
            let appDirectories = [
                "/Applications",
                "/Applications/Utilities",
                "\(NSHomeDirectory())/Applications"
            ]

            for directory in appDirectories {
                guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }

                for entry in entries where entry.hasSuffix(".app") {
                    let fullPath = "\(directory)/\(entry)"
                    if let appDetails = self.extractAppDetails(at: fullPath) {
                        apps.append(appDetails)
                    }
                }
            }

            // De-duplicate by path in case directories overlap, then order by footprint.
            var seen = Set<String>()
            return apps
                .filter { seen.insert($0.path).inserted }
                .sorted { $0.sizeBytes > $1.sizeBytes }
        }.value
    }

    private func extractAppDetails(at path: String) -> ApplicationDetails? {
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url),
              let infoDictionary = bundle.infoDictionary else {
            return nil
        }

        let name = (infoDictionary["CFBundleDisplayName"] as? String) ??
                   (infoDictionary["CFBundleName"] as? String) ??
                   url.deletingPathExtension().lastPathComponent

        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        let version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let sizeBytes = (try? FileActionService.calculateSize(at: url, isDirectory: true)) ?? 0

        var lastUsedDate: Date?
        if let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey]) {
            lastUsedDate = values.contentAccessDate ?? values.contentModificationDate
        }

        let icon = NSWorkspace.shared.icon(forFile: path)

        return ApplicationDetails(
            id: path,
            name: name,
            path: path,
            bundleIdentifier: bundleIdentifier,
            icon: icon,
            version: version,
            sizeBytes: sizeBytes,
            lastUsedDate: lastUsedDate
        )
    }

    func findRelatedFiles(for app: ApplicationDetails) async -> [ApplicationRelatedFile] {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let home = NSHomeDirectory()
            var relatedFiles: [ApplicationRelatedFile] = []

            var candidates: [(String, String)] = []

            if !app.bundleIdentifier.isEmpty {
                candidates += [
                    ("\(home)/Library/Application Support/\(app.bundleIdentifier)", "Application Support"),
                    ("\(home)/Library/Caches/\(app.bundleIdentifier)", "Caches"),
                    ("\(home)/Library/Preferences/\(app.bundleIdentifier).plist", "Preferences"),
                    ("\(home)/Library/Saved Application State/\(app.bundleIdentifier).savedState", "Saved State"),
                    ("\(home)/Library/Containers/\(app.bundleIdentifier)", "Containers"),
                    ("\(home)/Library/Group Containers/\(app.bundleIdentifier)", "Group Containers"),
                    ("\(home)/Library/HTTPStorages/\(app.bundleIdentifier)", "HTTP Storage"),
                    ("\(home)/Library/WebKit/\(app.bundleIdentifier)", "WebKit Data"),
                    ("\(home)/Library/Logs/\(app.bundleIdentifier)", "Logs"),
                    ("\(home)/Library/LaunchAgents/\(app.bundleIdentifier).plist", "Login Item")
                ]
            }

            candidates += [
                ("\(home)/Library/Application Support/\(app.name)", "Application Support"),
                ("\(home)/Library/Caches/\(app.name)", "Caches"),
                ("\(home)/Library/Logs/\(app.name)", "Logs")
            ]

            var seenPaths = Set<String>()
            for (path, category) in candidates {
                guard seenPaths.insert(path).inserted else { continue }

                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { continue }

                let size = (try? FileActionService.calculateSize(
                    at: URL(fileURLWithPath: path),
                    isDirectory: isDir.boolValue
                )) ?? 0

                relatedFiles.append(ApplicationRelatedFile(id: path, path: path, sizeBytes: size, category: category))
            }

            return relatedFiles.sorted { $0.sizeBytes > $1.sizeBytes }
        }.value
    }

    /// Quits the app if it's running, so its bundle can be trashed cleanly.
    /// Returns true once no running instance remains.
    @MainActor
    func quitIfRunning(_ app: ApplicationDetails) async -> Bool {
        guard !app.bundleIdentifier.isEmpty else { return true }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        guard !running.isEmpty else { return true }

        for instance in running {
            instance.terminate()
        }

        // Give the app a moment to shut down before reporting back.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(300))
            if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty {
                return true
            }
        }

        return NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    /// Moves the app bundle and the chosen leftover files to the Trash.
    ///
    /// Nothing is permanently deleted — everything goes to the Trash so the user can restore it.
    func uninstall(
        app: ApplicationDetails,
        removing relatedFiles: [ApplicationRelatedFile]
    ) async throws -> UninstallResult {
        guard !app.isProtected else {
            throw UninstallError.appIsProtected(app.name)
        }

        guard !app.isRunning else {
            throw UninstallError.appIsRunning(app.name)
        }

        // Leftovers first: if the bundle move fails we haven't orphaned support files
        // for an app that is still installed.
        let leftoverPaths = relatedFiles.map(\.path)
        let leftoverResult = await FileActionService.shared.moveToTrash(paths: leftoverPaths)
        let bundleResult = await FileActionService.shared.moveToTrash(paths: [app.path])

        let failedPaths = (leftoverResult.errors + bundleResult.errors)
            .map(\.path)
            .filter { !$0.isEmpty }

        return UninstallResult(
            app: app,
            bytesFreed: leftoverResult.bytesFreed + bundleResult.bytesFreed,
            filesRemoved: leftoverResult.itemsRemoved + bundleResult.itemsRemoved,
            failedPaths: failedPaths
        )
    }
}
