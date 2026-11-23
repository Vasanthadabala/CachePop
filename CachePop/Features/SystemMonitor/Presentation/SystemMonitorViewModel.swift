import AppKit
import Foundation
import Observation
import SwiftUI

/// Native popup clients explicitly describe visibility; AppKit's window occlusion flags
/// do not reliably include popovers in a menu-bar-only app.
nonisolated struct MonitorDemand {
    let sampling: Bool
    let details: Bool
    let processes: Bool
    let processView: Bool
    let preloadsProcesses: Bool
    let network: Bool

    init(clients: Set<String>, visibleWindow: Bool, visibleMainWindow: Bool) {
        let processPopup = !clients.isDisjoint(with: ["cpuMenu", "memoryMenu"])
        let popup = !clients.isDisjoint(with: ["cpuMenu", "memoryMenu", "driveMenu", "gpuMenu", "batteryMenu", "sensorsMenu", "networkMenu", "menu", "temperatureMenu", "fanMenu"])
        let section = clients.contains("section") && visibleMainWindow
        processView = processPopup || section
        preloadsProcesses = clients.contains(SystemMonitorViewModel.processMenuBarClient)
        processes = processView || preloadsProcesses
        details = clients.contains("recording") || section
            || (clients.contains("monitorDetails") && visibleMainWindow)
            || !clients.isDisjoint(with: ["driveMenu", "gpuMenu", "batteryMenu", "sensorsMenu", "sensorsMenuBar", "driveMenuBar", "gpuMenuBar", "batteryMenuBar", "sensorMenuBar"])
        network = details || !clients.isDisjoint(with: ["networkMenu", "networkMenuBar"])
        sampling = popup || preloadsProcesses || network || !clients.isDisjoint(with: ["fans", "recording", "menuBar", "driveMenuBar", "gpuMenuBar", "batteryMenuBar", "sensorMenuBar", "sensorsMenuBar"])
            || (visibleWindow && !clients.isEmpty)
    }
}


enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory
    var id: String { rawValue }
    var title: String { self == .cpu ? "CPU" : "Memory" }
}


/// Live readings for System Monitor, the sidebar, the menu bar panel and the menu bar icon's
/// readout. Live readings refresh once a second, including when only the menu bar is visible.
@Observable
@MainActor
final class SystemMonitorViewModel {
    /// Two minutes of live readings.
    static let historyLength = 120
    static let interval: Duration = .seconds(1)
    /// Live sensor readings in the menu bar don't wait for a visible window.
    static let menuBarClient = "menuBar"
    /// CPU and memory menu items also keep their top-process rows ready before a click.
    nonisolated static let processMenuBarClient = "processMenuBar"

    private(set) var snapshot: SystemSnapshot?
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var temperatureHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []
    private(set) var networkUsage: NetworkUsageHistory
    private(set) var gpuHistories: [String: [Double]] = [:]
    private(set) var rendererHistories: [String: [Double]] = [:]
    private(set) var tilerHistories: [String: [Double]] = [:]
    private(set) var memoryPressureHistory: [Double] = []
    private(set) var swapHistory: [Double] = []
    private(set) var batteryHistory: [Double] = []
    private(set) var chargeHistory: RollingBatteryHistory
    private(set) var powerHistory: [Double] = []
    private(set) var displayFrameHistory: [Double] = []
    private(set) var neuralPowerHistory: [Double] = []
    private(set) var driveReadHistories: [String: [Double]] = [:]
    private(set) var driveWriteHistories: [String: [Double]] = [:]
    var activePage: MonitorPage = .cpu
    @ObservationIgnored let coreTopology: [Int: CPUCoreKind]
    private(set) var processes: [ProcessUsage] = []
    private(set) var processStatus: ProcessReadStatus = .idle
    @ObservationIgnored private var cachedMenuProcesses: [ProcessUsage] = []
    @ObservationIgnored private var menuProcessDate: ContinuousClock.Instant?
    private(set) var sensorMaximums: [String: Double] = [:]
    private(set) var peakCPU: Double = 0
    private(set) var peakMemory: Double = 0
    private(set) var isRecording = false
    private(set) var logRecords: [MonitorLogRecord] = []
    static let logLimit = 1_800
    var processSort: ProcessSort = .cpu
    var processToQuit: ProcessUsage?
    /// Set to scroll System Monitor to the process list (used by the screenshot tour).
    var scrollToProcesses = false

