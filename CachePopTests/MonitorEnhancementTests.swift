import AppKit
import Foundation
import Testing
@testable import CachePop

@Suite("Monitor details and fan boost")
struct MonitorEnhancementTests {
    @MainActor
    @Test func usageMenusRankProcessesByTheirOwnMetricAndLimitTheList() {
        var rows: [ProcessUsage] = []
        for index: Int in 0..<7 {
            let bytes: Int64 = Int64(7 - index) * 1_000
            let cpu: Double = Double(index * 30)
            rows.append(ProcessUsage(pid: Int32(index + 1), name: "Process \(index)",
                                     cpuPercent: cpu, memoryBytes: bytes))
        }
        #expect(UsageMenuKind.cpu.topProcesses(rows).map(\.pid) == [7, 6, 5, 4, 3])
        #expect(UsageMenuKind.memory.topProcesses(rows).map(\.pid) == [1, 2, 3, 4, 5])
        #expect(UsageMenuKind.drive.topProcesses(rows).isEmpty)
        #expect(UsageMenuKind.cpu.topProcesses(rows).first?.cpuPercent == 180)
    }
    @Test func boostUsesStrongestRuleHysteresisAndAvailableSensors() {
        let cool = FanBoostRule(threshold: 70, percent: 75)
        let hot = FanBoostRule(threshold: 80, percent: 100)
        let drive = FanBoostRule(source: .drive, threshold: 60, percent: 90)
        let rules = [cool, hot, drive]
        let warm = FanBoostEvaluation.evaluate(rules: rules, temperatures: TemperatureSample(chipMax: 72), previous: [])
        #expect(warm.percent == 75)
        let peak = FanBoostEvaluation.evaluate(rules: rules, temperatures: TemperatureSample(chipMax: 82), previous: warm.active)
        #expect(peak.percent == 100)
        let held = FanBoostEvaluation.evaluate(rules: rules, temperatures: TemperatureSample(chipMax: 78), previous: peak.active)
        #expect(held.percent == 100)
        let lowered = FanBoostEvaluation.evaluate(rules: rules, temperatures: TemperatureSample(chipMax: 76), previous: held.active)
        #expect(lowered.percent == 75)
        let released = FanBoostEvaluation.evaluate(rules: rules, temperatures: TemperatureSample(chipMax: 66), previous: lowered.active)
        #expect(released.percent == nil)
        #expect(released.active.isEmpty)
        #expect(FanBoostEvaluation.evaluate(rules: [drive], temperatures: TemperatureSample(), previous: [drive.id]).percent == nil)
    }

    @MainActor
    @Test func autoBoostReturnsToMacOSWhenCoolOrHotAndRulesAreSaved() async throws {
        let controller = RecordingFanController()
        let control = FanControlViewModel(controller: controller)
        var snapshot = SystemSnapshot()
        snapshot.fans = [FanSample(index: 0, rpm: 1_800, minimum: 1_200, maximum: 5_800)]
        snapshot.temperatures = TemperatureSample(chipMax: 72)
        control.receive(snapshot, thermalState: .nominal)
        await control.enableAutoBoost(snapshot.fans)
        #expect(control.mode == .autoBoost)
        #expect(control.needsMonitoring)
        #expect(controller.speeds[0] == 4_350)
        snapshot.temperatures.chipMax = 66
        control.receive(snapshot, thermalState: .nominal)
        for _ in 0..<100 where !controller.speeds.isEmpty { await Task.yield() }
        #expect(controller.speeds.isEmpty)
        #expect(control.mode == .autoBoost) // still armed, with macOS managing a cool Mac
        await control.checkSafety(temperatures: TemperatureSample(chipMax: 96), thermalState: .nominal)
        #expect(control.mode == .automatic)
        #expect(!control.needsMonitoring)

        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        let rule = FanBoostRule(source: .memory, threshold: 60, percent: 90)
        settings.fanBoostRules = [rule]
        #expect(AppSettings(defaults: defaults, canChangeLoginItem: false).fanBoostRules == [rule])
    }

