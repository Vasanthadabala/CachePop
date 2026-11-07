import AppKit
import Foundation
import Observation
import SwiftUI

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
    /// nil when processes weren't sampled this time.
    var processes: [ProcessUsage]?
}

/// Takes readings off the main thread and keeps the previous counters so rates can be worked out.
actor SystemSampler {
    /// Replaces the SMC as the source of fan readings (demo mode).
    private let fanSource: (@Sendable () -> [FanSample])?
    private var temperatureReader: TemperatureReader?
    private var smc: SMC?
    private var lastTicks: [CPUTicks] = []
    private var lastDisk: ByteCounters?
    private var lastNetwork: ByteCounters?
    private var lastTime: Date?
    private let runner = ProcessCommandRunner()

    init(fanSource: (@Sendable () -> [FanSample])? = nil) {
        self.fanSource = fanSource
    }

    func sample(includeProcesses: Bool) async -> SystemSnapshot {
        if temperatureReader == nil { temperatureReader = TemperatureReader() }
        if smc == nil { smc = SMC() }

        // The first reading would show no CPU use at all, and one after a pause (nothing on screen)
        // the average over the whole pause: take a fresh baseline a moment before instead.
        if lastTime.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
            lastTicks = CPUReader.ticks()
            lastDisk = DiskIOReader.counters()
            lastNetwork = NetworkReader.counters()
            lastTime = Date()
            try? await Task.sleep(for: .milliseconds(500))
        }

        let now = Date()
        let seconds = lastTime.map { now.timeIntervalSince($0) } ?? 0
        var snapshot = SystemSnapshot()

        let ticks = CPUReader.ticks()
        snapshot.cpu = CPUSample.between(lastTicks, ticks)
        lastTicks = ticks
        snapshot.loadAverage = CPUReader.loadAverage()
        snapshot.memory = MemoryReader.read()

        let disk = DiskIOReader.counters()
        let network = NetworkReader.counters()
        if let lastDisk { snapshot.disk = Throughput.between(lastDisk, disk, seconds: seconds) }
        if let lastNetwork { snapshot.network = Throughput.between(lastNetwork, network, seconds: seconds) }
        lastDisk = disk
        lastNetwork = network
        lastTime = now

        snapshot.temperatures = temperatureReader?.read() ?? TemperatureSample()
        snapshot.fans = fanSource?() ?? smc?.fans() ?? []
        snapshot.battery = BatteryReader.read()

        if includeProcesses {
            let command = ToolCommand(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-Ao", "pid=,pcpu=,rss=,comm="])
            if let output = try? await runner.run(command, timeout: 5), output.succeeded {
                snapshot.processes = ProcessListParser.parse(output.stdout)
            }
        }
        return snapshot
    }
}

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory
    var id: String { rawValue }
    var title: String { self == .cpu ? "CPU" : "Memory" }
}

/// Live readings for System Monitor, the sidebar, the menu bar panel and the menu bar icon's
/// readout. Sampling runs only while something shows it: every two seconds while readings are
/// on screen, every five when only the menu bar readout needs them.
@Observable
@MainActor
final class SystemMonitorViewModel {
    static let historyLength = 60
    static let interval: Duration = .seconds(2)
    static let menuBarInterval: Duration = .seconds(5)
    /// The temperature and fan speed menu bar items. Always in view, so they don't wait for a
    /// visible window.
    static let menuBarClient = "menuBar"

    private(set) var snapshot: SystemSnapshot?
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var temperatureHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []
    private(set) var processes: [ProcessUsage] = []
    var processSort: ProcessSort = .cpu
    var processToQuit: ProcessUsage?
    /// Set to scroll System Monitor to the process list (used by the screenshot tour).
    var scrollToProcesses = false

