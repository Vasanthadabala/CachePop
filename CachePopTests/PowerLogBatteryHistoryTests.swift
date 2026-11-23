import Foundation
import Testing
@testable import CachePop

@Suite("Recovered battery history")
struct PowerLogBatteryHistoryTests {
    @Test func importsOnlyTimestampedChargeObservationsWithinTheWindow() {
        let now = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        let log = """
        2026-11-16 17:29:59 +0530 Sleep Using AC (Charge:90%)
        2026-11-16 17:30:00 +0530 Sleep Using AC (Charge:89%)
        2026-11-17 06:00:00 +0000 Wake Using Batt (Charge:78%)
        2026-11-17 07:00:00 +0000 Wake Using Batt (Charge:105%)
        2026-11-17 08:00:00 +0000 Wake Using Batt (Charge:80garbage%)
        2026-11-17 09:00:00 +0000 No recorded charge
        2026-11-17 13:00:00 +0000 Wake Using AC (Charge:81%)
        Not a timestamp (Charge:77%)
        """
        let readings = PowerLogBatteryHistoryReader.parse(log, in: interval)
        #expect(readings.map(\.percent) == [89, 78])
        #expect(readings.first?.date == interval.start)
        #expect(readings.last?.date == now.addingTimeInterval(-6 * 3_600))
    }

    @Test func importsPreserveLocalValuesAndDoNotInventMissingMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var history = RollingBatteryHistory(now: now, readings: [.init(date: now, percent: 77)])
        let previous = now.addingTimeInterval(-3_600)
        let changed = history.merge([.init(date: previous, percent: 80), .init(date: now, percent: 79)], at: now)
        #expect(changed)
        #expect(history.readings.map(\.percent) == [80, 77])
        #expect(history.segments.map(\.count) == [1, 1])
        let unchanged = history.merge([.init(date: previous, percent: 80)], at: now)
        #expect(!unchanged)
    }

    @Test func inaccessibleSystemLogLeavesSavedHistoryAlone() async {
        let reader = PowerLogBatteryHistoryReader(runner: UnavailableBatteryLog())
        let readings = await reader.readings(in: DateInterval(start: .distantPast, end: .now))
        #expect(readings.isEmpty)
    }
}

private struct UnavailableBatteryLog: CommandRunning {
    func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
        #expect(command.executable.path == "/usr/bin/pmset")
        #expect(command.arguments == ["-g", "log"])
        return CommandOutput(status: 1, stdout: "", stderr: "Unavailable")
    }
}
