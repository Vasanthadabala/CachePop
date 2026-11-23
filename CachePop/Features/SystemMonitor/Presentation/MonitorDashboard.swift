import AppKit
import SwiftUI

enum MonitorFormat {
    static func percent(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    static func frequency(_ value: Double?) -> String { value.map { String(format: "%.2f GHz", $0 / 1_000) } ?? "—" }
    static func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "—" }
}

struct MonitorGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(AppTheme.Typography.title2).accessibilityAddTraits(.isHeader) }
            content
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct MonitorSummary: View {
    let title: String
    let value: String
    let detail: String
    let fraction: Double
    var ringSymbol: String? = nil
    var color: Color = Metric.cpu.solid
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(AppTheme.Colors.track, lineWidth: 5)
                Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                if let ringSymbol { Image(systemName: ringSymbol).font(.system(size: 17)).foregroundStyle(AppTheme.Colors.textSecondary) }
                else { Text(MonitorFormat.percent(fraction)).font(.system(size: 12, weight: .semibold)).monospacedDigit() }
            }.frame(width: 52, height: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppTheme.Typography.headline)
                Text(detail).font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
        }.padding(14).card()
    }
}

struct MonitorChart: View {
    let title: String
    let values: [Double]
    var maximum: Double? = 1
    var unit = "%"
    var secondary: [Double]? = nil
    var height: CGFloat = 100
    var scaleTop: String? = nil
    var scaleBottom = "0"
    var color: Color = Metric.cpu.solid
    var secondaryColor: Color = Metric.outgoing.solid
    var body: some View {
        MonitorGroup(title: title) {
            HStack(spacing: 7) {
                VStack {
                    Text(scaleTop ?? (unit == "%" ? "100%" : maximum.map { $0 >= 1_000 ? ByteSize.string(Int64($0)) : String(format: "%.0f%@", $0, unit) } ?? ""))
                    Spacer()
                    Text(scaleBottom)
                }.font(.system(size: 10)).foregroundStyle(AppTheme.Colors.textSecondary).frame(width: unit == "%" ? 28 : 38, alignment: .trailing)
                ZStack {
                    VStack { ForEach(0..<4) { _ in Rectangle().fill(AppTheme.Colors.separator).frame(height: 0.5); Spacer(minLength: 0) } }
                    if let secondary {
                        DualSparkline(first: values, second: secondary, firstColor: color, secondColor: secondaryColor)
                    } else { Sparkline(values: values, maximum: maximum, color: color) }
                }
            }.frame(height: height)
            HStack { Text("2 min ago"); Spacer(); Text("Now") }
                .font(.system(size: 10)).foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }
}

struct CPUOverview: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot
    var body: some View {
        MonitorSummary(title: model.chipName, value: MonitorFormat.percent(snapshot.cpu.total),
                       detail: "\(model.cores.efficiency) efficiency · \(model.cores.performance) performance cores · \(snapshot.temperatures.chip.map(SystemMonitorViewModel.temperature) ?? "—")", fraction: snapshot.cpu.total, ringSymbol: "cpu")
        MonitorGroup {
            HStack {
                StatRow(label: "Apps", value: MonitorFormat.percent(snapshot.cpu.user), color: Metric.cpu.solid)
                StatRow(label: "System", value: MonitorFormat.percent(snapshot.cpu.system), color: Metric.cpuSystem.solid)
                StatRow(label: "Idle", value: MonitorFormat.percent(max(1 - snapshot.cpu.total, 0)), color: Metric.idle.solid)
            }
        }
        MonitorChart(title: "Usage history", values: model.cpuHistory)
        MonitorGroup(title: "Load per core") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 9) {
                ForEach(Array(snapshot.cpu.perCore.enumerated()), id: \.offset) { index, load in
                    let color = Metric.core(model.coreTopology[index]).solid
                    VStack(spacing: 4) {
                        StatRow(label: CPUCoreTopology.label(index, topology: model.coreTopology), value: MonitorFormat.percent(load))
                        ProgressView(value: load).tint(color).controlSize(.small)
                    }
                }
            }
        }
        HStack(alignment: .top, spacing: 12) {
            MonitorGroup(title: "Average load") {
                ForEach(Array(snapshot.loadAverage.prefix(3).enumerated()), id: \.offset) { index, value in
                    StatRow(label: ["1 minute", "5 minutes", "15 minutes"][index], value: String(format: "%.2f", value))
                }
            }
            MonitorGroup(title: "Frequency") {
                StatRow(label: "All cores", value: MonitorFormat.frequency(snapshot.performance.cpuMHz(efficiencyCores: model.cores.efficiency, performanceCores: model.cores.performance)))
                StatRow(label: "Efficiency", value: MonitorFormat.frequency(snapshot.performance.efficiencyMHz), color: Metric.efficiency.solid)
                StatRow(label: "Performance", value: MonitorFormat.frequency(snapshot.performance.performanceMHz), color: Metric.performance.solid)
            }
        }
        MonitorProcesses(model: model).id("processes")
    }
}