    let cores: (performance: Int, efficiency: Int)
    let chipName: String

    private let sampler: any SystemSampling
    /// How many of each client are showing readings. Counted, not a set: a view coming back
    /// (switching sections quickly) can appear before the copy it replaces has disappeared.
    @ObservationIgnored private var clients: [String: Int] = [:]
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []
    private let processApplications: any ProcessApplicationControlling
    @ObservationIgnored private let batteryHistoryStore: (any BatteryChargeHistoryStoring)?
    @ObservationIgnored private let batteryHistoryReader: (any BatteryChargeHistoryReading)?
    @ObservationIgnored private let networkUsageStore: (any NetworkUsageStoring)?
    @ObservationIgnored private var lastNetworkUsageSave: Date?
    @ObservationIgnored private var networkUsageNeedsSave = false
    @ObservationIgnored private var batteryHistoryTask: Task<Void, Never>?
    @ObservationIgnored private var lastBatteryHistoryRefresh: Date?
    @ObservationIgnored private let historyCalendar: Calendar
    @ObservationIgnored private let historyNow: () -> Date

    /// Called with every reading, for the fan heat check.
    var onSnapshot: (SystemSnapshot, ProcessInfo.ThermalState) -> Void = { _, _ in }

    init(sampler: any SystemSampling, processor: ProcessorIdentity, processApplications: any ProcessApplicationControlling,
         batteryHistoryStore: (any BatteryChargeHistoryStoring)? = nil,
         batteryHistoryReader: (any BatteryChargeHistoryReading)? = nil,
         networkUsageStore: (any NetworkUsageStoring)? = nil,
         calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = { Date() }) {
        self.processApplications = processApplications
        self.sampler = sampler
        self.batteryHistoryStore = batteryHistoryStore
        self.batteryHistoryReader = batteryHistoryReader
        self.networkUsageStore = networkUsageStore
        networkUsage = networkUsageStore?.load() ?? NetworkUsageHistory()
        historyCalendar = calendar
        historyNow = now
        chargeHistory = RollingBatteryHistory(now: now(), calendar: calendar, readings: batteryHistoryStore?.load() ?? [])
        chipName = processor.name
        cores = (processor.performanceCores, processor.efficiencyCores)
        coreTopology = processor.topology
    }
    isolated deinit {
        task?.cancel()
        batteryHistoryTask?.cancel()
        if networkUsageNeedsSave { networkUsageStore?.save(networkUsage) }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isSamplingDetails = false
    @ObservationIgnored private var isSamplingProcesses = false

    /// Starts sampling for `client` ("window", "section", "menu", `menuBarClient`, or "fans" while
    /// fans are on a fixed speed). CPU/memory items preload processes while enabled.
    func begin(_ client: String) {
        clients[client, default: 0] += 1
        watchWindows()
        updateSampling()
    }

    func end(_ client: String) {
        guard let count = clients[client] else { return }
        clients[client] = count > 1 ? count - 1 : nil
        updateSampling()
        if !readingDemand.network { flushNetworkUsage() }
    }

    /// Keep the same live cadence for visible readings and menu-bar-only mode. Stop when no
    /// visible client, menu bar item, recording or fan heat check needs readings.
    private func updateSampling() {
        releaseUnusedProcessDetails()
        let demand = readingDemand
        let details = demand.details
        guard demand.sampling else {
            task?.cancel()
            return
        }
        if let task, !task.isCancelled, isSamplingDetails == details, isSamplingProcesses == demand.processes { return }

        // Take a reading immediately when starting or changing the requested detail level.
        let previous = task
        previous?.cancel()
        isSamplingDetails = details
        isSamplingProcesses = demand.processes
        task = Task(priority: .userInitiated) { [weak self, sampler] in
            // Let the old loop cancel its commands before a new loop starts them again.
            await previous?.value
            guard !Task.isCancelled else { return }
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                guard self != nil else { break }
                await self?.tick(includeDetails: details)
                // Count sampling time toward the interval instead of adding it to every wait.
                // Skip missed deadlines rather than issuing a burst of catch-up readings.
                deadline += Self.interval
                if deadline <= clock.now { deadline = clock.now.advanced(by: Self.interval) }
                do { try await clock.sleep(until: deadline, tolerance: .milliseconds(20)) }
                catch { break }
            }
            await sampler.cancelPendingReadings()
        }
    }

