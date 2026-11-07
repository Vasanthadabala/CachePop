import Foundation
import Observation
import SwiftData

/// One finished clean, as shown in History.
@Model
final class CleanRecord {
    var date: Date
    /// Space the clean freed, measured from the disk (or estimated when it couldn't be read).
    var freedBytes: Int64
    var wasMeasured: Bool
    var itemCount: Int
    var trashBytes: Int64
    /// Titles of what was cleaned, largest first.
    var titles: [String]

    init(date: Date, freedBytes: Int64, wasMeasured: Bool, itemCount: Int, trashBytes: Int64, titles: [String]) {
        self.date = date
        self.freedBytes = freedBytes
        self.wasMeasured = wasMeasured
        self.itemCount = itemCount
        self.trashBytes = trashBytes
        self.titles = titles
    }
}

/// Every clean CachePop has done, with the lifetime total.
///
/// Kept in its own store under Application Support/CachePop. If the store can't be opened the
/// history lives in memory for this session instead of stopping the app.
@Observable
@MainActor
final class CleanHistory {
    private(set) var records: [CleanRecord] = []
    @ObservationIgnored private let context: ModelContext?

    init(inMemory: Bool = false) {
        context = Self.makeContainer(inMemory: inMemory).map { ModelContext($0) }
        reload()
    }

    var lifetimeFreedBytes: Int64 { records.reduce(0) { $0 + $1.freedBytes } }
    var lastClean: CleanRecord? { records.first }

    func add(_ report: CleanupReport, date: Date = Date()) {
        let cleaned = report.entries.filter {
            switch $0.outcome {
            case .removed, .movedToTrash, .failed: true
            case .skipped: false
            }
        }
        guard !cleaned.isEmpty else { return }
        let record = CleanRecord(
            date: date,
            freedBytes: report.measuredFreedBytes ?? report.estimatedFreedBytes,
            wasMeasured: report.measuredFreedBytes != nil,
            itemCount: cleaned.count,
            trashBytes: report.movedToTrashBytes,
            titles: cleaned.sorted { $0.item.sizeBytes > $1.item.sizeBytes }.map(\.item.title)
        )
        insert(record)
    }

    func insert(_ record: CleanRecord) {
        if let context {
            context.insert(record)
            try? context.save()
            reload()
        } else {
            records.insert(record, at: 0)
        }
    }

    func clear() {
        if let context {
            try? context.delete(model: CleanRecord.self)
            try? context.save()
        }
        records = []
    }

    private func reload() {
        guard let context else { return }
        let descriptor = FetchDescriptor<CleanRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        records = (try? context.fetch(descriptor)) ?? []
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer? {
        let schema = Schema([CleanRecord.self])
        if !inMemory, let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CachePop", isDirectory: true) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let configuration = ModelConfiguration("CleanHistory", schema: schema, url: folder.appendingPathComponent("History.store"))
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) { return container }
        }
        let memory = ModelConfiguration("CleanHistory", schema: schema, isStoredInMemoryOnly: true)
        return try? ModelContainer(for: schema, configurations: [memory])
    }
}
