import Foundation
import Observation

/// Every clean CachePop has done, with the lifetime total.
///
/// Kept in its own store under Application Support/CachePop. If the store can't be opened the
/// history lives in memory for this session instead of stopping the app.
@Observable
@MainActor
final class CleanHistory {
    private(set) var records: [CleanHistoryEntry] = []
    @ObservationIgnored private let store: any CleanHistoryStoring

    init(store: any CleanHistoryStoring) {
        self.store = store
        reload()
    }

    var lifetimeFreedBytes: Int64 { records.reduce(0) { $0 + $1.freedBytes } }
    var lastClean: CleanHistoryEntry? { records.first }

    func add(_ report: CleanupReport, date: Date = Date()) {
        let cleaned = report.entries.filter {
            switch $0.outcome {
            case .removed, .movedToTrash, .failed: true
            case .skipped: false
            }
        }
        guard !cleaned.isEmpty else { return }
        let record = CleanHistoryEntry(
            date: date,
            freedBytes: report.measuredFreedBytes ?? report.estimatedFreedBytes,
            wasMeasured: report.measuredFreedBytes != nil,
            itemCount: cleaned.count,
            trashBytes: report.movedToTrashBytes,
            titles: cleaned.sorted { $0.item.sizeBytes > $1.item.sizeBytes }.map(\.item.title)
        )
        insert(record)
    }

    func insert(_ record: CleanHistoryEntry) {
        store.insert(record)
        reload()
    }
    func clear() {
        store.clear()
        records = []
    }
    private func reload() { records = store.fetch() }
}
