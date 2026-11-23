import Foundation
import Testing
@testable import CachePop

@Suite("Rolling battery history")
struct RollingBatteryHistoryTests {
    private func calendar(_ zone: String = "Asia/Kolkata") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }

    private func date(_ hour: Int = 12, minute: Int = 0, day: Int = 17, month: Int = 11,
                      calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func coversExactly24HoursWithNewestReadingsOnTheRight() {
        let c = calendar()
        let now = date(calendar: c)
        var history = RollingBatteryHistory(now: now, calendar: c)
        history.record(percent: 78, at: now, calendar: c)
        #expect(history.interval.start == now.addingTimeInterval(-86_400))
        #expect(history.interval.end == now)
        #expect(history.fraction(for: history.interval.start) == 0)
        #expect(history.fraction(for: now) == 1)
        #expect(history.fraction(for: now.addingTimeInterval(-43_200)) == 0.5)
        #expect(history.readings == [.init(date: now, percent: 78)])
    }

    @Test func coalescesWithinAMinuteAndExpiresOnlyOlderReadings() {
        let c = calendar()
        let start = date(0, calendar: c)
        var history = RollingBatteryHistory(now: start, calendar: c)
        for minute in 0...1_500 {
            let now = start.addingTimeInterval(Double(minute * 60))
            let inserted = history.record(percent: 80, at: now, calendar: c)
            let repeated = history.record(percent: 80, at: now.addingTimeInterval(20), calendar: c)
            #expect(inserted)
            #expect(!repeated)
        }
        #expect(history.readings.count == 1_441)
        #expect(history.readings.first?.date == start.addingTimeInterval(3_600))
        let changed = history.record(percent: 79, at: history.interval.end.addingTimeInterval(40), calendar: c)
        #expect(changed)
        #expect(history.readings.count == 1_441)
        #expect(history.readings.last?.percent == 79)
        #expect(history.segments.count == 1)
    }

    @Test func crossingMidnightRetainsYesterday() {
        let c = calendar()
        let late = date(23, minute: 59, calendar: c)
        var history = RollingBatteryHistory(now: late, calendar: c)
        history.record(percent: 80, at: late, calendar: c)
        let midnight = late.addingTimeInterval(60)
        history.record(percent: 79, at: midnight, calendar: c)
        #expect(history.interval.end == midnight)
        #expect(history.readings == [.init(date: late, percent: 80), .init(date: midnight, percent: 79)])
    }

    @Test func restorationRejectsStaleFutureInvalidAndDuplicateReadings() {
        let c = calendar()
        let now = date(calendar: c)
        let recent = now.addingTimeInterval(-60)
        let history = RollingBatteryHistory(now: now, calendar: c, readings: [
            .init(date: now.addingTimeInterval(-86_460), percent: 90),
            .init(date: recent, percent: 81), .init(date: recent.addingTimeInterval(20), percent: 80),
            .init(date: now, percent: 79), .init(date: now.addingTimeInterval(60), percent: 78),
            .init(date: recent.addingTimeInterval(-60), percent: -1),
            .init(date: Date(timeIntervalSince1970: .infinity), percent: 50)
        ])
        #expect(history.readings == [.init(date: recent, percent: 80), .init(date: now, percent: 79)])
        var changed = history
        let accepted = changed.record(percent: 101, at: now, calendar: c)
        #expect(!accepted)
        #expect(changed == history)
    }

    @Test func sleepingAndClockCorrectionsDoNotInventHistory() {
        let c = calendar()
        let morning = date(8, calendar: c)
        var history = RollingBatteryHistory(now: morning, calendar: c)
        history.record(percent: 90, at: morning, calendar: c)
        history.record(percent: 89, at: morning.addingTimeInterval(60), calendar: c)
        let noon = date(calendar: c)
        history.record(percent: 80, at: noon, calendar: c)
        #expect(history.segments.map(\.count) == [2, 1])
        history.record(percent: 79, at: noon.addingTimeInterval(-120), calendar: c)
        #expect(history.readings.last?.date == noon.addingTimeInterval(-120))
        #expect(!history.readings.contains { $0.date >= noon })
        history.record(percent: nil, at: noon.addingTimeInterval(90_000), calendar: c)
        #expect(history.readings.isEmpty)
    }

    @Test func daylightSavingAndTimezoneChangesKeep24ElapsedHours() {
        let c = calendar("America/New_York")
        for now in [date(day: 8, month: 3, calendar: c), date(day: 1, calendar: c)] {
            var history = RollingBatteryHistory(now: now, calendar: c, readings: [
                .init(date: now.addingTimeInterval(-86_400), percent: 90), .init(date: now, percent: 80)
            ])
            #expect(history.interval.duration == 86_400)
            #expect(history.readings.count == 2)
            history.record(percent: 80, at: now, calendar: calendar("Asia/Kolkata"))
            #expect(history.interval.duration == 86_400)
            #expect(history.readings.count == 2)
        }
    }

    @MainActor @Test func storeSurvivesRelaunchAndHandlesCorruptData() throws {
        let suite = "CachePop.tests.battery-history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let c = calendar()
        let now = date(calendar: c)
        let values = [BatteryChargeReading(date: now, percent: 78)]
        UserDefaultsBatteryHistoryStore(defaults: defaults).save(values)
        #expect(UserDefaultsBatteryHistoryStore(defaults: defaults).load() == values)
        defaults.set(Data("invalid".utf8), forKey: "monitor.batteryChargeHistory.v1")
        #expect(UserDefaultsBatteryHistoryStore(defaults: defaults).load().isEmpty)
    }

    @MainActor @Test func viewModelRestoresHistoryAndAvoidsWritingEverySecond() {
        let c = calendar()
        var now = date(calendar: c)
        let store = BatteryHistoryTestStore(readings: [.init(date: now.addingTimeInterval(-60), percent: 79)])
        let model = SystemMonitorViewModel(sampler: BatteryHistoryTestSampler(),
                                          processor: ProcessorIdentity(name: "Fixture", performanceCores: 1, efficiencyCores: 1, topology: [:]),
                                          processApplications: BatteryHistoryTestProcesses(), batteryHistoryStore: store,
                                          calendar: c, now: { now })
        let snapshot = SystemSnapshot(battery: BatterySample(percent: 78, isCharging: false, isPluggedIn: true,
                                                            cycleCount: nil, health: nil, minutesRemaining: nil))
        #expect(model.chargeHistory.readings.count == 1)
        for _ in 0..<10 { model.apply(snapshot) }
        #expect(store.saves == 1)
        #expect(model.chargeHistory.readings.count == 2)
        now = now.addingTimeInterval(60)
        model.apply(snapshot)
        #expect(store.saves == 2)
        #expect(store.readings.count == 3)
    }

    @MainActor @Test func systemImportMergesWithNewLiveReadingsAndRunsAtMostHourly() async throws {
        let c = calendar()
        var now = date(calendar: c)
        let earlier = now.addingTimeInterval(-3_600)
        let reader = BatteryHistoryTestReader(readings: [.init(date: earlier, percent: 80)])
        let store = BatteryHistoryTestStore(readings: [])
        let model = SystemMonitorViewModel(sampler: BatteryHistoryTestSampler(),
                                          processor: ProcessorIdentity(name: "Fixture", performanceCores: 1, efficiencyCores: 1, topology: [:]),
                                          processApplications: BatteryHistoryTestProcesses(), batteryHistoryStore: store,
                                          batteryHistoryReader: reader, calendar: c, now: { now })
        let snapshot = SystemSnapshot(battery: BatterySample(percent: 77, isCharging: false, isPluggedIn: true,
                                                            cycleCount: nil, health: nil, minutesRemaining: nil))
        model.apply(snapshot)
        for _ in 0..<100 {
            if model.chargeHistory.readings.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.chargeHistory.readings.map(\.percent) == [80, 77])
        #expect(store.readings == model.chargeHistory.readings)
        for _ in 0..<10 { model.apply(snapshot) }
        #expect(await reader.calls == 1)
        now = now.addingTimeInterval(3_600)
        model.apply(snapshot)
        for _ in 0..<100 {
            if await reader.calls == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await reader.calls == 2)
    }
}

private actor BatteryHistoryTestReader: BatteryChargeHistoryReading {
    let values: [BatteryChargeReading]
    var calls = 0
    init(readings: [BatteryChargeReading]) { values = readings }
    func readings(in interval: DateInterval) async -> [BatteryChargeReading] {
        calls += 1
        return values
    }
}

@MainActor
private final class BatteryHistoryTestStore: BatteryChargeHistoryStoring {
    var readings: [BatteryChargeReading]
    var saves = 0
    init(readings: [BatteryChargeReading]) { self.readings = readings }
    func load() -> [BatteryChargeReading] { readings }
    func save(_ readings: [BatteryChargeReading]) { self.readings = readings; saves += 1 }
}

private actor BatteryHistoryTestSampler: SystemSampling {
    func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot { SystemSnapshot() }
}

@MainActor
private final class BatteryHistoryTestProcesses: ProcessApplicationControlling {
    func canQuit(pid: Int32) -> Bool { false }
    func quit(pid: Int32) {}
    func retainDetails(for processIDs: Set<Int32>) {}
    func releaseDetails() {}
}
