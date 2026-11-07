import Foundation
import AppKit
import CoreServices

struct ApplicationDetails: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String
    let icon: NSImage?
    let version: String
    /// The app bundle itself.
    let sizeBytes: Int64
    let lastUsedDate: Date?
    /// Settings, caches and support files the app keeps in ~/Library; nil until measured.
    var librarySizeBytes: Int64?

    /// What the app really takes: the bundle plus its files in your Library.
    var totalSizeBytes: Int64 { sizeBytes + (librarySizeBytes ?? 0) }

    var formattedSize: String { ByteSize.string(sizeBytes) }
    var formattedTotalSize: String { ByteSize.string(totalSizeBytes) }

    /// Apps that ship with macOS live in /System or are protected by SIP (Safari), so moving
    /// them to the Trash fails and the UI must not offer it. Apple apps installed separately —
    /// Xcode, Pages, Keynote — are ordinary apps and can be uninstalled.
    var isProtected: Bool {
        path.hasPrefix("/System/")
            || Self.systemApps.contains(bundleIdentifier.lowercased())
            || bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private static let systemApps: Set<String> = ["com.apple.safari"]

    /// An app's display name without invisible formatting characters: WhatsApp's starts with a
    /// left-to-right mark, which breaks sorting and file-name matching. nil if nothing is left.
    nonisolated static func cleanName(_ name: String) -> String? {
        let visible = String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return visible.isEmpty ? nil : visible
    }

    /// Running copies of this very bundle. Another copy with the same identifier (Xcode next to
    /// Xcode-beta) doesn't count, so uninstalling one never quits or waits for the other.
    var runningInstances: [NSRunningApplication] {
        guard !bundleIdentifier.isEmpty else { return [] }
        let bundlePath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { instance in
            // No location, an iPhone app run from inside its wrapper, or a quarantined copy
            // macOS runs from a temporary mount: count it.
            guard let url = instance.bundleURL else { return true }
            let runningPath = url.resolvingSymlinksInPath().path
            return runningPath == bundlePath || runningPath.hasPrefix(bundlePath + "/")
                || runningPath.contains("/AppTranslocation/")
        }
    }

    var isRunning: Bool { !runningInstances.isEmpty }

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

    /// Includes the sizes so rows refresh when the Library measurement arrives.
    static func == (lhs: ApplicationDetails, rhs: ApplicationDetails) -> Bool {
        lhs.id == rhs.id && lhs.sizeBytes == rhs.sizeBytes && lhs.librarySizeBytes == rhs.librarySizeBytes
    }
}

struct ApplicationRelatedFile: Identifiable, Equatable {
    let id: String
    let path: String
    let sizeBytes: Int64
    /// e.g. "Preferences", "Caches", "Application Support"
    let category: String
    /// False when macOS kept CachePop from measuring it (no Full Disk Access).
    var isReadable = true

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
    /// The app itself couldn't be moved to the Trash, so nothing was removed.
    case appNotMoved(String, detail: String)

