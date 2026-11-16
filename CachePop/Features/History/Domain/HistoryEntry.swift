import Foundation

struct CleanHistoryEntry: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var date: Date
    var freedBytes: Int64
    var wasMeasured: Bool
    var itemCount: Int
    var trashBytes: Int64
    var titles: [String]
}
@MainActor
protocol CleanHistoryStoring {
    func fetch() -> [CleanHistoryEntry]
    func insert(_ entry: CleanHistoryEntry)
    func clear()
}
