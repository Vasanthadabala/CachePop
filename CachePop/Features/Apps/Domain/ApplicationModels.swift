import Foundation

nonisolated struct ApplicationDetails: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String
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


nonisolated struct ApplicationRelatedFile: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let sizeBytes: Int64
    /// e.g. "Preferences", "Caches", "Application Support"
    let category: String
    /// False when macOS kept CachePop from measuring it (no Full Disk Access).
    var isReadable = true

    static func == (lhs: ApplicationRelatedFile, rhs: ApplicationRelatedFile) -> Bool {
        lhs.id == rhs.id
    }
}


nonisolated enum UninstallError: LocalizedError {
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


nonisolated struct UninstallResult: Sendable {
    let app: ApplicationDetails
    let bytesFreed: Int64
    let filesRemoved: Int
    let failedPaths: [String]

    var formattedBytesFreed: String {
        ByteCountFormatter.string(fromByteCount: bytesFreed, countStyle: .file)
    }
}
