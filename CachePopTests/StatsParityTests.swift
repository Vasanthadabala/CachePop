import Foundation
import Testing
@testable import CachePop

@Suite("Stats monitoring parity")
struct StatsParityTests {
    @Test func frequencyUsesResidencyWeightsAndRejectsBrokenTables() {
        #expect(PerformanceTelemetry.weightedFrequency(table: [1_000, 2_000, 3_000], residencies: [1, 2, 1]) == 2_000)
        #expect(PerformanceTelemetry.weightedFrequency(table: [1_000], residencies: [0]) == nil)
        #expect(PerformanceTelemetry.weightedFrequency(table: [1_000], residencies: [1, 2]) == nil)
        #expect(PerformanceTelemetry.weightedFrequency(table: [1_000], residencies: [-1]) == nil)
        let reading = PerformanceSample(efficiencyMHz: 1_000, performanceMHz: 2_500)
        #expect(reading.cpuMHz(efficiencyCores: 6, performanceCores: 4) == 1_600)
    }

    @Test func memoryPressureLevelAndCoreLabelsPreserveTheirMeaning() {
        #expect(MemoryReader.pressureFraction(availableLevel: 75) == 0.25)
        #expect(MemoryReader.pressureFraction(availableLevel: 100) == 0)
        #expect(MemoryReader.pressureFraction(availableLevel: -1) == nil)
        let topology: [Int: CPUCoreKind] = [0: .efficiency, 1: .performance, 2: .efficiency, 3: .performance]
        #expect(CPUCoreTopology.label(3, topology: topology) == "Performance 2")
        #expect(CPUCoreTopology.label(4, topology: topology) == "Core 5")
    }

    @Test func energyUnitsConvertToWattsWithoutGuessingUnknownUnits() {
        #expect(PerformanceTelemetry.watts(energy: 2_000, unit: "mJ", seconds: 2) == 1)
        #expect(PerformanceTelemetry.watts(energy: 2_000_000, unit: "uJ", seconds: 2) == 1)
        #expect(PerformanceTelemetry.watts(energy: 2_000_000_000, unit: "nJ", seconds: 2) == 1)
        #expect(PerformanceTelemetry.watts(energy: -1, unit: "J", seconds: 1) == nil)
        #expect(PerformanceTelemetry.watts(energy: 1, unit: "unknown", seconds: 1) == nil)
        #expect(PerformanceTelemetry.watts(energy: 1, unit: "J", seconds: 0) == nil)
    }

    @Test func smartLogDecodesLifetimeUnitsAndHealthWithoutOverflow() throws {
        var bytes = [UInt8](repeating: 0, count: 512)
        bytes[1] = 0x34; bytes[2] = 0x01 // 308 K
        bytes[3] = 100; bytes[5] = 4
        bytes[32] = 2; bytes[48] = 3; bytes[112] = 20; bytes[128] = 30; bytes[144] = 2
        let value = try #require(DriveHealth.decode(bytes))
        #expect(value.remainingLife == 96)
        #expect(abs((value.temperature ?? 0) - 34.85) < 0.001)
        #expect(value.totalRead == 1_024_000 && value.totalWritten == 1_536_000)
        #expect(value.powerCycles == 20 && value.powerOnHours == 30 && value.unsafeShutdowns == 2)
        #expect(!value.isWarning)
        bytes[0] = 1; bytes[40] = 1; bytes[5] = 255
        let overflow = try #require(DriveHealth.decode(bytes))
        #expect(overflow.totalRead == .max && overflow.remainingLife == 0 && overflow.isWarning)
        #expect(DriveHealth.decode([0, 1]) == nil)
    }

    @Test func gpuClientsAreMeasuredOverTimeAndResetForReusedQueues() throws {
        let reader = GPUProcessReader()
        let now = ContinuousClock.now
        let first = GPUProcessReader.Client(pid: 123, name: "Fixture", nanoseconds: 1_000, queues: 1)
        #expect(reader.sample([1: first], at: now).isEmpty)
        let second = GPUProcessReader.Client(pid: 123, name: "Fixture", nanoseconds: 500_001_000, queues: 1)
        let reading = try #require(reader.sample([1: second], at: now.advanced(by: .seconds(1))).first)
        #expect(reading.percent == 50)
        let reset = GPUProcessReader.Client(pid: 123, name: "Fixture", nanoseconds: 800_001_000, queues: 2)
        #expect(reader.sample([1: reset], at: now.advanced(by: .seconds(2))).isEmpty)
        #expect(reader.sample([:], at: now.advanced(by: .seconds(3))).isEmpty)
    }

    @Test func gpuClientParsingRejectsMalformedAndOverflowingCounters() {
        #expect(GPUProcessReader.parse(["IOUserClientCreator": "pid 42, App", "AppUsage": [["accumulatedGPUTime": 123]]])?.pid == 42)
        #expect(GPUProcessReader.parse(["IOUserClientCreator": "pid nope, App", "AppUsage": [["accumulatedGPUTime": 123]]]) == nil)
        #expect(GPUProcessReader.parse(["IOUserClientCreator": "pid 42, App", "AppUsage": [["accumulatedGPUTime": -1]]]) == nil)
        #expect(GPUProcessReader.parse(["IOUserClientCreator": "pid 42, App", "AppUsage": [["accumulatedGPUTime": NSNumber(value: UInt64.max)], ["accumulatedGPUTime": 1]]]) == nil)
    }