struct MemoryOverview: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot
    private var memory: MemorySample { snapshot.memory }
    var body: some View {
        MonitorSummary(title: "Memory", value: ByteSize.memory(memory.used), detail: "of \(ByteSize.memory(memory.total)) · \(memory.pressure.title)", fraction: memory.usedFraction, color: Metric.memory.solid)
        MonitorChart(title: "Usage history", values: model.memoryHistory, color: Metric.memory.solid)
        HStack(alignment: .top, spacing: 12) {
            MonitorGroup(title: "Breakdown") {
                StatRow(label: "App memory", value: ByteSize.memory(memory.app), color: Metric.memory.solid)
                StatRow(label: "Wired", value: ByteSize.memory(memory.wired), color: Metric.wired.solid)
                StatRow(label: "Compressed", value: ByteSize.memory(memory.compressed), color: Metric.compressed.solid)
                StatRow(label: "Cached files", value: ByteSize.memory(memory.cached), color: Metric.cached.solid)
            }
            MonitorGroup(title: "Available") {
                StatRow(label: "Available memory", value: ByteSize.memory(max(memory.total - memory.used, 0)))
                StatRow(label: "Free pages", value: ByteSize.memory(memory.free))
                StatRow(label: "Swap used", value: ByteSize.memory(memory.swapUsed))
                StatRow(label: "Pressure", value: memory.pressure.title + (memory.pressureFraction.map { " · \(MonitorFormat.percent($0))" } ?? ""), color: memory.total > 0 ? memory.pressure.color : nil)
            }
        }
        HStack(alignment: .top, spacing: 12) {
            MonitorChart(title: "Memory pressure", values: model.memoryPressureHistory, unit: "", height: 60,
                         scaleTop: memory.pressureFraction == nil ? "High" : "100%", scaleBottom: memory.pressureFraction == nil ? "Normal" : "0", color: Metric.memory.solid)
            MonitorChart(title: "Swap", values: model.swapHistory, maximum: max(model.swapHistory.max() ?? 0, 1_048_576), unit: "B", height: 60, color: Metric.compressed.solid)
        }
        MonitorProcesses(model: model).id("processes")
    }
}

