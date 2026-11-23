import Foundation
import Testing
@testable import CachePop

@Suite("System Monitor")
struct SystemMonitorTests {
    @Test func cpuUsageComesFromTickDifferences() {
        let before = [CPUTicks(user: 100, system: 50, idle: 850, nice: 0), CPUTicks(user: 0, system: 0, idle: 1_000, nice: 0)]
        let after = [CPUTicks(user: 160, system: 70, idle: 870, nice: 0), CPUTicks(user: 0, system: 0, idle: 1_100, nice: 0)]
        let sample = CPUSample.between(before, after)
        #expect(sample.perCore.count == 2)
        #expect(abs(sample.perCore[0] - 0.8) < 0.0001)
        #expect(sample.perCore[1] == 0)
        #expect(abs(sample.total - 0.4) < 0.0001)
        #expect(abs(sample.user - 0.3) < 0.0001)
        #expect(abs(sample.system - 0.1) < 0.0001)
        #expect(CPUSample.between([], after) == CPUSample())
    }

    @Test func memoryFollowsActivityMonitorsArithmetic() {
        let sample = MemorySample.from(total: 16_000, pageSize: 10, internalPages: 500, purgeablePages: 100, externalPages: 200,
                                       wiredPages: 150, compressorPages: 50, swapUsed: 0, pressure: .normal)
        #expect(sample.app == 4_000)
        #expect(sample.wired == 1_500)
        #expect(sample.compressed == 500)
        #expect(sample.cached == 3_000)
        #expect(sample.used == 6_000)
        #expect(sample.free == 7_000)
    }

    @Test func ratesNeverGoNegative() {
        let rate = Throughput.between(ByteCounters(read: 1_000, written: 500), ByteCounters(read: 3_000, written: 100), seconds: 2)
        #expect(rate.inPerSecond == 1_000)
        #expect(rate.outPerSecond == 0)
        #expect(Throughput.between(ByteCounters(), ByteCounters(read: 10), seconds: 0) == Throughput())
    }

    @Test func temperaturesAreGroupedAndNoiseIgnored() {
        let sample = TemperatureSample.from([
            ("PMU tdie1", 40), ("PMU tdie2", 44), ("PMU2 tdie1", 42), ("PMU tdev1", -21.9),
            ("NAND CH0 temp", 37), ("gas gauge battery", 32), ("gas gauge battery", 34), ("PMU tcal", 51.8),
            ("pACC MTR Temp Sensor0", 60), ("eACC MTR Temp Sensor0", 50)
        ])
        #expect(sample.chip == 55)
        #expect(sample.chipMax == 60)
        #expect(sample.ssd == 37)
        #expect(sample.battery == 33)
        #expect(TemperatureSample.from([]).chip == nil)
    }

    @Test func memorySensorsAreFoundAmongTheSMCKeys() {
        let keys = ["Tm0B", "Tm02", "Tm0p", "Tm0P", "TMVR", "TM0P", "TM0S", "TMA1", "TMB4", "Tp01", "TH0x", "Tm", "#KEY"]
        // M4 (Tm0B), M1 (Tm02), M4 Pro (Tm0p) and Intel (TM0P, TM0S, the riser slots). Not the
        // mainboard (Tm0P), a voltage regulator (TMVR) or other sensors.
        #expect(MemoryTemperature.keys(in: keys) == ["Tm0B", "Tm02", "Tm0p", "TM0P", "TM0S", "TMA1", "TMB4"])
        #expect(MemoryTemperature.average([40, 42, -21.7, 0]) == 41)
        #expect(MemoryTemperature.average([]) == nil)
    }

    @MainActor
    @Test func temperaturePanelShowsTheSensorsThisMacHas() {
        #expect(TemperatureMenuContent.rows(nil).map(\.title) == ["CPU"])
        let all = TemperatureMenuContent.rows(TemperatureSample(chip: 41, ssd: 39, battery: 34, memory: 40))
        #expect(all.map(\.title) == ["CPU", "Memory", "Drive", "Battery"])
        #expect(all.map(\.celsius) == [41, 40, 39, 34])
        #expect(TemperatureMenuContent.rows(TemperatureSample(chip: 41, ssd: 39)).map(\.title) == ["CPU", "Drive"])
    }

    @Test func smcNumbersDecode() {
        let floatBytes = withUnsafeBytes(of: Float(2_412.5).bitPattern.littleEndian) { Array($0) }
        #expect(SMC.decode(type: "flt ", bytes: floatBytes) == 2_412.5)
        #expect(SMC.decode(type: "fpe2", bytes: [0x25, 0x80]) == 2_400)
        #expect(SMC.decode(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMC.decode(type: "ch8*", bytes: [1]) == nil)
        #expect(SMC.fourCharacterCode("FNum") == 0x464E_756D)
    }

    @Test func batteryHealth() {
        #expect(BatterySample.health(fullCharge: 4_034, design: 4_629).map { Int(($0 * 100).rounded()) } == 87)
        #expect(BatterySample.health(fullCharge: nil, design: 4_629) == nil)
        #expect(BatterySample.health(fullCharge: 5_000, design: 4_000) == 1)
    }