    @Test func sensorIDsSurviveMissingReadingsAndGroupsAreAvailable() {
        let full = TemperatureSample.from([("CPU core", 50), ("GPU die", 45), ("NAND", 38), ("Battery", 32)])
        let missing = TemperatureSample.from([("CPU core", 0), ("GPU die", 46), ("NAND", 39), ("Battery", 33)])
        #expect(full.sensors.first { $0.name == "GPU die" }?.id == missing.sensors.first { $0.name == "GPU die" }?.id)
        #expect(full.sensors.map(\.group) == [.cpu, .gpu, .drive, .battery])
        let duplicate = TemperatureSample.from([("CPU", 40), ("CPU", 42)])
        #expect(Set(duplicate.sensors.map(\.id)).count == 2)
    }

    @MainActor
    @Test func missingFanReadingsReleaseAnActiveBoost() async {
        let controller = RecordingFanController()
        let control = FanControlViewModel(controller: controller)
        var snapshot = SystemSnapshot()
        snapshot.fans = [FanSample(index: 0, rpm: 1_800, minimum: 1_200, maximum: 5_800)]
        snapshot.temperatures = TemperatureSample(chipMax: 72)
        control.receive(snapshot, thermalState: .nominal)
        await control.enableAutoBoost(snapshot.fans)
        #expect(!controller.speeds.isEmpty)
        snapshot.fans = []
        control.receive(snapshot, thermalState: .nominal)
        for _ in 0..<100 where control.needsMonitoring { await Task.yield() }
        #expect(controller.speeds.isEmpty)
        #expect(control.mode == .automatic)
        #expect(control.message?.contains("unavailable") == true)
    }

    @MainActor
    @Test func peaksResetToCurrentReadingsAndRecordingOmitsProcessNames() {
        let monitor = SystemMonitorViewModel()
        var snapshot = SystemSnapshot()
        snapshot.cpu.total = 0.9
        snapshot.memory = MemorySample(total: 1_000, app: 800)
        snapshot.temperatures = .from([("CPU", 80)])
        snapshot.processes = [ProcessUsage(pid: 123, name: "private-process-name", cpuPercent: 80, memoryBytes: 1_000)]
        monitor.apply(snapshot)
        snapshot.cpu.total = 0.2
        snapshot.temperatures = .from([("CPU", 40)])
        monitor.apply(snapshot)
        #expect(monitor.peakCPU == 0.9)
        #expect(monitor.sensorMaximums[snapshot.temperatures.sensors[0].id] == 80)
        monitor.resetMaximums()
        #expect(monitor.peakCPU == 0.2)
        #expect(monitor.sensorMaximums[snapshot.temperatures.sensors[0].id] == 40)
        monitor.startRecording()
        monitor.apply(snapshot)
        monitor.stopRecording()
        #expect(monitor.logRecords.count == 2)
        monitor.apply(snapshot)
        #expect(monitor.logRecords.count == 2)
        let csv = MonitorLogRecord.csv(monitor.logRecords)
        #expect(csv.contains("drive_read_bytes_per_second"))
        #expect(csv.contains("battery_health_percent"))
        #expect(!csv.contains("private-process-name"))
        #expect(csv.split(separator: "\n").count == 3)
    }

    @Test func checksSeparateUnavailableDataFromWarnings() {
        var snapshot = SystemSnapshot()
        snapshot.battery = BatterySample(percent: 80, isCharging: false, isPluggedIn: false, health: 0.65)
        let checks = MonitorStatus.checks(snapshot: snapshot, disk: .empty, isHot: false)
        #expect(checks.first { $0.id == "drive" }?.level == .unavailable)
        #expect(checks.first { $0.id == "memory" }?.level == .unavailable)
        #expect(checks.first { $0.id == "battery" }?.level == .warning)
        #expect(checks.first { $0.id == "sensors" }?.level == .unavailable)
    }

    @Test func rotorStopsForZeroAndReduceMotionAndScalesWithinLimits() {
        #expect(FanRotation.duration(rpm: 0, reduceMotion: false) == nil)
        #expect(FanRotation.duration(rpm: 2_000, reduceMotion: true) == nil)
        #expect(FanRotation.duration(rpm: .nan, reduceMotion: false) == nil)
        #expect(FanRotation.duration(rpm: 6_000, reduceMotion: false)! < FanRotation.duration(rpm: 1_500, reduceMotion: false)!)
    }
}