struct GPUOverview: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot
    var body: some View {
        VStack(spacing: 14) {
            ForEach(snapshot.gpus) { gpu in
                MonitorSummary(title: gpu.name, value: MonitorFormat.percent(gpu.utilization), detail: "Graphics processor", fraction: gpu.utilization ?? 0, ringSymbol: "display", color: Metric.gpu.solid)
                MonitorChart(title: "GPU utilisation", values: model.gpuHistories[gpu.id] ?? [], color: Metric.gpu.solid)
                HStack(spacing: 12) {
                    MonitorChart(title: "Renderer", values: model.rendererHistories[gpu.id] ?? [], height: 70, color: Metric.renderer.solid)
                    MonitorChart(title: "Tiler", values: model.tilerHistories[gpu.id] ?? [], height: 70, color: Metric.tiler.solid)
                }
                if !model.displayFrameHistory.isEmpty {
                    MonitorChart(title: "Display activity", values: model.displayFrameHistory, maximum: max(model.displayFrameHistory.max() ?? 1, 1), unit: " fps", height: 60, color: Metric.gpu.solid)
                }
                if !model.neuralPowerHistory.isEmpty {
                    MonitorChart(title: "Neural Engine power", values: model.neuralPowerHistory, maximum: max(model.neuralPowerHistory.max() ?? 1, 1), unit: " W", height: 60, color: Metric.power.solid)
                }
                MonitorGroup(title: "Details") {
                    StatRow(label: "GPU temperature", value: snapshot.temperatures.gpu.map(SystemMonitorViewModel.temperature) ?? "—")
                    StatRow(label: "Renderer utilisation", value: MonitorFormat.percent(gpu.renderer), color: Metric.renderer.solid)
                    StatRow(label: "Tiler utilisation", value: MonitorFormat.percent(gpu.tiler), color: Metric.tiler.solid)
                    StatRow(label: "GPU memory", value: gpu.memoryBytes.map(ByteSize.memory) ?? "—")
                    StatRow(label: "GPU power", value: MonitorFormat.watts(snapshot.performance.gpuWatts))
                    StatRow(label: "Neural Engine power", value: MonitorFormat.watts(snapshot.performance.neuralWatts))
                    StatRow(label: "Display activity", value: snapshot.performance.displayFramesPerSecond.map { String(format: "%.0f frames/s", $0) } ?? "—")
                    Text("Display activity combines compositor swaps across displays.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
            if snapshot.gpus.isEmpty { MonitorGroup(title: "GPU") { Text("This graphics driver does not expose utilisation readings.").foregroundStyle(AppTheme.Colors.textSecondary) } }
            MonitorGroup(title: "Top GPU processes") {
                ActivityColumnHeader(value: "GPU")
                ForEach(snapshot.gpuProcesses) { process in ActivityProcessRow(pid: process.pid, name: process.name, value: String(format: "%.1f%%", process.percent)) }
                if snapshot.gpuProcesses.isEmpty { Text("Waiting for GPU activity counters…").font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary) }
            }
        }.accessibilityIdentifier("gpuMonitorCard")
    }
}

struct DriveOverview: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot
    let disk: DiskInfo
    let onOpenSection: (AppSection) -> Void
    @State private var selectedVolumeID = "/"
    private var volume: MountedVolume? { snapshot.environment.volumes.first { $0.id == selectedVolumeID } }
    private var activity: DriveActivity? { snapshot.driveActivity.first { $0.id == volume?.driverID } }
    private var reads: [Double] { volume?.driverID.flatMap { model.driveReadHistories[$0] } ?? model.diskReadHistory }
    private var writes: [Double] { volume?.driverID.flatMap { model.driveWriteHistories[$0] } ?? model.diskWriteHistory }
    var body: some View {
        if !snapshot.environment.volumes.isEmpty {
            Picker("Drive", selection: $selectedVolumeID) {
                ForEach(snapshot.environment.volumes) { Text($0.id == "/" ? disk.volumeName : $0.name).tag($0.id) }
            }.pickerStyle(.menu).frame(maxWidth: 260, alignment: .leading).accessibilityIdentifier("monitorDrivePicker")
        }
        MonitorSummary(title: volume?.id == "/" ? disk.volumeName : volume?.name ?? disk.volumeName,
                       value: "\(ByteSize.string(volume?.available ?? disk.availableBytes)) free",
                       detail: "\(ByteSize.string(volume?.total ?? disk.totalBytes)) capacity", fraction: volume?.usedFraction ?? disk.usedFraction, color: Metric.drive.solid)
        DriveHistoryChart(title: activity == nil ? "Read / Write history · all drives" : "Read / Write history",
                          reads: reads, writes: writes)
        MonitorGroup(title: "Activity") {
            HStack {
                StatRow(label: "Read", value: ByteSize.rate(activity?.throughput.inPerSecond ?? snapshot.disk.inPerSecond), color: Metric.incoming.solid)
                StatRow(label: "Write", value: ByteSize.rate(activity?.throughput.outPerSecond ?? snapshot.disk.outPerSecond), color: Metric.outgoing.solid)
            }
            HStack { StatRow(label: "Read since boot", value: ByteSize.string(Int64(clamping: activity?.counters.read ?? snapshot.diskTotals.read))); StatRow(label: "Written since boot", value: ByteSize.string(Int64(clamping: activity?.counters.written ?? snapshot.diskTotals.written))) }
            if let volume {
                StatRow(label: "Filesystem", value: volume.format)
                StatRow(label: "BSD name", value: volume.bsdName ?? "—")
                StatRow(label: "Writable", value: volume.isReadOnly ? "No" : "Yes")
                StatRow(label: "Encrypted", value: volume.isEncrypted.map { $0 ? "Yes" : "No" } ?? "—")
                Button("Open Drive in Finder", systemImage: "folder") { NSWorkspace.shared.open(URL(fileURLWithPath: volume.id)) }.buttonStyle(.link)
            }
            Button("See what's using space", systemImage: "arrow.turn.down.right") { onOpenSection(.diskUsage) }.buttonStyle(.link)
        }
        MountedVolumesView(environment: snapshot.environment)
        DriveHardwareDetails(hardware: snapshot.environment.hardware)
        MonitorGroup(title: "Top drive processes") {
            HStack { Text("Process"); Spacer(); Text("Read / Write") }.font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            ForEach(snapshot.driveProcesses) { process in
                ActivityProcessRow(pid: process.pid, name: process.name, value: "\(ByteSize.rate(process.readPerSecond)) / \(ByteSize.rate(process.writePerSecond))")
            }
            if snapshot.driveProcesses.isEmpty { Text("Waiting for drive activity counters…").font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary) }
        }
    }
}