    let cores = CPUReader.coreKinds()
    let chipName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }()

    private let sampler: SystemSampler
    /// How many of each client are showing readings. Counted, not a set: a view coming back
    /// (switching sections quickly) can appear before the copy it replaces has disappeared.
    @ObservationIgnored private var clients: [String: Int] = [:]
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []
    /// Running apps behind listed processes, looked up once per process instead of on every
    /// render: each lookup asks Launch Services, and a fresh instance loads its icon again.
    @ObservationIgnored private var runningApps: [Int32: NSRunningApplication?] = [:]

    /// Called with every reading, for the fan heat check.
    var onSnapshot: (SystemSnapshot, ProcessInfo.ThermalState) -> Void = { _, _ in }

    init(fanSource: (@Sendable () -> [FanSample])? = nil) {
        sampler = SystemSampler(fanSource: fanSource)
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Whether the running loop samples every `interval` (true) or every `menuBarInterval`.
    @ObservationIgnored private var isSamplingFast = false

    /// Starts sampling for `client` ("window", "section", "menu", `menuBarClient`, or "fans" while
    /// fans are on a fixed speed). The process list is only read while the System Monitor section
    /// is showing.
    func begin(_ client: String) {
        clients[client, default: 0] += 1
        watchWindows()
        updateSampling()
    }

    func end(_ client: String) {
        guard let count = clients[client] else { return }
        clients[client] = count > 1 ? count - 1 : nil
        updateSampling()
    }

    /// Samples every two seconds while a CachePop window showing readings can be seen, and while
    /// fans are on a fixed speed (the heat check needs temperatures); every five while only the
    /// menu bar readout needs them. A minimized, hidden or covered window, or a menu bar panel
    /// that closed without saying so, costs nothing.
    private func updateSampling() {
        let onScreen = clients.keys.contains { $0 != "fans" && $0 != Self.menuBarClient } && Self.hasVisibleWindow
        let fast = clients["fans"] != nil || onScreen
        let wanted = fast || clients[Self.menuBarClient] != nil
        guard wanted else {
            task?.cancel()
            task = nil
            return
        }
        // Already sampling at the right pace.
        if task != nil, isSamplingFast == fast { return }

        // Start, or restart at the new pace (a window opening takes a reading straight away).
        task?.cancel()
        isSamplingFast = fast
        let pause = fast ? Self.interval : Self.menuBarInterval
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: pause)
            }
        }
    }

    /// Whether any CachePop window (the main window or the menu bar panel) is on screen and not
    /// fully covered. The menu bar icon's own window is always there, so it doesn't count.
    private static var hasVisibleWindow: Bool {
        (NSApp?.windows ?? []).contains { window in
            window.isVisible && window.occlusionState.contains(.visible) && !window.className.contains("StatusBar")
        }
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
    }

    private func tick() async {
        let wantsProcesses = clients["section"] != nil && Self.hasVisibleWindow
        let snapshot = await sampler.sample(includeProcesses: wantsProcesses)
        guard !Task.isCancelled else { return }
        apply(snapshot)
    }

    func apply(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        // Only on a change, so views showing heat aren't invalidated on every reading.
        let thermal = ProcessInfo.processInfo.thermalState
        if thermalState != thermal { thermalState = thermal }
        append(snapshot.cpu.total, to: &cpuHistory)
        append(snapshot.memory.usedFraction, to: &memoryHistory)
        if let chip = snapshot.temperatures.chip { append(chip, to: &temperatureHistory) }
        append(snapshot.disk.inPerSecond, to: &diskReadHistory)
        append(snapshot.disk.outPerSecond, to: &diskWriteHistory)
        append(snapshot.network.inPerSecond, to: &networkInHistory)
        append(snapshot.network.outPerSecond, to: &networkOutHistory)
        if let processes = snapshot.processes {
            self.processes = processes
            // Forget processes that ended, and look again for ones that had no app yet.
            let pids = Set(processes.map(\.pid))
            runningApps = runningApps.filter { pids.contains($0.key) && $0.value != nil }
        }
        onSnapshot(snapshot, thermalState)
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

    /// The running app behind a process, if any.
    func runningApp(for process: ProcessUsage) -> NSRunningApplication? {
        if let cached = runningApps[process.pid], cached?.isTerminated != true { return cached }
        let app = NSRunningApplication(processIdentifier: process.pid)
        runningApps[process.pid] = .some(app)
        return app
    }

    /// The app behind a process, if it's one the user can quit normally.
    func app(for process: ProcessUsage) -> NSRunningApplication? {
        guard let app = runningApp(for: process),
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    /// Asks the app to quit, the same as choosing Quit in it. Unsaved work prompts as usual.
    func quit(_ process: ProcessUsage) {
        app(for: process)?.terminate()
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