    /// Keep the full process/app list only while a process view is visible. Enabled CPU/memory
    /// menu items continue refreshing the small top-process cache in the background.
    func releaseUnusedProcessDetails(discardMenuCache: Bool = false) {
        if discardMenuCache { cachedMenuProcesses = []; menuProcessDate = nil }
        let demand = readingDemand
        guard !demand.processView else { return }
        if !processes.isEmpty { processes = [] }
        if !demand.preloadsProcesses { processStatus = .idle }
        processApplications.releaseDetails()
        if var snapshot, snapshot.processes != nil {
            snapshot.processes = nil
            self.snapshot = snapshot
        }
    }

    private var readingDemand: MonitorDemand {
        MonitorDemand(clients: Set(clients.keys), visibleWindow: Self.hasVisibleWindow,
                      visibleMainWindow: Self.hasVisibleMainWindow)
    }

    /// Enabled CPU/memory items keep these rows fresh even before the first opening.
    /// The full process list and app/icon objects are still released while inactive.
    func menuProcesses(at now: ContinuousClock.Instant = .now) -> [ProcessUsage] {
        if !processes.isEmpty { return processes }
        guard let menuProcessDate, menuProcessDate.duration(to: now) <= .seconds(10) else { return [] }
        return cachedMenuProcesses
    }

    /// Whether any CachePop window (the main window or the menu bar panel) is on screen and not
    /// fully covered. The menu bar icon's own window is always there, so it doesn't count.
    private static var hasVisibleWindow: Bool {
        (NSApp?.windows ?? []).contains { window in
            window.isVisible && window.occlusionState.contains(.visible) && !window.className.contains("StatusBar")
        }
    }

    private static var hasVisibleMainWindow: Bool {
        (NSApp?.windows ?? []).contains { $0.canBecomeMain && $0.isVisible && $0.occlusionState.contains(.visible) }
    }