struct DriveHardwareDetails: View {
    let hardware: [DriveHardware]
    var body: some View {
        ForEach(hardware) { device in
            MonitorGroup(title: device.model) {
                StatRow(label: "Connection", value: device.connection)
                if let health = device.health {
                    StatRow(label: "Remaining life", value: "\(health.remainingLife)%", color: health.isWarning ? AppTheme.Status.warning : AppTheme.Status.success)
                    StatRow(label: "Temperature", value: health.temperature.map(SystemMonitorViewModel.temperature) ?? "—")
                    StatRow(label: "Lifetime read", value: ByteSize.string(health.totalRead))
                    StatRow(label: "Lifetime written", value: ByteSize.string(health.totalWritten))
                    StatRow(label: "Power-on hours", value: health.powerOnHours.formatted())
                    StatRow(label: "Power cycles", value: health.powerCycles.formatted())
                    StatRow(label: "Unsafe shutdowns", value: health.unsafeShutdowns.formatted())
                    StatRow(label: "Media errors", value: health.mediaErrors.formatted(), color: health.mediaErrors > 0 ? AppTheme.Status.warning : nil)
                    StatRow(label: "Available spare", value: "\(health.availableSpare)%")
                    StatRow(label: "Critical warning", value: health.criticalWarning == 0 ? "None" : "Reported by drive", color: health.criticalWarning == 0 ? nil : AppTheme.Status.warning)
                } else { Text("Hardware health is not exposed by this drive.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary) }
            }
        }
    }
}

struct SensorsOverview: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot
    let fanControl: FanControlViewModel
    var body: some View {
        MonitorGroup(title: "Temperatures") {
            StatRow(label: "CPU average", value: snapshot.temperatures.chip.map(SystemMonitorViewModel.temperature) ?? "—", color: Metric.cpu.solid)
            StatRow(label: "Hottest CPU", value: snapshot.temperatures.chipMax.map(SystemMonitorViewModel.temperature) ?? "—", color: model.isHot ? AppTheme.Status.warning : nil)
            if let value = snapshot.temperatures.gpu { StatRow(label: "GPU average", value: SystemMonitorViewModel.temperature(value), color: Metric.gpu.solid) }
            if let value = snapshot.temperatures.memory { StatRow(label: "Memory", value: SystemMonitorViewModel.temperature(value), color: Metric.memory.solid) }
            if let value = snapshot.temperatures.ssd { StatRow(label: "Drive", value: SystemMonitorViewModel.temperature(value), color: Metric.drive.solid) }
            if let value = snapshot.temperatures.battery { StatRow(label: "Battery", value: SystemMonitorViewModel.temperature(value), color: Metric.battery.solid) }
        }
        MonitorChart(title: "CPU temperature history", values: model.temperatureHistory, maximum: 120, unit: "°C", height: 80, color: Metric.temperature.solid)
        MonitorGroup(title: "Power & electrical") {
            ForEach(snapshot.electricalSensors) { sensor in StatRow(label: "\(sensor.name) · \(sensor.kind.rawValue.lowercased())", value: sensor.formatted) }
            StatRow(label: "CPU power", value: MonitorFormat.watts(snapshot.performance.cpuWatts))
            StatRow(label: "GPU power", value: MonitorFormat.watts(snapshot.performance.gpuWatts))
            StatRow(label: "Neural Engine power", value: MonitorFormat.watts(snapshot.performance.neuralWatts))
            StatRow(label: "Memory power", value: MonitorFormat.watts(snapshot.performance.memoryWatts))
        }
        if !model.powerHistory.isEmpty { MonitorChart(title: "System power history", values: model.powerHistory, maximum: max(model.powerHistory.max() ?? 1, 1), unit: " W", height: 60, color: Metric.power.solid) }
        SensorReadingsView(sensors: snapshot.temperatures.sensors)
        MonitorGroup(title: "Fans") {
            if snapshot.fans.isEmpty { Text("Passive cooling · no fans").font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary) }
            else {
                ForEach(snapshot.fans) { fan in StatRow(label: "Fan \(fan.index + 1)", value: "\(Int(fan.rpm)) rpm"); ProgressView(value: fan.fraction).tint(Metric.fans.solid) }
                FanControlPanel(control: fanControl, fans: snapshot.fans)
            }
        }
    }
}

