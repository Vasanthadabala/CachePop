import Foundation

nonisolated struct BatteryChargeReading: Codable, Equatable, Sendable {
    let date: Date
    let percent: Int
}

/// The last 24 elapsed hours, with at most one actual reading per minute.
nonisolated struct RollingBatteryHistory: Equatable, Sendable {
    private(set) var interval: DateInterval
    private(set) var readings: [BatteryChargeReading]

    init(now: Date, calendar: Calendar = .autoupdatingCurrent, readings: [BatteryChargeReading] = []) {
        let minute = calendar.dateInterval(of: .minute, for: now)!.start
        interval = DateInterval(start: minute.addingTimeInterval(-86_400), end: minute)
        self.readings = Self.normalized(readings, interval: interval, calendar: calendar)
    }

    func fraction(for date: Date) -> Double {
        min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }

    /// A gap in recording must remain a gap in the chart.
    var segments: [[BatteryChargeReading]] {
        var result: [[BatteryChargeReading]] = []
        for reading in readings {
            if let previous = result.last?.last, reading.date.timeIntervalSince(previous.date) <= 90 {
                result[result.count - 1].append(reading)
            } else {
                result.append([reading])
            }
        }
        return result
    }

    /// Restore real system observations without overwriting readings taken by CachePop.
    @discardableResult
    mutating func merge(_ historical: [BatteryChargeReading], at now: Date,
                        calendar: Calendar = .autoupdatingCurrent) -> Bool {
        var restored = Self(now: now, calendar: calendar, readings: historical)
        let local = Self.normalized(readings, interval: restored.interval, calendar: calendar)
        var minutes = Dictionary(uniqueKeysWithValues: restored.readings.map { ($0.date, $0) })
        for reading in local { minutes[reading.date] = reading }
        restored.readings = minutes.values.sorted { $0.date < $1.date }
        guard restored != self else { return false }
        self = restored
        return true
    }

    @discardableResult
    mutating func record(percent: Int?, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let minute = calendar.dateInterval(of: .minute, for: now)!.start
        let window = DateInterval(start: minute.addingTimeInterval(-86_400), end: minute)
        var changed = interval != window
        interval = window
        let count = readings.count
        readings.removeAll { $0.date < window.start || $0.date > window.end }
        changed = changed || readings.count != count
        guard let percent, (0...100).contains(percent) else { return changed }
        let reading = BatteryChargeReading(date: minute, percent: percent)
        if readings.last?.date == minute {
            guard readings.last != reading else { return changed }
            readings[readings.count - 1] = reading
        } else {
            readings.append(reading)
        }
        return true
    }

    private static func normalized(_ values: [BatteryChargeReading], interval: DateInterval,
                                   calendar: Calendar) -> [BatteryChargeReading] {
        var minutes: [Date: BatteryChargeReading] = [:]
        for value in values.filter({ $0.date.timeIntervalSince1970.isFinite }).sorted(by: { $0.date < $1.date }) {
            guard (0...100).contains(value.percent), value.date >= interval.start,
                  value.date <= interval.end,
                  let minute = calendar.dateInterval(of: .minute, for: value.date)?.start else { continue }
            minutes[minute] = BatteryChargeReading(date: minute, percent: value.percent)
        }
        return minutes.values.sorted { $0.date < $1.date }
    }
}

nonisolated protocol BatteryChargeHistoryReading: Sendable {
    func readings(in interval: DateInterval) async -> [BatteryChargeReading]
}

@MainActor
protocol BatteryChargeHistoryStoring {
    func load() -> [BatteryChargeReading]
    func save(_ readings: [BatteryChargeReading])
}
