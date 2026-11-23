import AppKit
import Foundation

actor SystemSampler: SystemSampling {
    /// Replaces the SMC as the source of fan readings (demo mode).
    private let fanSource: (@Sendable () -> [FanSample])?
    private var temperatureReader: TemperatureReader?
    private var smc: SMC?
    /// The SMC's memory sensors, looked for on the first reading.
    private var memoryKeys: [String]?
    private var cpuTemperatureSensors: [CPUTemperature.Sensor] = []
    private var availableSMCKeys: Set<String> = []
    private var gpuTemperatureKeys: [String] = []
    private var telemetry: PerformanceTelemetry?
    private var gpuProcessReader: GPUProcessReader?
    private var driveProcessReader: DriveProcessReader?
    private var energyTask: Task<Void, Never>?
    private var energyProcesses: [EnergyProcessUsage] = []
    private var lastTicks: [CPUTicks] = []
    private var lastDisk: ByteCounters?
    private var lastDriveCounters: [String: ByteCounters] = [:]
    private var lastNetwork: NetworkReading?
    private var lastNetworkTime: Date?
    private var lastTime: Date?
    private var lastIOTime: Date?
    private let runner: any CommandRunning
    private let batteryHealthSource: @Sendable () async -> Double?
    private var processTask: Task<Void, Never>?
    private var batteryHealthTask: Task<Void, Never>?
    private var lastProcessRefresh: ContinuousClock.Instant?
    private var lastBatteryHealthRefresh: ContinuousClock.Instant?
    private var pendingProcesses: [ProcessUsage]?
    private var processStatus: ProcessReadStatus = .idle
    private var batteryHealth: Double?
    private var environment = MonitorEnvironment()
    private var environmentTask: Task<Void, Never>?
    private var lastEnvironmentRefresh: ContinuousClock.Instant?
    private let environmentSource: @Sendable () async -> MonitorEnvironment

    init(fanSource: (@Sendable () -> [FanSample])? = nil,
         runner: any CommandRunning = ProcessCommandRunner(stopsWhenCancelled: true),
         batteryHealthSource: @escaping @Sendable () async -> Double? = { await BatteryHealthReader.maximumCapacity() },
         environmentSource: @escaping @Sendable () async -> MonitorEnvironment = { MonitorEnvironmentReader.read() }) {
        self.fanSource = fanSource
        self.runner = runner
        self.batteryHealthSource = batteryHealthSource
        self.environmentSource = environmentSource
    }

    deinit {
        processTask?.cancel()
        batteryHealthTask?.cancel()
        environmentTask?.cancel()
        energyTask?.cancel()
    }

    func cancelPendingReadings() async {
        processTask?.cancel()
        processTask = nil
        pendingProcesses = nil
        energyTask?.cancel()
        energyTask = nil
        energyProcesses = []
        gpuProcessReader = nil
        driveProcessReader = nil
        telemetry = nil
        processStatus = .idle
        environmentTask?.cancel()
        lastProcessRefresh = nil
        if batteryHealthTask != nil {
            batteryHealthTask?.cancel()
            batteryHealthTask = nil
            lastBatteryHealthRefresh = nil
        }
    }

    func sample(includeProcesses: Bool, includeDetails: Bool = true) async -> SystemSnapshot {
        await sample(request: MonitorReadRequest(processes: includeProcesses, details: includeDetails))
    }

    func sample(request: MonitorReadRequest) async -> SystemSnapshot {
        let includeProcesses = request.processes
        let includeDetails = request.details
        guard !Task.isCancelled else { return SystemSnapshot() }
        // Warm the process list while the first CPU baseline is being measured.
        refreshProcessesIfNeeded(requested: includeProcesses)
        refreshEnergyProcesses(requested: request.energyProcesses)
        if temperatureReader == nil { temperatureReader = TemperatureReader() }
        if smc == nil { smc = SMC() }

        // The first reading would show no CPU use at all, and one after a pause (nothing on screen)
        // the average over the whole pause: take a fresh baseline a moment before instead.
        if lastTime.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
            lastTicks = CPUReader.ticks()
            if includeDetails {
                lastDisk = DiskIOReader.counters()
                lastIOTime = Date()
            }
            if includeDetails || request.network {
                lastNetwork = NetworkReader.reading()
                lastNetworkTime = Date()
            }
            lastTime = Date()
            try? await Task.sleep(for: .seconds(1))
        }
        guard !Task.isCancelled else { return SystemSnapshot() }

        let now = Date()
        var snapshot = SystemSnapshot()
        snapshot.hasDetailedReadings = includeDetails

        let ticks = CPUReader.ticks()
        snapshot.cpu = CPUSample.between(lastTicks, ticks)
        lastTicks = ticks
        snapshot.loadAverage = CPUReader.loadAverage()
        snapshot.memory = MemoryReader.read()
        if includeDetails || includeProcesses {
            if telemetry == nil { telemetry = PerformanceTelemetry() }
            snapshot.performance = telemetry?.read() ?? PerformanceSample()
        } else { telemetry = nil }

        if includeDetails {
            let seconds = lastIOTime.map { now.timeIntervalSince($0) } ?? 0
            let devices = DiskIOReader.devices()
            let disk = devices.reduce(into: ByteCounters()) { total, device in total.read &+= device.counters.read; total.written &+= device.counters.written }
            snapshot.diskTotals = disk
            snapshot.driveActivity = devices.map { device in
                DriveActivity(id: device.id, counters: device.counters,
                              throughput: seconds > 0 && seconds <= 10 ? lastDriveCounters[device.id].map { Throughput.between($0, device.counters, seconds: seconds) } ?? Throughput() : Throughput())
            }
            lastDriveCounters = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0.counters) })
            if seconds > 0, seconds <= 10 {
                if let lastDisk { snapshot.disk = Throughput.between(lastDisk, disk, seconds: seconds) }
            }
            lastDisk = disk
            lastIOTime = now
            refreshBatteryHealthIfNeeded()
            snapshot.battery = BatteryReader.read(maximumCapacity: batteryHealth)
            snapshot.gpus = GPUReader.read()
            refreshEnvironmentIfNeeded()
            snapshot.environment = environment
        }
        if includeDetails || request.network {
            let reading = NetworkReader.reading()
            snapshot.networkReading = reading
            let seconds = lastNetworkTime.map { now.timeIntervalSince($0) } ?? 0
            if let reading, let lastNetwork, seconds > 0, seconds <= 10 {
                let delta = reading.bytes(since: lastNetwork)
                snapshot.network = Throughput(inPerSecond: Double(delta.read) / seconds,
                                              outPerSecond: Double(delta.written) / seconds)
                snapshot.hasNetworkReadings = true
            }
            lastNetwork = reading
            lastNetworkTime = now
        }
        if request.gpuProcesses {
            if gpuProcessReader == nil { gpuProcessReader = GPUProcessReader() }
            snapshot.gpuProcesses = gpuProcessReader?.read() ?? []
        } else { gpuProcessReader = nil }
        if request.driveProcesses {
            if driveProcessReader == nil { driveProcessReader = DriveProcessReader() }
            snapshot.driveProcesses = driveProcessReader?.read() ?? []
        } else { driveProcessReader = nil }
        snapshot.energyProcesses = energyProcesses
        lastTime = now

        snapshot.temperatures = temperatureReader?.read() ?? TemperatureSample()
        if memoryKeys == nil {
            let keys = smc?.allKeys() ?? []
            availableSMCKeys = Set(keys)
            gpuTemperatureKeys = ElectricalSensors.gpuKeys(chipName: CPUReader.name, available: availableSMCKeys)
            memoryKeys = MemoryTemperature.keys(in: keys)
            cpuTemperatureSensors = CPUTemperature.sensors(chipName: CPUReader.name, availableKeys: keys)
        }
        snapshot.temperatures.applyCPU(CPUTemperature.read(cpuTemperatureSensors) { smc?.number($0) })
        var memoryReadings: [Double] = []
        for (index, key) in (memoryKeys ?? []).enumerated() {
            if let value = smc?.number(key), value > 1, value < 130 {
                memoryReadings.append(value)
                snapshot.temperatures.sensors.append(TemperatureSensor(id: "smc.\(key)", name: "Memory sensor \(index + 1)", group: .memory, celsius: value))
            }
        }
        snapshot.temperatures.memory = MemoryTemperature.average(memoryReadings)
        if includeDetails {
            let gpu = gpuTemperatureKeys.enumerated().compactMap { index, key -> TemperatureSensor? in
                guard let value = smc?.number(key), value.isFinite, (10...120).contains(value) else { return nil }
                return TemperatureSensor(id: "smc.\(key)", name: "GPU sensor \(index + 1)", group: .gpu, celsius: value)
            }
            snapshot.temperatures.sensors += gpu
            if !gpu.isEmpty { snapshot.temperatures.gpu = gpu.map(\.celsius).reduce(0, +) / Double(gpu.count) }
        }
        if includeDetails { snapshot.electricalSensors = ElectricalSensors.read(keys: availableSMCKeys) { smc?.number($0) } }
        if let batteryTemperature = snapshot.battery?.temperatureCelsius { snapshot.temperatures.battery = batteryTemperature }
        snapshot.fans = fanSource?() ?? smc?.fans() ?? []

        snapshot.processes = pendingProcesses
        pendingProcesses = nil
        snapshot.processStatus = processStatus
        return snapshot
    }

    private func refreshEnergyProcesses(requested: Bool) {
        guard requested else {
            energyTask?.cancel(); energyTask = nil; energyProcesses = []; return
        }
        guard energyTask == nil else { return }
        energyTask = Task.detached(priority: .utility) { [weak self, runner] in
            let command = ToolCommand(executable: URL(fileURLWithPath: "/usr/bin/top"),
                                      arguments: ["-l", "2", "-s", "1", "-n", "8", "-o", "power", "-stats", "pid,command,power"])
            let output = try? await runner.run(command, timeout: 5)
            guard !Task.isCancelled else { return }
            await self?.receivedEnergyProcesses(output)
        }
    }

    private func receivedEnergyProcesses(_ output: CommandOutput?) {
        guard !Task.isCancelled else { return }
        if let output, output.succeeded { energyProcesses = EnergyProcessUsage.parse(output.stdout) }
        energyTask = nil
    }

    private func refreshEnvironmentIfNeeded() {
        let now = ContinuousClock.now
        guard environmentTask == nil,
              lastEnvironmentRefresh.map({ $0.duration(to: now) >= .seconds(15) }) ?? true else { return }
        lastEnvironmentRefresh = now
        environmentTask = Task.detached(priority: .utility) { [weak self, environmentSource] in
            let reading = await environmentSource()
            let cancelled = Task.isCancelled
            await self?.receivedEnvironment(reading, cancelled: cancelled)
        }
    }

    private func receivedEnvironment(_ reading: MonitorEnvironment, cancelled: Bool) {
        environmentTask = nil
        if cancelled { lastEnvironmentRefresh = nil } else { environment = reading }
    }

    /// Slow commands run independently: CPU, memory and temperature readings never wait for them.
    private func refreshProcessesIfNeeded(requested: Bool) {
        guard requested else {
            processTask?.cancel()
            processTask = nil
            pendingProcesses = nil
            lastProcessRefresh = nil
            processStatus = .idle
            return
        }
        let now = ContinuousClock.now
        if processTask == nil, lastProcessRefresh.map({ $0.duration(to: now) >= .seconds(1) }) ?? true {
            if processStatus == .idle { processStatus = .loading }
            lastProcessRefresh = now
            processTask = Task.detached(priority: .utility) { [weak self, runner] in
                let command = ToolCommand(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-Ao", "pid=,pcpu=,rss=,comm="])
                let output = try? await runner.run(command, timeout: 5)
                await self?.finishProcessRefresh(output)
            }
        }
    }

    private func finishProcessRefresh(_ output: CommandOutput?) {
        guard !Task.isCancelled else { return }
        if let output, output.succeeded {
            pendingProcesses = ProcessListParser.parse(output.stdout)
            processStatus = .ready
        } else {
            processStatus = .unavailable
        }
        processTask = nil
    }

    private func refreshBatteryHealthIfNeeded() {
        let now = ContinuousClock.now
        guard batteryHealthTask == nil,
              lastBatteryHealthRefresh.map({ $0.duration(to: now) >= .seconds(1_800) }) ?? true else { return }
        lastBatteryHealthRefresh = now
        batteryHealthTask = Task.detached(priority: .utility) { [weak self, batteryHealthSource] in
            let value = await batteryHealthSource()
            await self?.finishBatteryHealthRefresh(value)
        }
    }

    private func finishBatteryHealthRefresh(_ value: Double?) {
        guard !Task.isCancelled else { return }
        batteryHealth = value
        batteryHealthTask = nil
    }
}
