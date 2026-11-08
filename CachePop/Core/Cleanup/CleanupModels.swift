import Foundation

// MARK: - Groups

/// The headings a scan's findings are grouped under, in the order they're shown.
nonisolated enum CleanupGroupKind: String, CaseIterable, Identifiable, Sendable {
    case xcode
    case simulators
    case developerCaches
    case devices
    case leftovers
    case general
    case browsers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcode:           "Xcode"
        case .simulators:      "Simulators & emulators"
        case .developerCaches: "Developer caches"
        case .devices:         "iPhone & iPad"
        case .leftovers:       "Deleted apps & projects"
        case .general:         "App caches, logs & Trash"
        case .browsers:        "Browser history & cookies"
        }
    }

    var symbolName: String {
        switch self {
        case .xcode:           "hammer"
        case .simulators:      "iphone"
        case .developerCaches: "shippingbox"
        case .devices:         "ipad.and.iphone"
        case .leftovers:       "app.dashed"
        case .general:         "archivebox"
        case .browsers:        "safari"
        }
    }

    /// What the scanner looks at, in plain words — shown while scanning and on the start screen.
    var scanDescription: String {
        switch self {
        case .xcode:           "Derived data, device support, device crash logs, Xcode caches and old archives"
        case .simulators:      "Simulators, test clones, runtimes and Android emulators"
        case .developerCaches: "npm, Gradle, SwiftPM, CocoaPods, Homebrew, Docker, local AI models and other tool caches"
        case .devices:         "Device backups and iOS update files"
        case .leftovers:       "Data and broken login items left by apps you've deleted, and coding tools' data for projects you've removed"
        case .general:         "App caches, Safari's cache, Mail attachments, old logs, installers in Downloads, Time Machine snapshots and the Trash"
        case .browsers:        "History and cookies in Safari, Chrome, Firefox, Brave, Edge, Arc and Vivaldi. Never ticked for you"
        }
    }
}

// MARK: - What happens to the data afterwards

/// Whether the data comes back on its own once it has been removed.
nonisolated enum Regeneration: Sendable, Hashable {
    /// Re-created by the tool as soon as it needs it (a cache, derived data).
    case automatic
    /// Downloaded again when needed — costs bandwidth and time, nothing is lost.
    case redownloaded
    /// Copied again from a device the next time it is connected.
    case onDeviceConnect
    /// Moved to the Trash, so it can still be put back.
    case movedToTrash
    /// Already unusable (e.g. a simulator whose runtime is gone) — nothing of value is lost.
    case unusable
    /// Gone for good.
    case permanent

    var label: String {
        switch self {
        case .automatic:       "Comes back automatically"
        case .redownloaded:    "Downloaded again when needed"
        case .onDeviceConnect: "Copied again when the device connects"
        case .movedToTrash:    "Moved to the Trash"
        case .unusable:        "Can't be used anyway"
        case .permanent:       "Doesn't come back"
        }
    }

    var symbolName: String {
        switch self {
        case .automatic:       "arrow.clockwise"
        case .redownloaded:    "arrow.down.circle"
        case .onDeviceConnect: "cable.connector"
        case .movedToTrash:    "trash"
        case .unusable:        "xmark.circle"
        case .permanent:       "exclamationmark.triangle"
        }
    }

    /// Only data that can't be recovered deserves a warning colour.
    var isLossy: Bool { self == .permanent }

    /// Moving to the Trash doesn't free space until the Trash is emptied.
    var freesSpaceNow: Bool { self != .movedToTrash }
}

// MARK: - Operations

/// A command-line tool invocation, e.g. `simctl delete unavailable`.
nonisolated struct ToolCommand: Sendable, Equatable, Hashable {
    let executable: URL
    let arguments: [String]
    var environment: [String: String] = [:]

    /// Human-readable form for logs and the confirmation sheet, e.g. `simctl delete unavailable`.
    var displayString: String {
        ([executable.lastPathComponent] + arguments).joined(separator: " ")
    }
}

/// The concrete thing the cleaner does for one item. Every file operation is checked by
/// `PathSafety` again right before it runs.
nonisolated enum CleanupOperation: Sendable, Equatable {
    /// Permanently remove these files or folders.
    case delete([URL])
    /// Permanently remove everything inside these folders, keeping the folders themselves.
    case deleteContents([URL])
    /// Move these files or folders to the Trash.
    case moveToTrash([URL])
    /// Run a command-line tool.
    case command(ToolCommand)
}

