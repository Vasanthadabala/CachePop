import Foundation
import Testing
@testable import CachePop

@Suite("Hardware monitoring")
struct HardwareMonitoringTests {
    @Test func gpuPercentagesPreserveUnavailableReadings() {
        #expect(GPUSample.percentage(nil) == nil)
        #expect(GPUSample.percentage(-1) == nil)
        #expect(GPUSample.percentage(101) == nil)
        #expect(GPUSample.percentage(NSNumber(value: Double.nan)) == nil)
        #expect(GPUSample.percentage(0) == 0)
        #expect(GPUSample.percentage(42) == 0.42)
        #expect(GPUSample.percentage(100) == 1)
    }

    @Test func coreGroupsUseLogicalCoreIDsInsteadOfAssumingAnOrder() {
        let topology: [Int: CPUCoreKind] = [0: .performance, 1: .efficiency, 3: .efficiency]
        let loads = [0.9, 0.2, 1, 0.4]
        let efficiency = CPUCoreTopology.average(.efficiency, loads: loads, topology: topology)
        #expect(abs((efficiency ?? 0) - 0.3) < 0.0001)
        #expect(CPUCoreTopology.average(.performance, loads: loads, topology: topology) == 0.9)
        #expect(CPUCoreTopology.average(.efficiency, loads: [], topology: topology) == nil)
        #expect(CPUCoreTopology.average(.performance, loads: loads, topology: [:]) == nil)
    }

    @Test func electricalReadingsConvertUnitsAndRejectSentinels() {
        let reading = BatterySample.electrical(voltageMillivolts: 12_000, milliamps: -1_250)
        let battery = BatterySample(percent: 50, isCharging: false, isPluggedIn: false, cycleCount: nil,
                                    health: nil, minutesRemaining: nil, voltage: reading.voltage, amperage: reading.current)
        #expect(battery.voltage == 12)
        #expect(battery.amperage == -1.25)
        #expect(battery.powerWatts == 15)
        #expect(BatterySample.electrical(voltageMillivolts: 65_535, milliamps: 65_535).voltage == nil)
        #expect(BatterySample.electrical(voltageMillivolts: nil, milliamps: nil).current == nil)
        #expect(BatterySample.electrical(voltageMillivolts: 12_000, milliamps: 0).current == 0)
    }

    @Test func mountedVolumeFractionsStayWithinTheirBounds() {
        func volume(_ total: Int64, _ free: Int64) -> MountedVolume {
            MountedVolume(id: "/fixture", name: "Fixture", format: "APFS", total: total, available: free, isReadOnly: false)
        }
        #expect(volume(100, 25).usedFraction == 0.75)
        #expect(volume(0, 0).usedFraction == 0)
        #expect(volume(100, 150).usedFraction == 0)
        #expect(volume(100, 0).usedFraction == 1)
    }

    @MainActor
    @Test func gpuHistoriesAreBoundedAndForgetDisconnectedDevices() {
        let model = SystemMonitorViewModel()
        let gpu = GPUSample(id: "one", name: "Fixture", utilization: 0.4, renderer: nil, tiler: nil, memoryBytes: nil)
        for _ in 0..<500 { model.apply(SystemSnapshot(gpus: [gpu])) }
        #expect(model.gpuHistories["one"]?.count == SystemMonitorViewModel.historyLength)
        model.apply(SystemSnapshot(hasDetailedReadings: false))
        #expect(model.gpuHistories["one"]?.count == SystemMonitorViewModel.historyLength)
        model.apply(SystemSnapshot(gpus: []))
        #expect(model.gpuHistories.isEmpty)
    }

    actor HeldEnvironment {
        private(set) var calls = 0
        var pending: CheckedContinuation<MonitorEnvironment, Never>?
        func read() async -> MonitorEnvironment {
            calls += 1
            if calls == 1 { return await withCheckedContinuation { pending = $0 } }
            return MonitorEnvironment(hasLoaded: true)
        }
        func finish() {
            pending?.resume(returning: MonitorEnvironment(volumes: [MountedVolume(id: "stale", name: "Stale", format: "APFS", total: 1, available: 1, isReadOnly: false)], hasLoaded: true))
            pending = nil
        }
    }

    @Test func slowDriveMetadataCannotBlockLiveReadingsOrSpawnDuplicateJobs() async throws {
        let source = HeldEnvironment()
        let sampler = SystemSampler(batteryHealthSource: { nil }, environmentSource: { await source.read() })
        _ = await sampler.sample(includeProcesses: false, includeDetails: false)
        #expect(await source.calls == 0)
        _ = await sampler.sample(includeProcesses: false, includeDetails: true)
        for _ in 0..<100 where await source.calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await source.calls == 1)
        await sampler.cancelPendingReadings()
        // The metadata source is still held here, yet another live reading must finish.
        let reading = await sampler.sample(includeProcesses: false, includeDetails: true)
        #expect(!reading.cpu.perCore.isEmpty)
        #expect(await source.calls == 1)
        await source.finish()
        var fresh = false
        for _ in 0..<100 {
            let next = await sampler.sample(includeProcesses: false, includeDetails: true)
            #expect(!next.environment.volumes.contains { $0.id == "stale" })
            if next.environment.hasLoaded { fresh = true; break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fresh)
        await sampler.cancelPendingReadings()
    }

    @Test func nativeHardwareProbeReadsOnlyAvailableValues() {
        let gpus = GPUReader.read()
        let topology = CPUCoreTopology.read()
        let volumes = MonitorEnvironmentReader.volumes()
        let battery = BatteryReader.read()
        print("Hardware probe: \(gpus.count) GPUs, \(topology.count) mapped cores, \(volumes.count) mounted local volumes, battery: \(battery != nil)")
        #expect(gpus.allSatisfy { $0.utilization.map { (0...1).contains($0) } ?? true })
        #expect(topology.keys.allSatisfy { $0 >= 0 && $0 < ProcessInfo.processInfo.processorCount })
        #expect(volumes.allSatisfy { $0.total >= 0 && $0.available >= 0 })
        #expect(TemperatureReader.isUsed("GPU die"))
        #expect(TemperatureReader.isUsed("GPU gacc"))
        #expect(!TemperatureReader.isUsed("Unrelated ambient service"))
    }
}