struct BatteryOverview: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot
    var body: some View {
        if let battery = snapshot.battery {
            let chargeColor = Metric.batteryCharge(percent: battery.percent, isCharging: battery.isCharging)
            MonitorSummary(title: "Battery", value: "\(battery.percent)%", detail: battery.isCharging ? "Charging" : battery.isPluggedIn ? "Power adapter" : "On battery", fraction: Double(battery.percent) / 100, ringSymbol: "battery.100percent", color: chargeColor)
            BatteryChargeChart(history: model.chargeHistory, color: chargeColor)
            MonitorGroup(title: "Battery power") {
                StatRow(label: "Power source", value: battery.isPluggedIn ? "Power adapter" : "Battery")
                StatRow(label: battery.isCharging ? "Time to full" : "Time remaining", value: battery.minutesRemaining.map { "\($0 / 60) hr \($0 % 60) min" } ?? "—")
                StatRow(label: "Battery power", value: MonitorFormat.watts(battery.powerWatts))
                StatRow(label: "Voltage", value: battery.voltage.map { String(format: "%.2f V", $0) } ?? "—")
                StatRow(label: "Current", value: battery.amperage.map { String(format: "%.2f A", $0) } ?? "—")
                if battery.isChargingPaused { StatRow(label: "Charging", value: "Paused") }
            }.accessibilityElement(children: .contain).accessibilityLabel("Battery power")
            MonitorGroup(title: "Battery health") {
                StatRow(label: "Maximum capacity", value: MonitorFormat.percent(battery.health), color: battery.health.map { $0 < 0.8 ? AppTheme.Status.warning : AppTheme.Status.success })
                StatRow(label: "Cycles", value: battery.cycleCount.map(String.init) ?? "—")
                StatRow(label: "Temperature", value: snapshot.temperatures.battery.map(SystemMonitorViewModel.temperature) ?? "—")
                capacity("Current charge", battery.currentCapacityMah)
                capacity("Full charge capacity", battery.fullChargeCapacityMah)
                capacity("Design capacity", battery.designCapacityMah)
            }
            if battery.isPluggedIn {
                MonitorGroup(title: "Power adapter") {
                    StatRow(label: "Adapter rating", value: battery.adapterWatts.map { "\($0) W" } ?? "—")
                    StatRow(label: "Voltage", value: battery.adapterVoltage.map { String(format: "%.1f V", $0) } ?? "—")
                    StatRow(label: "Current limit", value: battery.adapterAmperage.map { String(format: "%.2f A", $0) } ?? "—")
                }
            }
            MonitorGroup(title: "Energy impact") {
                ActivityColumnHeader(value: "Impact")
                ForEach(snapshot.energyProcesses) { process in ActivityProcessRow(pid: process.pid, name: process.name, value: String(format: "%.1f", process.impact)) }
                Text("Relative macOS energy score; not watts.").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textTertiary)
            }
        } else { MonitorGroup(title: "Battery") { Text("This Mac does not report a built-in battery.").foregroundStyle(AppTheme.Colors.textSecondary) } }
    }
    private func capacity(_ title: String, _ value: Int?) -> some View { StatRow(label: title, value: value.map { "\($0.formatted()) mAh" } ?? "—") }
}

