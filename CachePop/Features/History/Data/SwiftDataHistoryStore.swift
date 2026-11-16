import Foundation
import SwiftData

@MainActor
final class SwiftDataHistoryStore: CleanHistoryStoring {
    private let context: ModelContext?
    private var fallback: [CleanHistoryEntry] = []
    init(inMemory: Bool = false) {
        context = Self.makeContainer(inMemory: inMemory).map { ModelContext($0) }
    }
    func fetch() -> [CleanHistoryEntry] {
        guard let context else { return fallback }
        let descriptor = FetchDescriptor<CleanRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map {
            CleanHistoryEntry(id: String(describing: $0.persistentModelID), date: $0.date,
                              freedBytes: $0.freedBytes, wasMeasured: $0.wasMeasured,
                              itemCount: $0.itemCount, trashBytes: $0.trashBytes, titles: $0.titles)
        }
    }
    func insert(_ entry: CleanHistoryEntry) {
        guard let context else { fallback.insert(entry, at: 0); return }
        context.insert(CleanRecord(date: entry.date, freedBytes: entry.freedBytes,
                                   wasMeasured: entry.wasMeasured, itemCount: entry.itemCount,
                                   trashBytes: entry.trashBytes, titles: entry.titles))
        try? context.save()
    }
    func clear() {
        if let context { try? context.delete(model: CleanRecord.self); try? context.save() }
        fallback = []
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
