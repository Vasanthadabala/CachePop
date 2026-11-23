import Foundation
import Testing
@testable import CachePop

@Suite("Daily and monthly network usage")
struct NetworkUsageHistoryTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return value
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func reading(_ download: UInt64, _ upload: UInt64) -> NetworkReading {
        NetworkReading(counters: ByteCounters(read: download, written: upload), interface: "en0",
                       localAddress: "192.0.2.1", interfaceCounters: ["en0": ByteCounters(read: download, written: upload)])
    }

    @Test func countsObservedBytesWithoutImportingLifetimeCounters() {
        let start = date("2026-11-19T10:00:00+05:30")
        var history = NetworkUsageHistory()
        let began = history.record(reading(9_000_000_000, 5_000_000_000), at: start, calendar: calendar)
        #expect(began)
        #expect(history.today(at: start, calendar: calendar) == ByteCounters())
        history.record(reading(9_000_001_000, 5_000_000_400), at: start.addingTimeInterval(1), calendar: calendar)
        history.record(reading(9_000_002_000, 5_000_000_800), at: start.addingTimeInterval(2), calendar: calendar)
        #expect(history.today(at: start, calendar: calendar) == ByteCounters(read: 2_000, written: 800))
        #expect(history.month(at: start, calendar: calendar) == history.today(at: start, calendar: calendar))
        #expect(history.startedAt == start)
    }

    @Test func interfacesResetAppearAndDisappearIndependently() {
        let previous = NetworkReading(counters: ByteCounters(), interface: "en0", localAddress: nil,
                                      interfaceCounters: ["en0": ByteCounters(read: 1_000, written: 500),
                                                          "en1": ByteCounters(read: 2_000, written: 400),
                                                          "en2": ByteCounters(read: 10_000, written: 10_000)])
        let current = NetworkReading(counters: ByteCounters(), interface: "en1", localAddress: nil,
                                     interfaceCounters: ["en0": ByteCounters(read: 10, written: 600),
                                                         "en1": ByteCounters(read: 2_300, written: 550),
                                                         "en3": ByteCounters(read: 90_000, written: 50_000)])
        #expect(current.bytes(since: previous) == ByteCounters(read: 300, written: 250))
    }

    @Test func midnightAndMonthEndSplitTheObservedInterval() {
        let before = date("2026-01-31T23:59:59+05:30")
        let after = before.addingTimeInterval(2)
        var history = NetworkUsageHistory()
        history.record(reading(1_000, 500), at: before, calendar: calendar)
        history.record(reading(1_200, 600), at: after, calendar: calendar)
        #expect(history.today(at: before, calendar: calendar) == ByteCounters(read: 100, written: 50))
        #expect(history.today(at: after, calendar: calendar) == ByteCounters(read: 100, written: 50))
        #expect(history.month(at: after, calendar: calendar) == ByteCounters(read: 100, written: 50))
        #expect(history.month(at: before, calendar: calendar) == ByteCounters(read: 100, written: 50))
        #expect(history.days.count == 2)
    }

    @Test func gapsClockCorrectionsAndUnavailableReadingsDoNotInventUsage() {
        let start = date("2026-11-19T10:00:00+05:30")
        var history = NetworkUsageHistory()
        history.record(reading(100, 100), at: start, calendar: calendar)
        history.record(reading(500, 500), at: start.addingTimeInterval(100), calendar: calendar)
        history.record(reading(600, 600), at: start.addingTimeInterval(99), calendar: calendar)
        history.record(nil, at: start.addingTimeInterval(100), calendar: calendar)
        history.record(reading(900, 900), at: start.addingTimeInterval(101), calendar: calendar)
        #expect(history.today(at: start, calendar: calendar) == ByteCounters())
        history.record(reading(1_000, 950), at: start.addingTimeInterval(102), calendar: calendar)
        #expect(history.today(at: start, calendar: calendar) == ByteCounters(read: 100, written: 50))
        #expect(history.today(at: start.addingTimeInterval(86_400), calendar: calendar) == ByteCounters())
        #expect(history.month(at: start.addingTimeInterval(86_400), calendar: calendar) == ByteCounters(read: 100, written: 50))
    }

    @Test func localCalendarHandlesDSTWithoutAssuming24HourDays() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        let before = date("2026-03-08T01:59:59-05:00")
        var history = NetworkUsageHistory()
        history.record(reading(100, 100), at: before, calendar: c)
        history.record(reading(300, 200), at: before.addingTimeInterval(2), calendar: c)
        #expect(history.days.count == 1)
        #expect(history.today(at: before, calendar: c) == ByteCounters(read: 200, written: 100))
        #expect(history.days.first?.key == "2026-03-08")
    }

    @Test func retentionStaysBoundedAndCurrentMonthTotalsRemainComplete() {
        let start = date("2026-01-01T10:00:00+05:30")
        var history = NetworkUsageHistory()
        for day in 0..<100 {
            let date = start.addingTimeInterval(Double(day) * 86_400)
            history.record(reading(100, 100), at: date, calendar: calendar)
            history.record(reading(200, 150), at: date.addingTimeInterval(1), calendar: calendar)
        }
        let end = start.addingTimeInterval(99 * 86_400)
        #expect(history.days.count <= 63)
        #expect(history.month(at: end, calendar: calendar) == ByteCounters(read: 1_000, written: 500))
    }

    @MainActor @Test func storageRestoresTotalsButNeverLiveBaselinesOrAddresses() throws {
        let suite = "CachePop.tests.network-usage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsNetworkUsageStore(defaults: defaults)
        let start = date("2026-11-19T10:00:00+05:30")
        var history = NetworkUsageHistory()
        history.record(reading(10_000, 1_000), at: start, calendar: calendar)
        history.record(reading(11_000, 1_500), at: start.addingTimeInterval(1), calendar: calendar)
        store.save(history)
        var restored = UserDefaultsNetworkUsageStore(defaults: defaults).load()
        #expect(restored.today(at: start, calendar: calendar) == ByteCounters(read: 1_000, written: 500))
        restored.record(reading(50_000, 10_000), at: start.addingTimeInterval(2), calendar: calendar)
        #expect(restored.today(at: start, calendar: calendar) == ByteCounters(read: 1_000, written: 500), "A relaunch must establish a new baseline.")
        let data = try #require(defaults.data(forKey: "monitor.networkUsage.v1"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        #expect(!String(describing: plist).contains("192.0.2.1"))
        #expect(!String(describing: plist).contains("en0"))
        defaults.set(Data("corrupt".utf8), forKey: "monitor.networkUsage.v1")
        #expect(store.load().startedAt == nil)
    }

    @MainActor @Test func modelTracksNetworkOnlyReadingsAndFlushesPendingTotals() {
        var now = date("2026-11-19T10:00:00+05:30")
        let store = NetworkUsageTestStore()
        let model = SystemMonitorViewModel(sampler: NetworkUsageTestSampler(),
                                          processor: ProcessorIdentity(name: "Fixture", performanceCores: 1, efficiencyCores: 1, topology: [:]),
                                          processApplications: NetworkUsageTestProcesses(), networkUsageStore: store,
                                          calendar: calendar, now: { now })
        var snapshot = SystemSnapshot(hasDetailedReadings: false)
        snapshot.networkReading = reading(1_000, 500)
        model.apply(snapshot)
        #expect(store.saves == 1)
        now = now.addingTimeInterval(1)
        snapshot.networkReading = reading(1_500, 700)
        model.apply(snapshot)
        #expect(store.saves == 1)
        #expect(model.networkUsage.today(at: now, calendar: calendar) == ByteCounters(read: 500, written: 200))
        model.flushNetworkUsage()
        #expect(store.saves == 2)
        #expect(store.history.today(at: now, calendar: calendar) == ByteCounters(read: 500, written: 200))
    }
}

@MainActor private final class NetworkUsageTestStore: NetworkUsageStoring {
    var history = NetworkUsageHistory()
    var saves = 0
    func load() -> NetworkUsageHistory { history }
    func save(_ history: NetworkUsageHistory) { self.history = history; saves += 1 }
}

private actor NetworkUsageTestSampler: SystemSampling {
    func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot { SystemSnapshot() }
}

@MainActor private final class NetworkUsageTestProcesses: ProcessApplicationControlling {
    func canQuit(pid: Int32) -> Bool { false }
    func quit(pid: Int32) {}
    func retainDetails(for processIDs: Set<Int32>) {}
    func releaseDetails() {}
}
