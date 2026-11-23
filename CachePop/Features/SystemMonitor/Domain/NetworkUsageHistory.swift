import Foundation

nonisolated struct NetworkUsageDay: Codable, Equatable, Sendable {
    /// The local Gregorian date when traffic was recorded, independent of DST duration.
    let key: String
    var bytes: ByteCounters
}

/// Only observed deltas count. First readings, sampling gaps and process restarts establish
/// a fresh baseline rather than treating lifetime interface counters as today's usage.
nonisolated struct NetworkUsageHistory: Codable, Equatable, Sendable {
    private(set) var startedAt: Date?
    private(set) var days: [NetworkUsageDay] = []
    private var previous: NetworkReading?
    private var previousDate: Date?
    private enum CodingKeys: CodingKey { case startedAt, days }

    init() {}

    func today(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> ByteCounters {
        total(prefix: Self.key(for: date, calendar: calendar))
    }

    func month(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> ByteCounters {
        total(prefix: String(Self.key(for: date, calendar: calendar).prefix(7)))
    }

    @discardableResult
    mutating func record(_ reading: NetworkReading?, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard now.timeIntervalSince1970.isFinite else { return false }
        let oldStart = startedAt
        let oldDays = days
        defer { previous = reading; previousDate = reading == nil ? nil : now }
        guard let reading else { return false }
        if startedAt == nil { startedAt = now }
        guard let previous, let previousDate else { return startedAt != oldStart }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0, elapsed <= 10 else { return startedAt != oldStart }
        var remaining = reading.bytes(since: previous)
        var cursor = previousDate
        var c = Calendar(identifier: .gregorian)
        c.timeZone = calendar.timeZone
        // A reading may straddle midnight/month-end. Split that short interval without
        // creating or extrapolating traffic during unobserved hours.
        while cursor < now {
            let end = min(c.dateInterval(of: .day, for: cursor)?.end ?? now, now)
            guard end > cursor else { break }
            let fraction = end.timeIntervalSince(cursor) / now.timeIntervalSince(cursor)
            let bytes = ByteCounters(read: Self.share(remaining.read, fraction), written: Self.share(remaining.written, fraction))
            if bytes.read > 0 || bytes.written > 0 {
                let key = Self.key(for: cursor, calendar: c)
                if let index = days.firstIndex(where: { $0.key == key }) {
                    days[index].bytes.read = NetworkReading.add(days[index].bytes.read, bytes.read)
                    days[index].bytes.written = NetworkReading.add(days[index].bytes.written, bytes.written)
                } else { days.append(NetworkUsageDay(key: key, bytes: bytes)) }
            }
            remaining.read -= bytes.read
            remaining.written -= bytes.written
            cursor = end
        }
        let cutoff = Self.key(for: c.date(byAdding: .day, value: -62, to: now) ?? now, calendar: c)
        days = Array(days.filter { $0.key >= cutoff }.sorted { $0.key < $1.key }.suffix(63))
        return startedAt != oldStart || days != oldDays
    }

    private func total(prefix: String) -> ByteCounters {
        days.filter { $0.key.hasPrefix(prefix) }.reduce(into: ByteCounters()) { total, day in
            total.read = NetworkReading.add(total.read, day.bytes.read)
            total.written = NetworkReading.add(total.written, day.bytes.written)
        }
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = calendar.timeZone
        let parts = c.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func share(_ bytes: UInt64, _ fraction: Double) -> UInt64 {
        if fraction >= 1 { return bytes }
        if fraction <= 0 { return 0 }
        return UInt64(Double(bytes) * min(fraction, 0.999999999999))
    }
}

@MainActor
protocol NetworkUsageStoring {
    func load() -> NetworkUsageHistory
    func save(_ history: NetworkUsageHistory)
}
