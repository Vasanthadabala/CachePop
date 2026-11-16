import Foundation

/// One reading of everything System Monitor shows.
nonisolated struct SystemSnapshot: Sendable, Equatable {
    var cpu = CPUSample()
    var loadAverage: [Double] = []
    var memory = MemorySample()
    var disk = Throughput()
    var network = Throughput()
    var temperatures = TemperatureSample()
    var fans: [FanSample] = []
    var battery: BatterySample?
    /// nil when no new process list is ready for this reading.
    var processes: [ProcessUsage]?
    var hasDetailedReadings = true
    var gpus: [GPUSample] = []
    var environment = MonitorEnvironment()
    var processStatus: ProcessReadStatus = .idle
    var performance = PerformanceSample()
    var electricalSensors: [ElectricalSensor] = []
    var diskTotals = ByteCounters()
    var driveActivity: [DriveActivity] = []
    var gpuProcesses: [GPUProcessUsage] = []
    var driveProcesses: [DriveProcessUsage] = []
    var energyProcesses: [EnergyProcessUsage] = []
}


nonisolated enum ProcessReadStatus: Sendable, Equatable {
    case idle, loading, ready, unavailable

    var message: String {
        switch self {
        case .idle, .loading: "Reading processes…"
        case .ready: "No processes to show."
        case .unavailable: "Process list unavailable. Retrying…"
        }
    }
}


/// Takes readings off the main thread and keeps the previous counters so rates can be worked out.
nonisolated protocol SystemSampling: Sendable {
    func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot
    func sample(request: MonitorReadRequest) async -> SystemSnapshot
    func cancelPendingReadings() async
}


extension SystemSampling {
    func sample(request: MonitorReadRequest) async -> SystemSnapshot {
        await sample(includeProcesses: request.processes, includeDetails: request.details)
    }
    func cancelPendingReadings() async {}
}