    @Test func processListParses() {
        let output = """
          1   0.0  12345 /sbin/launchd
        812  23.4 204800 /Applications/Visual Studio Code.app/Contents/MacOS/Code Helper (Renderer)
        bad line
        """
        let processes = ProcessListParser.parse(output)
        #expect(processes.count == 2)
        #expect(processes[1].pid == 812)
        #expect(processes[1].cpuPercent == 23.4)
        #expect(processes[1].memoryBytes == 204_800 * 1024)
        #expect(processes[1].name == "Code Helper (Renderer)")
    }

    @Test func sparklineFillsFromTheRight() {
        let points = SparklineGeometry.points([0, 0.5, 1], minimum: 0, maximum: 1, capacity: 5, in: CGSize(width: 100, height: 54))
        #expect(points.count == 3)
        #expect(points.last?.x == 100)
        #expect(points.first?.x == 50)
        #expect(points.first?.y == 52)
        #expect(points.last?.y == 2)
        #expect(SparklineGeometry.points([1], minimum: 0, maximum: 1, capacity: 5, in: CGSize(width: 100, height: 50)).isEmpty)
    }

    /// Reads the real sensors once. Read-only; checks only that readings are sane.
    @Test func liveReadingsAreSane() async {
        #expect(!CPUReader.ticks().isEmpty)
        let memory = MemoryReader.read()
        #expect(memory.total > 0)
        #expect(memory.used <= memory.total)
        let sampler = SystemSampler()
        _ = await sampler.sample(includeProcesses: false)
        var snapshot = await sampler.sample(includeProcesses: true)
        // Process commands finish independently of the live sensor readings.
        for _ in 0..<500 where snapshot.processes == nil {
            try? await Task.sleep(for: .milliseconds(10))
            snapshot = await sampler.sample(includeProcesses: true, includeDetails: false)
        }
        #expect((0...1).contains(snapshot.cpu.total))
        #expect(!(snapshot.processes ?? []).isEmpty)
        if let chip = snapshot.temperatures.chip { #expect((1...130).contains(chip)) }
        if let memory = snapshot.temperatures.memory { #expect((1...130).contains(memory)) }
        for fan in snapshot.fans { #expect(fan.rpm >= 0) }
    }
}

@Suite("Monitor formatting")
struct MonitorFormattingTests {
    @MainActor
    @Test func menuBarUsageDistinguishesMissingReadingsFromZeroUsage() {
        #expect(SystemMonitorViewModel.menuBarCPUUsage(nil) == nil)
        #expect(SystemMonitorViewModel.menuBarMemoryUsage(nil) == nil)
        #expect(SystemMonitorViewModel.menuBarMemoryUsage(SystemSnapshot()) == nil)
        #expect(SystemMonitorViewModel.menuBarSSDUsage(.empty) == nil)

        var snapshot = SystemSnapshot()
        #expect(SystemMonitorViewModel.menuBarCPUUsage(snapshot) == "0%")
        snapshot.cpu.total = 0.426
        snapshot.memory = MemorySample(total: 1_000, app: 600, wired: 100, compressed: 50, cached: 150)
        #expect(SystemMonitorViewModel.menuBarCPUUsage(snapshot) == "43%")
        #expect(SystemMonitorViewModel.menuBarMemoryUsage(snapshot) == "75%")
        #expect(SystemMonitorViewModel.menuBarSSDUsage(DiskInfo(totalBytes: 1_000, availableBytes: 360)) == "64%")
        #expect(SystemMonitorViewModel.menuBarSSDUsage(DiskInfo(totalBytes: 1_000, availableBytes: 1_000)) == "0%")
        #expect(SystemMonitorViewModel.menuBarSSDUsage(DiskInfo(totalBytes: 1_000, availableBytes: 0)) == "100%")
    }

    @Test func memoryUsesBinaryUnitsAndRatesStartAtKilobytes() {
        #expect(ByteSize.memory(17_179_869_184) == "16 GB")
        #expect(!ByteSize.rate(481).contains("bytes"))
        #expect(ByteSize.rate(2_500_000).hasSuffix("MB/s"))
    }

    @MainActor
    @Test func menuBarReadingsShowWhatsAvailable() {
        var snapshot = SystemSnapshot()
        snapshot.temperatures = TemperatureSample(chip: 41, chipMax: 45)
        snapshot.fans = [FanSample(index: 0, rpm: 1_520, minimum: 1_200, maximum: 5_800),
                         FanSample(index: 1, rpm: 1_911.6, minimum: 1_200, maximum: 6_200)]

        #expect(SystemMonitorViewModel.menuBarTemperature(snapshot) == SystemMonitorViewModel.temperature(41))
        // The fastest fan, rounded, without a thousands separator (it sits in the menu bar).
        #expect(SystemMonitorViewModel.menuBarFanSpeed(snapshot) == "1912 rpm")

        // Before the first reading, or on a Mac without fans or sensors, there's nothing to show.
        #expect(SystemMonitorViewModel.menuBarTemperature(nil) == nil)
        #expect(SystemMonitorViewModel.menuBarFanSpeed(nil) == nil)
        var bare = snapshot
        bare.fans = []
        bare.temperatures = TemperatureSample()
        #expect(SystemMonitorViewModel.menuBarFanSpeed(bare) == nil)
        #expect(SystemMonitorViewModel.menuBarTemperature(bare) == nil)
    }
}
