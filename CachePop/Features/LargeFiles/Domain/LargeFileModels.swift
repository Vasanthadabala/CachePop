import Foundation

/// How old a file must be to show, for the Large Files filter.
nonisolated enum FileAge: Int, CaseIterable, Identifiable, Sendable {
    case any = 0, threeMonths = 90, sixMonths = 180, year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .any:         "Any date"
        case .threeMonths: "Not changed in 3 months"
        case .sixMonths:   "Not changed in 6 months"
        case .year:        "Not changed in a year"
        }
    }

    func includes(_ file: FoundFile, now: Date = Date()) -> Bool {
        guard self != .any else { return true }
        guard let modified = file.modified else { return true }
        return now.timeIntervalSince(modified) >= TimeInterval(rawValue) * 86_400
    }
}


nonisolated struct FoundFile: Identifiable, Sendable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    var identity: FileReviewIdentity? = nil

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}


/// Files with identical contents. Sorted newest first, so the first is the one to keep.
nonisolated struct DuplicateSet: Identifiable, Sendable, Equatable {
    let id: String
    let files: [FoundFile]

    var fileSize: Int64 { files.first?.size ?? 0 }
    /// Space taken by every copy beyond the first.
    var extraBytes: Int64 { fileSize * Int64(max(files.count - 1, 0)) }
}


nonisolated struct LargeFilesResult: Sendable, Equatable {
    var largeFiles: [FoundFile] = []
    var duplicates: [DuplicateSet] = []
    var scannedFileCount = 0
    var unreadableCount = 0
    var wasLimited = false

    var duplicateExtraBytes: Int64 { duplicates.reduce(0) { $0 + $1.extraBytes } }
    var extraCopies: [FoundFile] { duplicates.flatMap { Array($0.files.dropFirst()) } }
    /// Keep the headline and its two categories from counting large duplicate copies twice.
    var otherLargeFiles: [FoundFile] {
        let copies = Set(extraCopies.map(\.id))
        return largeFiles.filter { !copies.contains($0.id) }
    }
    var reviewBytes: Int64 {
        var copies = Set<String>()
        for group in duplicates {
            for file in group.files.dropFirst() { copies.insert(file.id) }
        }
        return largeFiles.reduce(Int64(0)) { total, file in
            total + (copies.contains(file.id) ? 0 : file.size)
        } + duplicateExtraBytes
    }

    static let empty = LargeFilesResult()
}