/// One way of dealing with an item. Most items have exactly one; a simulator can be
/// erased (kept, but emptied) or deleted.
nonisolated struct CleanupAction: Identifiable, Sendable, Equatable {
    let id: String
    /// Verb shown in pickers, e.g. "Erase" or "Delete".
    let title: String
    let operation: CleanupOperation
    let regeneration: Regeneration
    /// What this action does, in one sentence.
    let explanation: String
}

// MARK: - In use

/// What to re-check right before cleaning, so nothing in use is touched even if it started
/// after the scan.
nonisolated enum InUseCheck: Sendable, Equatable {
    case none
    /// A compiler or `xcodebuild` is running.
    case buildTools
    /// A Gradle daemon is running.
    case gradleDaemon
    /// An app whose bundle identifier starts with one of these prefixes is open, or one of
    /// these command-line tools is running (the Codex app and the `codex` CLI).
    case runningApp(bundleIDPrefixes: [String], executableNames: [String] = [], name: String)
    /// This simulator is booted.
    case simulator(udid: String)
    /// Any simulator in this device set is booted.
    case simulatorSet(SimulatorControl.DeviceSet)
    /// Any simulator at all is booted.
    case anySimulator
    /// Per folder: skip the caches of apps that are open.
    case appCacheOwners
    /// This Android emulator is running.
    case androidEmulator(name: String)
}

// MARK: - Items

/// One line in the review list.
nonisolated struct CleanupItem: Identifiable, Sendable, Equatable {
    let id: String
    let group: CleanupGroupKind
    let title: String
    /// What it is and why it's safe (or not) to remove — one or two plain sentences.
    let explanation: String
    /// Extra facts such as "iOS 27.0 · Shutdown" or "Largest: Google 1.3 GB".
    var detail: String? = nil
    /// Measured size in bytes. For cloned simulator data this is an upper bound.
    let sizeBytes: Int64
    /// True when files may share storage (APFS clones, hard links) so the size can overcount.
    var sizeIsUpperBound = false
    let actions: [CleanupAction]
    /// Preselected only when the data is safe to regenerate.
    var isRecommended: Bool
    /// A caution shown next to the item, e.g. for archives.
    var warning: String? = nil
    /// A neutral note, e.g. why a safe item still starts unticked.
    var note: String? = nil
    /// Set when the item is in use (booted simulator, running build) or unreadable.
    var blockedReason: String? = nil
    /// Shown when blocked only because Full Disk Access is missing.
    var needsFullDiskAccess = false
    var inUseCheck: InUseCheck = .none

    var isBlocked: Bool { blockedReason != nil }
    var defaultAction: CleanupAction { actions[0] }

    func action(withID id: String?) -> CleanupAction {
        actions.first { $0.id == id } ?? defaultAction
    }
}

nonisolated struct CleanupGroup: Identifiable, Sendable, Equatable {
    let kind: CleanupGroupKind
    var items: [CleanupItem]
    /// Plain notes about the scan of this group, e.g. "Xcode isn't installed".
    var notes: [String] = []

    var id: CleanupGroupKind { kind }

    var totalBytes: Int64 {
        items.filter { !$0.isBlocked }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Adds the findings of a second scanner that reports under the same heading.
    func appending(_ other: CleanupGroup, sortRecommendedFirst: Bool) -> CleanupGroup {
        let combined = items + other.items
        return CleanupGroup(
            kind: kind,
            items: sortRecommendedFirst ? recommendedFirst(combined) : combined,
            notes: notes + other.notes
        )
    }
}

nonisolated struct CleanupScanResult: Sendable, Equatable {
    var groups: [CleanupGroup]

    var allItems: [CleanupItem] { groups.flatMap(\.items) }

    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.totalBytes } }

    var needsFullDiskAccess: Bool { allItems.contains(where: \.needsFullDiskAccess) }

    static let empty = CleanupScanResult(groups: [])
}

// MARK: - Default selection

/// Rules for what starts ticked, applied to every scan result in one place.
nonisolated enum RecommendationPolicy {
    /// Data that has to be downloaded again and is bigger than this starts unticked: clearing
    /// it costs a long re-download the next time a project builds. 100 MB as Finder counts it.
    static let largeDownloadThreshold: Int64 = 100_000_000

    /// `threshold` comes from Settings; nil keeps every re-download ticked.
    static func apply(to item: CleanupItem, threshold: Int64? = largeDownloadThreshold) -> CleanupItem {
        guard let threshold,
              item.isRecommended,
              item.defaultAction.regeneration == .redownloaded,
              item.sizeBytes > threshold else { return item }
        var item = item
        item.isRecommended = false
        item.note = "Unticked because it's over \(ByteSize.string(threshold)) to download again. Tick it when you need the space."
        return item
    }

    static func apply(to group: CleanupGroup, threshold: Int64? = largeDownloadThreshold) -> CleanupGroup {
        let updated = group.items.map { apply(to: $0, threshold: threshold) }
        guard updated != group.items else { return group }
        var group = group
        // Keep ticked items first; the simulators group has its own order and no such items.
        group.items = group.kind == .simulators ? updated : recommendedFirst(updated)
        return group
    }
}

