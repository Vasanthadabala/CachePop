import Foundation
import AppKit
import CoreServices

final class AppUninstallerEngine: ApplicationManaging, Sendable {
    static let shared = AppUninstallerEngine()

    private let home: URL
    private let appDirectories: [String]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, appDirectories: [String]? = nil) {
        self.home = home
        self.appDirectories = appDirectories ?? ["/Applications", "/Applications/Utilities", home.appendingPathComponent("Applications").path]
    }

    func scanApplications() async -> [ApplicationDetails] {
        let work = Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default

            // De-duplicate by path in case directories overlap.
            var seen = Set<String>()
            var paths: [String] = []
            for directory in self.appDirectories {
                guard !Task.isCancelled else { return [ApplicationDetails]() }
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
                    guard !Task.isCancelled, next < paths.count else { return }
                    let path = paths[next]
                    next += 1
                    group.addTask { self.extractAppDetails(at: path) }
                }
                for _ in 0..<width { addNext() }
                var found: [ApplicationDetails] = []
                for await app in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let app { found.append(app) }
                    addNext()
                }
                return found
            }

            // Order by footprint; ties by path, so the list keeps its order from scan to scan.
            return apps.sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.path < $1.path }
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// Reads one app's details. Runs off the main thread; the pool frees the walk's file URLs
    /// and the full-size icon after each app instead of at the end of the whole scan.
    nonisolated private func extractAppDetails(at path: String) -> ApplicationDetails? {
        autoreleasepool { () -> ApplicationDetails? in
            guard !Task.isCancelled else { return nil }
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
            guard !Task.isCancelled else { return nil }

            let lastUsedDate = Self.lastUsedDate(of: url)

            // FinderIcon loads a bounded, display-sized icon only when a row appears.

            return ApplicationDetails(
                id: path,
                name: name,
                path: path,
                bundleIdentifier: bundleIdentifier,
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
        let work = Task.detached(priority: priority) {
            guard !Task.isCancelled else { return [ApplicationRelatedFile]() }
            let others = (installedBundleIDs ?? LiveAppCatalog().installedBundleIDs())
                .subtracting([app.bundleIdentifier.lowercased()])
            let candidates = AppLeftovers.candidates(
                bundleID: app.bundleIdentifier, name: app.name,
                home: self.home, otherBundleIDs: others
            )
            return candidates.compactMap { candidate -> ApplicationRelatedFile? in
                guard !Task.isCancelled else { return nil }
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
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    @MainActor
    func isRunning(_ app: ApplicationDetails) -> Bool { app.isRunning }

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