    /// Re-checks whenever a window is shown, closed, covered or uncovered, or the app is hidden.
    private func watchWindows() {
        guard windowObservers.isEmpty else { return }
        let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                     NSApplication.didChangeOcclusionStateNotification]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateSampling() }
            }
        }
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushNetworkUsage() }
        })
    }

    private func tick(includeDetails: Bool) async {
        let visible = Self.hasVisibleMainWindow && clients["monitorDetails"] != nil
        let request = MonitorReadRequest(processes: readingDemand.processes, details: includeDetails,
                                         gpuProcesses: clients["gpuMenu"] != nil || clients["gpuMenuBar"] != nil || (visible && activePage == .gpu),
                                         driveProcesses: clients["driveMenu"] != nil || clients["driveMenuBar"] != nil || (visible && activePage == .drive),
                                         energyProcesses: clients["batteryMenu"] != nil || clients["batteryMenuBar"] != nil || (visible && activePage == .battery),
                                         network: readingDemand.network)
        let snapshot = await sampler.sample(request: request)
        guard !Task.isCancelled else { return }
        apply(snapshot)
    }

    func apply(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        let now = historyNow()
        var usage = networkUsage
        if usage.record(snapshot.networkReading, at: now, calendar: historyCalendar) { networkUsageNeedsSave = true }
        networkUsage = usage
        if networkUsageNeedsSave, lastNetworkUsageSave.map({ now.timeIntervalSince($0) >= 30 || now < $0 }) ?? true {
            flushNetworkUsage()
        }
        if snapshot.cpu.total > peakCPU { peakCPU = snapshot.cpu.total }
        if snapshot.memory.usedFraction > peakMemory { peakMemory = snapshot.memory.usedFraction }
        for sensor in snapshot.temperatures.sensors {
            if sensor.celsius > (sensorMaximums[sensor.id] ?? -.infinity) {
                sensorMaximums[sensor.id] = sensor.celsius
            }
        }
        if isRecording {
            logRecords.append(MonitorLogRecord(snapshot: snapshot))
            if logRecords.count > Self.logLimit { logRecords.removeFirst() }
        }
        // Only on a change, so views showing heat aren't invalidated on every reading.
        let thermal = ProcessInfo.processInfo.thermalState
        if thermalState != thermal { thermalState = thermal }
        append(snapshot.cpu.total, to: &cpuHistory)
        append(snapshot.memory.usedFraction, to: &memoryHistory)
        append(snapshot.memory.pressureFraction ?? (snapshot.memory.pressure == .normal ? 0 : snapshot.memory.pressure == .warning ? 0.5 : 1), to: &memoryPressureHistory)
        append(Double(snapshot.memory.swapUsed), to: &swapHistory)
        if let battery = snapshot.battery { append(Double(battery.percent) / 100, to: &batteryHistory) }
        var history = chargeHistory
        if history.record(percent: snapshot.battery?.percent, at: historyNow(), calendar: historyCalendar) {
            chargeHistory = history
            batteryHistoryStore?.save(history.readings)
        }
        if snapshot.battery != nil { refreshBatteryHistoryIfNeeded() }
        if let power = snapshot.electricalSensors.first(where: { $0.id == "PSTR" }) { append(power.value, to: &powerHistory) }
        if let frames = snapshot.performance.displayFramesPerSecond { append(frames, to: &displayFrameHistory) }
        if let watts = snapshot.performance.neuralWatts { append(watts, to: &neuralPowerHistory) }
        if let chip = snapshot.temperatures.chip { append(chip, to: &temperatureHistory) }
        if snapshot.hasNetworkReadings {
            append(snapshot.network.inPerSecond, to: &networkInHistory)
            append(snapshot.network.outPerSecond, to: &networkOutHistory)
        }
        if snapshot.hasDetailedReadings {
            var histories = gpuHistories.filter { id, _ in snapshot.gpus.contains { $0.id == id } }
            for gpu in snapshot.gpus {
                if let value = gpu.utilization {
                    var history = histories[gpu.id] ?? []
                    append(value, to: &history)
                    histories[gpu.id] = history
                }
            }
            gpuHistories = histories
            func additionalHistories(_ previous: [String: [Double]], _ value: (GPUSample) -> Double?) -> [String: [Double]] {
                var result = previous.filter { id, _ in snapshot.gpus.contains { $0.id == id } }
                for gpu in snapshot.gpus {
                    if let reading = value(gpu) { var values = result[gpu.id] ?? []; append(reading, to: &values); result[gpu.id] = values }
                }
                return result
            }
            rendererHistories = additionalHistories(rendererHistories) { $0.renderer }
            tilerHistories = additionalHistories(tilerHistories) { $0.tiler }
            append(snapshot.disk.inPerSecond, to: &diskReadHistory)
            append(snapshot.disk.outPerSecond, to: &diskWriteHistory)
            let drives = Set(snapshot.driveActivity.map(\.id))
            driveReadHistories = driveReadHistories.filter { drives.contains($0.key) }
            driveWriteHistories = driveWriteHistories.filter { drives.contains($0.key) }
            for drive in snapshot.driveActivity {
                var reads = driveReadHistories[drive.id] ?? [], writes = driveWriteHistories[drive.id] ?? []
                append(drive.throughput.inPerSecond, to: &reads); append(drive.throughput.outPerSecond, to: &writes)
                driveReadHistories[drive.id] = reads; driveWriteHistories[drive.id] = writes
            }
        }
        if let processes = snapshot.processes {
            self.processes = processes
            processStatus = .ready
            let cpu = processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5)
            let memory = processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5)
            var seen = Set<Int32>()
            cachedMenuProcesses = (Array(cpu) + Array(memory)).filter { seen.insert($0.pid).inserted }
            menuProcessDate = .now
            // Forget processes that ended, and look again for ones that had no app yet.
            let pids = Set(processes.map(\.pid))
            processApplications.retainDetails(for: pids)
        } else if snapshot.processStatus != .idle {
            processStatus = snapshot.processStatus
        }
        if readingDemand.preloadsProcesses { releaseUnusedProcessDetails() }
        onSnapshot(snapshot, thermalState)
    }

    /// Save the pending byte totals when sampling stops or the app exits.
    func flushNetworkUsage() {
        guard networkUsageNeedsSave else { return }
        networkUsageStore?.save(networkUsage)
        networkUsageNeedsSave = false
        lastNetworkUsageSave = historyNow()
    }

    /// One background import per hour, including after wake. Never slows the live sampler.
    private func refreshBatteryHistoryIfNeeded() {
        let now = historyNow()
        guard let batteryHistoryReader, batteryHistoryTask == nil,
              lastBatteryHistoryRefresh.map({ now.timeIntervalSince($0) >= 3_600 }) ?? true else { return }
        lastBatteryHistoryRefresh = now
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        batteryHistoryTask = Task { [weak self] in
            let readings = await batteryHistoryReader.readings(in: interval)
            guard !Task.isCancelled, let self else { return }
            var restored = self.chargeHistory
            if restored.merge(readings, at: self.historyNow(), calendar: self.historyCalendar) {
                self.chargeHistory = restored
                self.batteryHistoryStore?.save(restored.readings)
            }
            self.batteryHistoryTask = nil
        }
    }

    func resetMaximums() {
        sensorMaximums = Dictionary((snapshot?.temperatures.sensors ?? []).map { ($0.id, $0.celsius) }, uniquingKeysWith: max)
        peakCPU = snapshot?.cpu.total ?? 0
        peakMemory = snapshot?.memory.usedFraction ?? 0
    }

    func startRecording() {
        guard !isRecording else { return }
        logRecords = []
        isRecording = true
        if let snapshot { logRecords.append(MonitorLogRecord(snapshot: snapshot)) }
        begin("recording")
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        end("recording")
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    // MARK: Processes

    var topProcesses: [ProcessUsage] {
        let sorted = processSort == .cpu
            ? processes.sorted { $0.cpuPercent > $1.cpuPercent }
            : processes.sorted { $0.memoryBytes > $1.memoryBytes }
        return Array(sorted.prefix(8))
    }

    func canQuit(_ process: ProcessUsage) -> Bool { processApplications.canQuit(pid: process.pid) }

    /// Asks the app to quit normally; native prompts and self-protection belong to the adapter.
    func quit(_ process: ProcessUsage) {
        processApplications.quit(pid: process.pid)
        processToQuit = nil
    }

    // MARK: Text

    var sidebarSummary: String? {
        guard let snapshot else { return nil }
        var parts = ["CPU \(Int((snapshot.cpu.total * 100).rounded()))%"]
        if let chip = snapshot.temperatures.chip { parts.append(Self.temperature(chip)) }
        return parts.joined(separator: " · ")
    }

    var thermalTitle: String {
        switch thermalState {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        @unknown default: "Unknown"
        }
    }

    var thermalExplanation: String {
        switch thermalState {
        case .nominal: "Running cool. Nothing is being slowed down."
        case .fair: "A little warm. macOS may run fans faster or ease off background work."
        case .serious: "Hot. macOS is slowing the chip to cool it down."
        case .critical: "Very hot. macOS is slowing the chip a lot. Close heavy apps and let it cool."
        @unknown default: ""
        }
    }

    var isHot: Bool { thermalState == .serious || thermalState == .critical }

    /// nil until a sample is available; a genuine idle reading shows 0%.
    static func menuBarCPUUsage(_ snapshot: SystemSnapshot?) -> String? {
        snapshot.map { percentage($0.cpu.total) }
    }

    static func menuBarMemoryUsage(_ snapshot: SystemSnapshot?) -> String? {
        guard let memory = snapshot?.memory, memory.total > 0 else { return nil }
        return percentage(memory.usedFraction)
    }

    /// Storage occupied, rather than the disk's read/write throughput.
    static func menuBarSSDUsage(_ disk: DiskInfo) -> String? {
        guard disk.totalBytes > 0 else { return nil }
        return percentage(disk.usedFraction)
    }

    private static func percentage(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// The temperature menu bar item's text, e.g. "41°C". nil before the first reading, or
    /// without temperature sensors.
    static func menuBarTemperature(_ snapshot: SystemSnapshot?) -> String? {
        snapshot?.temperatures.chip.map(temperature)
    }

    /// The fan speed menu bar item's text: the fastest fan, e.g. "1840 rpm" (no thousands
    /// separator, to keep the item narrow). nil before the first reading, or without fans.
    static func menuBarFanSpeed(_ snapshot: SystemSnapshot?) -> String? {
        guard let fastest = snapshot?.fans.map(\.rpm).max() else { return nil }
        return "\(Int(fastest.rounded()).formatted(.number.grouping(.never))) rpm"
    }

    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteSize.rate(bytesPerSecond)
    }
}
