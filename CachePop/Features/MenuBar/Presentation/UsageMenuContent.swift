import AppKit
import SwiftUI

enum UsageMenuKind: String, CaseIterable {
    case cpu, gpu, memory, drive, battery
    var title: String {
        switch self { case .cpu: "CPU"; case .gpu: "GPU"; case .memory: "Memory"; case .drive: "Drive"; case .battery: "Battery" }
    }
    var hue: Hue {
        switch self {
        case .cpu: Metric.cpu
        case .gpu: Metric.gpu
        case .memory: Metric.memory
        case .drive: Metric.drive
        case .battery: Metric.battery
        }
    }
    var client: String { "\(rawValue)Menu" }
    var shortcut: String {
        switch self { case .cpu: "c"; case .gpu: "g"; case .memory: "m"; case .drive: "d"; case .battery: "b" }
    }
    var setting: ReferenceWritableKeyPath<AppSettings, Bool> {
        switch self {
        case .cpu: \.menuBarShowsCPUUsage
        case .gpu: \.menuBarShowsGPUUsage
        case .memory: \.menuBarShowsMemoryUsage
        case .drive: \.menuBarShowsSSDUsage
        case .battery: \.menuBarShowsBattery
        }
    }
    var backgroundClient: String {
        switch self {
        case .cpu, .memory: SystemMonitorViewModel.processMenuBarClient
        case .gpu: "gpuMenuBar"
        case .drive: "driveMenuBar"
        case .battery: "batteryMenuBar"
        }
    }

    func topProcesses(_ processes: [ProcessUsage]) -> [ProcessUsage] {
        guard self == .cpu || self == .memory else { return [] }
        return Array(processes.sorted { left, right in
            let lhs = self == .cpu ? left.cpuPercent : Double(left.memoryBytes)
            let rhs = self == .cpu ? right.cpuPercent : Double(right.memoryBytes)
            return lhs == rhs ? left.pid < right.pid : lhs > rhs
        }.prefix(5))
    }
}

