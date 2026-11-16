import Foundation
import Observation
import SwiftUI

/// Drives Disk Usage: the whole-disk overview, then any folder the user opens.
@Observable
@MainActor
final class DiskUsageViewModel {
    enum Phase { case start, measuring, ready }

    private(set) var phase: Phase = .start
    /// The folders opened so far; empty means the overview.
    private(set) var path: [URL] = []
    /// Measured contents, by folder path.
    private(set) var listings: [String: [UsageEntry]] = [:]
    /// Folders still being measured.
    private(set) var measuringFolders: Set<String> = []

    private let measurer: any DiskUsageMeasuring
    let home: URL
    let applications: URL
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(home: URL, applications: URL, measurer: any DiskUsageMeasuring) {
        self.measurer = measurer
        self.home = home
        self.applications = applications
    }

    isolated deinit { tasks.values.forEach { $0.cancel() } }

    /// Key for the overview listing (home folder contents plus Applications).
    static let overviewKey = "overview"

    var currentKey: String { path.last?.path ?? Self.overviewKey }
    var currentEntries: [UsageEntry] {
        (listings[currentKey] ?? []).sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }
    }
    var isMeasuringCurrent: Bool { measuringFolders.contains(currentKey) }

    var overviewEntries: [UsageEntry] { listings[Self.overviewKey] ?? [] }
    var applicationsBytes: Int64 { overviewEntries.first { $0.url == applications }?.bytes ?? 0 }
    var homeBytes: Int64 { overviewEntries.filter { $0.url != applications }.reduce(0) { $0 + ($1.bytes ?? 0) } }
    var hasUnreadableParts: Bool { (listings[currentKey] ?? []).contains(where: \.hasUnreadableParts) }

    // MARK: Actions

    func start() {
        withAnimation(AppTheme.Motion.quick) { phase = .measuring }
        measure(home, key: Self.overviewKey, adding: [UsageEntry(url: applications, isDirectory: true)])
    }

    func rescan() {
        cancel()
        listings = [:]
        path = []
        start()
    }

    func open(_ entry: UsageEntry) {
        guard entry.isDirectory else { return }
        withAnimation(AppTheme.Motion.quick) { path.append(entry.url) }
        if listings[entry.url.path] == nil {
            measure(entry.url, key: entry.url.path)
        }
    }

    /// Goes back to the overview (`index` nil) or to the folder at `index` in the path.
    func goBack(to index: Int?) {
        let kept = index.map { Array(path.prefix($0 + 1)) } ?? []
        // Folders left before they finished stop measuring (four tree walks each, competing with
        // the folder now shown) and are measured afresh if opened again.
        for url in path.dropFirst(kept.count) where measuringFolders.contains(url.path) {
            tasks[url.path]?.cancel()
            tasks[url.path] = nil
            measuringFolders.remove(url.path)
            listings[url.path] = nil
        }
        withAnimation(AppTheme.Motion.quick) { path = kept }
    }

    func cancel() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        measuringFolders = []
    }

    func resetForNavigation() {
        cancel()
        listings = [:]
        path = []
        phase = .start
    }

    /// Older drill-down listings are rebuildable. Keep the current view, overview
    /// and work in progress so background trimming never discards a measurement.
    func releaseInactiveListings() {
        let retained = measuringFolders.union([Self.overviewKey, currentKey])
        listings = listings.filter { retained.contains($0.key) }
    }

    /// Lists `folder` (after `extra`) and measures every entry, both off the main actor.
    private func measure(_ folder: URL, key: String, adding extra: [UsageEntry] = []) {
        guard tasks[key] == nil else { return }
        listings[key] = extra
        measuringFolders.insert(key)
        tasks[key] = Task { [weak self, measurer] in
            let entries = await measurer.entries(in: folder, adding: extra)
            guard !Task.isCancelled else { return }
            self?.listings[key] = entries
            let pending = PendingSizes(entries)
            await measurer.measure(entries) { [weak self] measured in
                await MainActor.run { [weak self] in
                    // A cancelled pass (Measure Again) must not write into the new listing.
                    guard !Task.isCancelled else { return }
                    pending.add(measured)
                    if pending.isDue { self?.apply(pending, to: key) }
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.apply(pending, to: key)
            self.measuringFolders.remove(key)
            self.tasks[key] = nil
            if key == Self.overviewKey { withAnimation(AppTheme.Motion.quick) { self.phase = .ready } }
        }
    }

    /// Writes the sizes measured since the last update into the listing, as one change.
    private func apply(_ pending: PendingSizes, to key: String) {
        let measured = pending.take()
        guard !measured.isEmpty, var listing = listings[key] else { return }
        for entry in measured {
            guard let index = pending.positions[entry.id], listing.indices.contains(index),
                  listing[index].id == entry.id else { continue }
            listing[index] = entry
        }
        withAnimation(AppTheme.Motion.standard) { listings[key] = listing }
    }
}


/// Sizes measured but not shown yet. Updating per entry copied, re-sorted and redrew a folder's
/// whole list once for each of its items; batching updates it a few times a second instead.
private final class PendingSizes {
    /// Where each entry sits in the listing.
    let positions: [String: Int]
    private var measured: [UsageEntry] = []
    private var lastTaken = ContinuousClock.now

    init(_ entries: [UsageEntry]) {
        positions = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var isDue: Bool { ContinuousClock.now - lastTaken >= .milliseconds(150) }

    func add(_ entry: UsageEntry) {
        measured.append(entry)
    }

    func take() -> [UsageEntry] {
        defer {
            measured = []
            lastTaken = .now
        }
        return measured
    }
}