    @Test func batteryCapacitiesUseMilliampHoursAndAdapterDataOnlyWhileConnected() throws {
        var properties: [String: Any] = ["CurrentCapacity": 80, "MaxCapacity": 100, "ExternalConnected": true,
            "AppleRawCurrentCapacity": 3_200, "AppleRawMaxCapacity": 4_000, "DesignCapacity": 4_500,
            "Voltage": 12_000, "Amperage": -500, "Temperature": 3_200,
            "AdapterDetails": ["Watts": 30, "AdapterVoltage": 20_000, "Current": 1_500]]
        let reading = try #require(BatteryReader.sample(properties: properties))
        #expect(reading.percent == 80 && reading.currentCapacityMah == 3_200)
        #expect(reading.fullChargeCapacityMah == 4_000 && reading.designCapacityMah == 4_500)
        #expect(reading.adapterWatts == 30 && reading.adapterVoltage == 20 && reading.adapterAmperage == 1.5)
        #expect(reading.powerWatts == 6 && reading.temperatureCelsius == 32)
        properties["ExternalConnected"] = false
        #expect(BatteryReader.sample(properties: properties)?.adapterWatts == nil)
    }

    @Test func powerScoresUseMeasuredRowsAndNeverWatts() {
        let result = EnergyProcessUsage.parse("PID COMMAND POWER\n42 First App 1.0\n7 Second 2.0\n42 First App 3.5\n8 Broken nan")
        #expect(result.map(\.pid) == [42, 7])
        #expect(result.first?.impact == 3.5)
        #expect(result.first?.name == "First App")
        #expect(EnergyProcessUsage.parse("PID COMMAND POWER\n1 Stale 8\nPID COMMAND POWER\n2 Current 2").map(\.pid) == [2])
    }

    @Test func electricalSensorsRejectNoiseAndKeepKindsSeparate() {
        let keys: Set<String> = ["PSTR", "VD0R", "ID0R"]
        let result = ElectricalSensors.read(keys: keys) { ["PSTR": 12.5, "VD0R": 20, "ID0R": 0.6][$0] }
        #expect(result.map(\.unit) == ["W", "V", "A"])
        #expect(ElectricalSensors.read(keys: keys) { _ in .infinity }.isEmpty)
        #expect(ElectricalSensors.read(keys: keys) { _ in 10_000 }.isEmpty)
    }

    @MainActor
    @Test func optionalMenuItemsAreOffByDefaultAndSavedIndependently() throws {
        let suite = "CachePop.tests.stats-parity.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        #expect(!settings.menuBarShowsGPUUsage && !settings.menuBarShowsBattery)
        settings.menuBarShowsGPUUsage = true
        settings.menuBarShowsBattery = true
        settings.showMenuBarItem = false
        let restored = AppSettings(defaults: defaults, canChangeLoginItem: false)
        #expect(restored.menuBarShowsGPUUsage && restored.menuBarShowsBattery && restored.showsAnyMenuBarItem)
        #expect(!restored.menuBarShowsCPUUsage && !restored.menuBarShowsMemoryUsage)
    }

    @MainActor
    @Test func newHistoriesRemainBoundedAndRemovedGPUsReleaseTheirCharts() {
        let monitor = SystemMonitorViewModel()
        let gpu = GPUSample(id: "fixture", name: "GPU", utilization: 0.4, renderer: 0.3, tiler: 0.2, memoryBytes: nil)
        for _ in 0..<400 {
            monitor.apply(SystemSnapshot(gpus: [gpu], electricalSensors: [ElectricalSensor(id: "PSTR", name: "System", kind: .power, value: 12)]))
        }
        #expect(monitor.memoryPressureHistory.count == SystemMonitorViewModel.historyLength)
        #expect(monitor.swapHistory.count == SystemMonitorViewModel.historyLength)
        #expect(monitor.powerHistory.count == SystemMonitorViewModel.historyLength)
        #expect(monitor.rendererHistories["fixture"]?.count == SystemMonitorViewModel.historyLength)
        monitor.apply(SystemSnapshot())
        #expect(monitor.rendererHistories.isEmpty && monitor.tilerHistories.isEmpty)
    }

    @Test func hardwareMenuClientsKeepReadingsAliveWithoutStartingCPUProcessCommands() {
        for client in ["gpuMenuBar", "batteryMenuBar", "driveMenuBar", "sensorMenuBar"] {
            let demand = MonitorDemand(clients: [client], visibleWindow: false, visibleMainWindow: false)
            #expect(demand.sampling && demand.details && !demand.processes)
        }
    }

    actor SlowEnergyRunner: CommandRunning {
        private(set) var starts = 0
        private(set) var cancellations = 0
        func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
            starts += 1
            do { try await Task.sleep(for: .seconds(10)) }
            catch { cancellations += 1; throw error }
            return CommandOutput(status: 0, stdout: "PID COMMAND POWER\n1 Fixture 2", stderr: "")
        }
    }

    @Test func energyQueriesNeverBlockLiveReadingsOrOverlapAndStopWhenReleased() async throws {
        let runner = SlowEnergyRunner()
        let sampler = SystemSampler(runner: runner)
        _ = await sampler.sample(includeProcesses: false, includeDetails: false)
        let now = ContinuousClock.now
        let request = MonitorReadRequest(processes: false, details: false, energyProcesses: true)
        _ = await sampler.sample(request: request)
        _ = await sampler.sample(request: request)
        #expect(now.duration(to: .now) < .milliseconds(500))
        for _ in 0..<100 where await runner.starts == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await runner.starts == 1)
        await sampler.cancelPendingReadings()
        for _ in 0..<100 where await runner.cancellations == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await runner.cancellations == 1)
    }
}