/// Component-specific popups share the same readings as System Monitor.
struct UsageMenuContent: View {
    let model: AppModel
    let kind: UsageMenuKind
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private var monitor: SystemMonitorViewModel { model.monitor }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack {
                Text(kind.title)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityIdentifier("\(kind.rawValue)MenuTitle")
                Spacer()
                status
            }
            switch kind {
            case .cpu: cpu
            case .gpu: gpu
            case .memory: memory
            case .drive: drive
            case .battery: battery
            }
            if kind == .cpu || kind == .memory { processList }
            Divider()
            actions
        }
        .padding(AppTheme.Spacing.m)
        .frame(width: 300)
        .onExitCommand { dismissMenu() }
    }

    @ViewBuilder private var status: some View {
        switch kind {
        case .cpu:
            Pill(text: monitor.thermalTitle, tone: monitor.isHot ? .warning : .neutral)
        case .gpu, .battery:
            EmptyView()
        case .memory:
            if let memory = monitor.snapshot?.memory, memory.total > 0 {
                Pill(text: memory.pressure.title, tone: memory.pressure == .normal ? .neutral : .warning)
            }
        case .drive:
            if model.isLowOnSpace { Pill(text: "Low space", tone: .warning) }
        }
    }

    @ViewBuilder private var cpu: some View {
        if let snapshot = monitor.snapshot {
            reading(SystemMonitorViewModel.menuBarCPUUsage(snapshot) ?? "—", detail: monitor.chipName)
            Sparkline(values: monitor.cpuHistory, maximum: 1, color: Metric.cpu.solid).frame(height: 42)
            if !snapshot.cpu.perCore.isEmpty {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(snapshot.cpu.perCore.enumerated()), id: \.offset) { index, load in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(AppTheme.Colors.track)
                            RoundedRectangle(cornerRadius: 2).fill(Metric.core(monitor.coreTopology[index]).solid)
                                .frame(height: max(18 * load, 1))
                        }.frame(height: 18)
                    }
                }.help("Usage per CPU core")
            }
            VStack(spacing: 5) {
                UsageMenuRow("Apps", percent(snapshot.cpu.user), color: Metric.cpu.solid)
                UsageMenuRow("System", percent(snapshot.cpu.system), color: Metric.cpuSystem.solid)
                UsageMenuRow("Idle", percent(max(1 - snapshot.cpu.total, 0)), color: Metric.idle.solid)
                if snapshot.loadAverage.count >= 3 {
                    UsageMenuRow("Load · 1 / 5 / 15 min", snapshot.loadAverage.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: " / "))
                }
                if let temperature = snapshot.temperatures.chip {
                    UsageMenuRow("CPU temperature", SystemMonitorViewModel.temperature(temperature))
                }
                UsageMenuRow("Efficiency frequency", MonitorFormat.frequency(snapshot.performance.efficiencyMHz), color: Metric.efficiency.solid)
                UsageMenuRow("Performance frequency", MonitorFormat.frequency(snapshot.performance.performanceMHz), color: Metric.performance.solid)
            }
        } else { ProgressView("Reading CPU…") }
    }

    @ViewBuilder private var memory: some View {
        if let memory = monitor.snapshot?.memory, memory.total > 0 {
            reading(ByteSize.memory(memory.used), detail: "of \(ByteSize.memory(memory.total)) in use")
            Sparkline(values: monitor.memoryHistory, maximum: 1, color: Metric.memory.solid).frame(height: 42)
            VStack(spacing: 5) {
                UsageMenuRow("App memory", ByteSize.memory(memory.app), color: Metric.memory.solid)
                UsageMenuRow("Wired", ByteSize.memory(memory.wired), color: Metric.wired.solid)
                UsageMenuRow("Compressed", ByteSize.memory(memory.compressed), color: Metric.compressed.solid)
                UsageMenuRow("Cached files", ByteSize.memory(memory.cached), color: Metric.cached.solid)
                UsageMenuRow("Available", ByteSize.memory(max(memory.total - memory.used, 0)))
                UsageMenuRow("Swap", ByteSize.memory(memory.swapUsed))
                if let temperature = monitor.snapshot?.temperatures.memory {
                    UsageMenuRow("Memory temperature", SystemMonitorViewModel.temperature(temperature))
                }
            }
        } else { ProgressView("Reading memory…") }
    }

    @ViewBuilder private var gpu: some View {
        if let snapshot = monitor.snapshot, let gpu = snapshot.gpus.first {
            reading(MonitorFormat.percent(gpu.utilization), detail: gpu.name)
            Sparkline(values: monitor.gpuHistories[gpu.id] ?? [], maximum: 1, color: Metric.gpu.solid).frame(height: 42)
            UsageMenuRow("Renderer", MonitorFormat.percent(gpu.renderer), color: Metric.renderer.solid)
            UsageMenuRow("Tiler", MonitorFormat.percent(gpu.tiler), color: Metric.tiler.solid)
            UsageMenuRow("Memory", gpu.memoryBytes.map(ByteSize.memory) ?? "—")
            UsageMenuRow("Temperature", snapshot.temperatures.gpu.map(SystemMonitorViewModel.temperature) ?? "—")
            UsageMenuRow("Display activity", snapshot.performance.displayFramesPerSecond.map { String(format: "%.0f frames/s", $0) } ?? "—")
            if !snapshot.gpuProcesses.isEmpty {
                Divider()
                Text("Top GPU processes").font(AppTheme.Typography.caption.weight(.semibold))
                ForEach(snapshot.gpuProcesses.prefix(5)) { process in UsageMenuRow(process.name, String(format: "%.1f%%", process.percent)) }
            }
        } else { Text("GPU readings are unavailable.").font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary) }
    }

    @ViewBuilder private var battery: some View {
        if let snapshot = monitor.snapshot, let battery = snapshot.battery {
            reading("\(battery.percent)%", detail: battery.isCharging ? "Charging" : battery.isPluggedIn ? "Power adapter" : "On battery")
            Sparkline(values: monitor.batteryHistory, maximum: 1, color: Metric.batteryCharge(percent: battery.percent, isCharging: battery.isCharging)).frame(height: 36)
            UsageMenuRow(battery.isCharging ? "Time to full" : "Time remaining", battery.minutesRemaining.map { "\($0 / 60) hr \($0 % 60) min" } ?? "—")
            UsageMenuRow("Power", MonitorFormat.watts(battery.powerWatts), color: Metric.power.solid)
            UsageMenuRow("Maximum capacity", MonitorFormat.percent(battery.health), color: battery.health.map { $0 < 0.8 ? AppTheme.Status.warning : AppTheme.Status.success })
            UsageMenuRow("Cycles", battery.cycleCount.map(String.init) ?? "—")
            if let watts = battery.adapterWatts { UsageMenuRow("Adapter rating", "\(watts) W") }
            if !snapshot.energyProcesses.isEmpty {
                Divider()
                Text("Energy impact").font(AppTheme.Typography.caption.weight(.semibold))
                ForEach(snapshot.energyProcesses.prefix(5)) { process in UsageMenuRow(process.name, String(format: "%.1f", process.impact)) }
            }
        } else { Text("No built-in battery is reported.").font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary) }
    }

    @ViewBuilder private var drive: some View {
        let disk = model.disk
        if disk.totalBytes > 0 {
            reading("\(ByteSize.string(disk.availableBytes)) free", detail: disk.volumeName)
            UsageBar(fraction: disk.usedFraction, color: model.isLowOnSpace ? AppTheme.Status.warning : Metric.drive.solid)
            VStack(spacing: 5) {
                UsageMenuRow("Used", "\(ByteSize.string(disk.usedBytes)) · \(percent(disk.usedFraction))")
                UsageMenuRow("Capacity", ByteSize.string(disk.totalBytes))
                if let temperature = monitor.snapshot?.temperatures.ssd {
                    UsageMenuRow("Drive temperature", SystemMonitorViewModel.temperature(temperature))
                }
            }
        } else { ProgressView("Reading drive…") }
        if let snapshot = monitor.snapshot {
            Divider()
            HStack {
                Text("Drive activity").font(AppTheme.Typography.callout.weight(.semibold))
                Spacer()
                Text("All drives").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            DualSparkline(first: monitor.diskReadHistory, second: monitor.diskWriteHistory,
                          firstColor: Metric.incoming.solid, secondColor: Metric.outgoing.solid).frame(height: 42)
            UsageMenuRow("Read", SystemMonitorViewModel.rate(snapshot.disk.inPerSecond), color: Metric.incoming.solid)
            UsageMenuRow("Write", SystemMonitorViewModel.rate(snapshot.disk.outPerSecond), color: Metric.outgoing.solid)
            if let health = snapshot.environment.hardware.compactMap(\.health).first {
                UsageMenuRow("Drive health", "\(health.remainingLife)% remaining life")
            }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("Top processes").fontWeight(.semibold)
                Spacer()
                Text(kind == .cpu ? "% of one core" : "Resident memory")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }.font(AppTheme.Typography.caption)
            let processes = kind.topProcesses(monitor.menuProcesses())
            if processes.isEmpty {
                Text(monitor.processStatus.message).font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .accessibilityIdentifier("usageProcessStatus")
            } else {
                ForEach(Array(processes.enumerated()), id: \.element.pid) { index, process in
                    let value = kind == .cpu
                        ? "\(Int(process.cpuPercent.rounded()).formatted(.number.grouping(.never)))%"
                        : ByteSize.memory(process.memoryBytes)
                    HStack {
                        Text(process.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 10)
                        Text(value).monospacedDigit().foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .font(AppTheme.Typography.callout)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(process.name), \(value)")
                    .accessibilityIdentifier("usageProcess\(index)")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 2) {
            if kind == .drive {
                MenuRow(title: "Open Drive in Finder", symbol: "folder") {
                    close { NSWorkspace.shared.open(model.disk.volumeURL ?? FileManager.default.homeDirectoryForCurrentUser) }
                }
                MenuRow(title: "Disk Usage", symbol: AppSection.diskUsage.symbolName) { close { model.show(.diskUsage) } }
                MenuRow(title: "Find Large Files", symbol: AppSection.largeFiles.symbolName) { close { model.show(.largeFiles) } }
            } else if kind == .cpu || kind == .memory {
                MenuRow(title: "View All Processes", symbol: "list.bullet") {
                    close {
                        monitor.processSort = kind == .cpu ? .cpu : .memory
                        model.show(.systemMonitor)
                        monitor.scrollToProcesses = true
                    }
                }
                MenuRow(title: "Open Activity Monitor", symbol: "waveform.path.ecg") {
                    close {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else {
                MenuRow(title: "System Monitor", symbol: "chart.xyaxis.line") {
                    close {
                        model.show(.systemMonitor)
                        monitor.activePage = kind == .gpu ? .gpu : .battery
                    }
                }
            }
            MenuRow(title: "Menu Bar Settings", symbol: "menubar.rectangle") {
                close { model.settings.selectedTab = .menuBar; model.show(.settings) }
            }
            MenuRow(title: "Quit CachePop", symbol: "power") { model.quitCompletely() }
        }
    }

    private func reading(_ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(detail).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    private func dismissMenu() {
        if let onClose { onClose() } else { dismiss() }
    }
    private func close(_ action: () -> Void) { dismissMenu(); action() }
}

struct UsageMenuRow: View {
    let title: String
    let value: String
    var color: Color?
    init(_ title: String, _ value: String, color: Color? = nil) { self.title = title; self.value = value; self.color = color }
    var body: some View {
        HStack {
            if let color {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(title).foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
        }.font(AppTheme.Typography.callout)
    }
}