struct MonitorProcesses: View {
    let model: SystemMonitorViewModel
    var body: some View {
        MonitorGroup(title: "Busiest apps and processes") {
            ActivityColumnHeader(value: model.processSort == .cpu ? "CPU" : "Memory", showsQuitColumn: true)
            if model.processes.isEmpty { Text(model.processStatus.message).font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary) }
            ForEach(model.topProcesses) { process in
                ActivityProcessRow(pid: process.pid, name: process.name,
                                   value: model.processSort == .cpu ? String(format: "%.1f%%", process.cpuPercent) : ByteSize.memory(process.memoryBytes),
                                   showsQuitColumn: true,
                                   onQuit: model.canQuit(process) ? { model.processToQuit = process } : nil)
            }
        }
    }
}

struct ActivityColumnHeader: View {
    let value: String
    var showsQuitColumn = false
    var body: some View {
        HStack(spacing: 12) {
            Text("Process")
            Spacer(minLength: 4)
            Text("PID").frame(width: 48, alignment: .trailing)
            Text(value).frame(width: showsQuitColumn ? 88 : nil, alignment: .trailing).frame(minWidth: 80, alignment: .trailing)
            if showsQuitColumn { Text("Quit").frame(width: 28) }
        }.font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textTertiary)
    }
}

struct ActivityProcessRow: View {
    let pid: Int32
    let name: String
    let value: String
    var showsQuitColumn = false
    var onQuit: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 12) {
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(String(pid)).foregroundStyle(AppTheme.Colors.textTertiary).frame(width: 48, alignment: .trailing)
                .accessibilityIdentifier("processPID-\(pid)")
            Text(value).frame(width: showsQuitColumn ? 88 : nil, alignment: .trailing).frame(minWidth: 80, alignment: .trailing)
                .accessibilityIdentifier("processValue-\(pid)")
            if showsQuitColumn {
                Group {
                    if let onQuit {
                        Button(action: onQuit) {
                            Image(systemName: "xmark.circle").frame(width: 28, height: 18).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(AppTheme.Colors.textTertiary)
                        .accessibilityLabel("Quit \(name)")
                    } else {
                        Color.clear.frame(width: 28, height: 18).accessibilityHidden(true)
                    }
                }.frame(width: 28, height: 18)
            }
        }.font(AppTheme.Typography.callout).monospacedDigit().padding(.vertical, 2)
    }
}