// MARK: - Results

nonisolated enum CleanupOutcome: Sendable, Equatable {
    /// Removed; `bytes` is the size measured during the scan.
    case removed(bytes: Int64)
    /// Moved to the Trash; space comes back once the Trash is emptied.
    case movedToTrash(bytes: Int64)
    /// Not touched, with the reason (booted simulator, running build…).
    case skipped(reason: String)
    /// Some or all of it failed.
    case failed(message: String, removedBytes: Int64)

    var estimatedFreedBytes: Int64 {
        switch self {
        case .removed(let bytes):               bytes
        case .failed(_, let removedBytes):      removedBytes
        case .movedToTrash, .skipped:           0
        }
    }
}

nonisolated struct CleanupItemReport: Identifiable, Sendable, Equatable {
    let item: CleanupItem
    let action: CleanupAction
    let outcome: CleanupOutcome
    /// Where each file went in the Trash, so it can be put back.
    var trashed: [TrashedItem] = []

    var id: String { item.id }
}

/// A file or folder CachePop moved to the Trash, and where it came from.
nonisolated struct TrashedItem: Sendable, Equatable, Hashable {
    let original: URL
    let trashed: URL
}

nonisolated struct CleanupReport: Sendable, Equatable {
    var entries: [CleanupItemReport]
    /// Free space on the volume (important-usage capacity) right before cleaning.
    var availableBefore: Int64?
    /// Free space after APFS settled.
    var availableAfter: Int64?

    /// The real number: how much the volume's available capacity grew.
    var measuredFreedBytes: Int64? {
        guard let availableBefore, let availableAfter else { return nil }
        return max(availableAfter - availableBefore, 0)
    }

    /// Sum of scanned sizes for everything that was removed. Can overcount clones.
    var estimatedFreedBytes: Int64 {
        entries.reduce(0) { $0 + $1.outcome.estimatedFreedBytes }
    }

    var movedToTrashBytes: Int64 {
        entries.reduce(0) { total, entry in
            if case .movedToTrash(let bytes) = entry.outcome { return total + bytes }
            return total
        }
    }

    var skipped: [CleanupItemReport] {
        entries.filter { if case .skipped = $0.outcome { return true } else { return false } }
    }

    var failed: [CleanupItemReport] {
        entries.filter { if case .failed = $0.outcome { return true } else { return false } }
    }

    /// Everything this clean moved to the Trash, for Put Back.
    var trashedItems: [TrashedItem] { entries.flatMap(\.trashed) }
}

// MARK: - Settings the engine follows

/// The user's choices from Settings that change what a scan offers and what a clean touches.
nonisolated struct CleanupSettings: Sendable, Equatable {
    /// Re-downloads bigger than this start unticked; nil keeps them ticked.
    var largeDownloadThreshold: Int64? = RecommendationPolicy.largeDownloadThreshold
    /// Logs younger than this are kept.
    var logAge: TimeInterval = 7 * 86_400
    /// Folders and items CachePop must never clean.
    var neverClean = NeverCleanList()

    static let standard = CleanupSettings()
}

// MARK: - Formatting

nonisolated enum ByteSize {
    // Made once: a formatter costs far more to create than to use, and these run for every size
    // on screen on every redraw. Sizes are formatted off the main thread too, hence the lock.
    private static let lock = NSLock()

    nonisolated(unsafe) private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    nonisolated(unsafe) private static let rateFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    nonisolated(unsafe) private static let fileFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    /// RAM in binary units, as Apple sells it: 16 GB, not 17.18 GB.
    static func memory(_ bytes: Int64) -> String {
        lock.withLock { memoryFormatter.string(fromByteCount: max(bytes, 0)) }
    }

    /// A transfer rate, never smaller than kilobytes: "0.5 KB/s", "12.3 MB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        lock.withLock { rateFormatter.string(fromByteCount: Int64(max(bytesPerSecond, 0))) } + "/s"
    }

    static func string(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        return lock.withLock { fileFormatter.string(fromByteCount: bytes) }
    }
}