    var errorDescription: String? {
        switch self {
        case .appIsProtected(let name):
            "\(name) is a protected system application and can't be uninstalled."
        case .appIsRunning(let name):
            "\(name) is still running. Quit it first, then try again."
        case .appNotMoved(let name, let detail):
            "\(name) couldn't be moved to the Trash, so its files in your Library were kept too. \(detail)"
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
            let fileManager = FileManager.default
            let appDirectories = [
                "/Applications",
                "/Applications/Utilities",
                "\(NSHomeDirectory())/Applications"
            ]

            // De-duplicate by path in case directories overlap.
            var seen = Set<String>()
            var paths: [String] = []
            for directory in appDirectories {
                guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
                for entry in entries where entry.hasSuffix(".app") {
                    let fullPath = "\(directory)/\(entry)"
                    if seen.insert(fullPath).inserted { paths.append(fullPath) }
                }
            }

            // Sizing a bundle walks every file in it, so a few are measured at once: one huge
            // app (Xcode) no longer holds up all the others.
            let width = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            let apps = await withTaskGroup(of: ApplicationDetails?.self, returning: [ApplicationDetails].self) { group in
                var next = 0
                func addNext() {
                    guard next < paths.count else { return }
                    let path = paths[next]
                    next += 1
                    group.addTask { self.extractAppDetails(at: path) }
                }
                for _ in 0..<width { addNext() }
                var found: [ApplicationDetails] = []
                for await app in group {
                    if let app { found.append(app) }
                    addNext()
                }
                return found
            }

            // Order by footprint; ties by path, so the list keeps its order from scan to scan.
            return apps.sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.path < $1.path }
        }.value
    }

    /// Reads one app's details. Runs off the main thread; the pool frees the walk's file URLs
    /// and the full-size icon after each app instead of at the end of the whole scan.
    nonisolated private func extractAppDetails(at path: String) -> ApplicationDetails? {
        autoreleasepool { () -> ApplicationDetails? in
            let url = URL(fileURLWithPath: path)
            guard let bundle = Bundle(url: url),
                  let infoDictionary = bundle.infoDictionary else {
                return nil
            }

            let rawName = (infoDictionary["CFBundleDisplayName"] as? String) ??
                          (infoDictionary["CFBundleName"] as? String) ??
                          url.deletingPathExtension().lastPathComponent
            let name = ApplicationDetails.cleanName(rawName) ?? url.deletingPathExtension().lastPathComponent

            let bundleIdentifier = bundle.bundleIdentifier ?? ""
            let version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? "Unknown"
            let sizeBytes = (try? FileActionService.calculateSize(at: url, isDirectory: true)) ?? 0

            let lastUsedDate = Self.lastUsedDate(of: url)

            // Drawn once here, off the main thread, at the largest size the screen shows (52 pt).
            let icon = IconCache.thumbnail(of: NSWorkspace.shared.icon(forFile: path), points: 64)

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
    }

    /// Spotlight's "last opened" date, which is what Finder shows. File access dates are often
    /// missing or zero (1970), so they're only a fallback, and implausible dates are dropped.
    nonisolated static func lastUsedDate(of url: URL) -> Date? {
        let earliestPlausible = Date(timeIntervalSince1970: 978_307_200) // 2001
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date,
           date > earliestPlausible {
            return date
        }
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        return [values?.contentAccessDate, values?.contentModificationDate]
            .compactMap { $0 }
            .first { $0 > earliestPlausible }
    }

    /// The app's files in ~/Library, measured. `installedBundleIDs` (lowercased) keeps files of
    /// other installed apps out, e.g. Chrome Canary's when uninstalling Chrome.
    func findRelatedFiles(for app: ApplicationDetails, installedBundleIDs: Set<String>? = nil,
                          priority: TaskPriority = .userInitiated) async -> [ApplicationRelatedFile] {
        await Task.detached(priority: priority) {
            let others = (installedBundleIDs ?? LiveAppCatalog().installedBundleIDs())
                .subtracting([app.bundleIdentifier.lowercased()])
            let candidates = AppLeftovers.candidates(
                bundleID: app.bundleIdentifier, name: app.name,
                home: URL(fileURLWithPath: NSHomeDirectory()), otherBundleIDs: others
            )
            return candidates.map { candidate in
                let size = DirectorySizer.size(of: candidate.url)
                return ApplicationRelatedFile(
                    id: candidate.url.path, path: candidate.url.path, sizeBytes: size.bytes,
                    category: candidate.category,
                    // Browser profiles and other apps' data can be closed to CachePop without
                    // Full Disk Access; say so rather than show 0 KB.
                    isReadable: !(size.hasUnreadableParts && size.bytes == 0)
                )
            }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        }.value
    }

    /// Quits the app if it's running, so its bundle can be trashed cleanly.
    /// Returns true once no running instance remains.
    @MainActor
    func quitIfRunning(_ app: ApplicationDetails) async -> Bool {
        // Only this copy: another one with the same identifier keeps running.
        let running = app.runningInstances
        guard !running.isEmpty else { return true }

        for instance in running {
            instance.terminate()
        }

        // Give the app a moment to shut down before reporting back.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(300))
            if !app.isRunning {
                return true
            }
        }

        return !app.isRunning
    }

    /// Moves the app bundle and the chosen leftover files to the Trash.
    ///
    /// Nothing is permanently deleted — everything goes to the Trash so the user can restore it.
    /// The app goes first: if it can't be moved it's still installed and still needs its
    /// settings, so the leftovers are left alone and the error is thrown.
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

        let bundleResult = await FileActionService.shared.moveToTrash(paths: [app.path])
        if let error = bundleResult.errors.first {
            let detail: String
            if case .failed(_, let message) = error {
                detail = message
            } else if case .notFound = error {
                detail = "It's no longer where it was. Scan again."
            } else {
                detail = "macOS didn't allow it. Try dragging it to the Trash in Finder."
            }
            throw UninstallError.appNotMoved(app.name, detail: detail)
        }

        let leftoverPaths = relatedFiles.map(\.path)
        let leftoverResult = await FileActionService.shared.moveToTrash(paths: leftoverPaths)

        // Quitting an app often tidies its own caches and saved state away: already gone
        // isn't a failure.
        let failedPaths = leftoverResult.errors
            .filter {
                if case .notFound = $0 { return false }
                return true
            }
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
