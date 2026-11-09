import AppKit
import SwiftUI

/// Live CPU, memory, temperature, fans, disk, network and battery, plus the busiest apps.
struct SystemMonitorView: View {
    @Bindable var model: SystemMonitorViewModel
    let fanControl: FanControlViewModel
    let disk: DiskInfo
    /// Opens Settings › Menu Bar, where the temperature and fan readout is switched on.
    let onOpenMenuBarSettings: () -> Void
    let onOpenSection: (AppSection) -> Void

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                MenuBarOptionsRow(action: onOpenMenuBarSettings)

                header

                if let snapshot = model.snapshot {
                    // Cards in a row share its height, so a tall Fans card doesn't leave gaps.
                    Grid(horizontalSpacing: AppTheme.Spacing.m, verticalSpacing: AppTheme.Spacing.m) {
                        GridRow {
                            CPUCard(model: model, snapshot: snapshot)
                            MemoryCard(model: model, memory: snapshot.memory)
                        }
                        GridRow {
                            TemperatureCard(model: model, temperatures: snapshot.temperatures)
                            FansCard(model: model, control: fanControl, fans: snapshot.fans)
                        }
                        GridRow {
                            DiskCard(model: model, disk: disk, throughput: snapshot.disk, onOpenSection: onOpenSection)
                            NetworkCard(model: model, throughput: snapshot.network)
                        }
                    }
                    if let battery = snapshot.battery {
                        BatteryCard(battery: battery, temperature: snapshot.temperatures.battery)
                    }
                    ProcessesCard(model: model)
                        .id("processes")
                } else {
                    ProgressView("Reading sensors…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.m)
        }
        .onChange(of: model.scrollToProcesses) { _, scroll in
            guard scroll else { return }
            withAnimation { proxy.scrollTo("processes", anchor: .bottom) }
            model.scrollToProcesses = false
        }
        }
        .onAppear { model.begin("section") }
        .onDisappear { model.end("section") }
        .confirmationDialog(
            "Quit \(model.processToQuit?.name ?? "")?",
            isPresented: Binding(get: { model.processToQuit != nil }, set: { if !$0 { model.processToQuit = nil } }),
            presenting: model.processToQuit
        ) { process in
            Button("Quit") { model.quit(process) }
            Button("Cancel", role: .cancel) { model.processToQuit = nil }
        } message: { _ in
            Text("It quits the same way as choosing Quit in the app. If something isn't saved, the app asks first.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(systemLine)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let snapshot = model.snapshot {
                let memory = ByteSize.memory(snapshot.memory.used).split(separator: " ").map(String.init)
                HStack(alignment: .top, spacing: 0) {
                    TapeStat(caption: "CPU", value: "\(Int((snapshot.cpu.total * 100).rounded()))", unit: "%",
                             fraction: snapshot.cpu.total, color: Metric.cpu.solid, leading: "0", trailing: "100%")
                    statDivider
                    TapeStat(caption: "Memory", value: memory.first ?? "0", unit: memory.count > 1 ? memory[1] : "",
                             fraction: snapshot.memory.usedFraction, color: Metric.memory.solid,
                             leading: "0", trailing: ByteSize.memory(snapshot.memory.total))
                    statDivider
                    TapeStat(caption: "Chip", value: snapshot.temperatures.chip.map { "\(Int($0.rounded()))" } ?? "—", unit: "°C",
                             fraction: ((snapshot.temperatures.chip ?? 20) - 20) / 85,
                             color: model.isHot ? AppTheme.Status.warning : Metric.temperature.solid,
                             leading: "20°", trailing: "105°")
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.separator)
            .frame(width: 1, height: 60)
            .padding(.horizontal, AppTheme.Spacing.l)
    }

    private var systemLine: String {
        let memory = ByteSize.memory(Int64(ProcessInfo.processInfo.physicalMemory))
        let version = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .components(separatedBy: " (").first ?? ""
        let uptime = Duration.seconds(ProcessInfo.processInfo.systemUptime)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
        return "\(model.chipName) · \(memory) memory · macOS \(version) · up \(uptime)"
    }
}

// MARK: - Menu bar options

/// A row card at the top that opens Settings › Menu Bar, where the temperature and fan
/// readout beside the menu bar icon is switched on.
private struct MenuBarOptionsRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.s + 2) {
                IconTile(symbolName: "menubar.rectangle", size: AppTheme.Layout.rowIcon)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Menu bar options")
                        .font(AppTheme.Typography.headline)
                    Text("Show the chip temperature and fan speed beside the menu bar icon.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer(minLength: AppTheme.Spacing.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .card()
        .accessibilityHint("Opens Settings")
    }
}

// MARK: - Card

private struct MonitorCard<Content: View>: View {
    let title: String
    let symbol: String
    let value: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
                IconTile(symbolName: symbol, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppTheme.Typography.headline)
                    if let detail {
                        Text(detail)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: AppTheme.Spacing.xs)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            content
        }
        .padding(AppTheme.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: 164, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var color: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .font(AppTheme.Typography.callout)
    }
}

// MARK: - CPU

private struct CPUCard: View {
    let model: SystemMonitorViewModel
    let snapshot: SystemSnapshot

    var body: some View {
        MonitorCard(
            title: "CPU",
            symbol: "cpu",
            value: "\(Int((snapshot.cpu.total * 100).rounded()))%",
            detail: coresLine
        ) {
            Sparkline(values: model.cpuHistory, maximum: 1, color: Metric.cpu.solid)
                .frame(minHeight: 38, maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(snapshot.cpu.perCore.enumerated()), id: \.offset) { _, load in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(AppTheme.Colors.track)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Metric.cpu.solid.opacity(0.85))
                            .frame(height: max(18 * load, 2))
                    }
                    .frame(height: 18)
                    .animation(AppTheme.Motion.standard, value: load)
                }
            }
            .help("Each bar is one core")

            HStack(spacing: AppTheme.Spacing.m) {
                StatRow(label: "Apps", value: percent(snapshot.cpu.user))
                StatRow(label: "System", value: percent(snapshot.cpu.system))
                if let load = snapshot.loadAverage.first {
                    StatRow(label: "Load", value: String(format: "%.2f", load))
                }
            }
        }
    }

    private var coresLine: String {
        let kinds = model.cores
        guard kinds.performance > 0 else { return "\(snapshot.cpu.perCore.count) cores" }
        return "\(kinds.performance) performance · \(kinds.efficiency) efficiency cores"
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

// MARK: - Memory

private struct MemoryCard: View {
    let model: SystemMonitorViewModel
    let memory: MemorySample

    private var parts: [(String, Int64, Color)] {
        [
            ("Apps", memory.app, Metric.memory.solid),
            ("Wired", memory.wired, AppTheme.Palette.blue.solid),
            ("Compressed", memory.compressed, AppTheme.Palette.rose.solid),
            ("Cached files", memory.cached, AppTheme.Palette.graphite.solid.opacity(0.6))
        ]
    }

    var body: some View {
        MonitorCard(
            title: "Memory",
            symbol: "memorychip",
            value: ByteSize.memory(memory.used),
            detail: "of \(ByteSize.memory(memory.total)) · pressure \(memory.pressure.title.lowercased())"
        ) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle()
                            .fill(part.2)
                            .frame(width: max(proxy.size.width * CGFloat(Double(part.1) / Double(max(memory.total, 1))) - 2, 0))
                    }
                    Rectangle().fill(AppTheme.Colors.track)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .animation(AppTheme.Motion.standard, value: memory)

            Grid(alignment: .leading, horizontalSpacing: AppTheme.Spacing.m, verticalSpacing: 5) {
                GridRow {
                    StatRow(label: parts[0].0, value: ByteSize.memory(parts[0].1), color: parts[0].2)
                    StatRow(label: parts[1].0, value: ByteSize.memory(parts[1].1), color: parts[1].2)
                }
                GridRow {
                    StatRow(label: parts[2].0, value: ByteSize.memory(parts[2].1), color: parts[2].2)
                    StatRow(label: parts[3].0, value: ByteSize.memory(parts[3].1), color: parts[3].2)
                }
            }

            Sparkline(values: model.memoryHistory, maximum: 1, color: Metric.memory.solid)
                .frame(minHeight: 26, maxHeight: .infinity)

            HStack(spacing: AppTheme.Spacing.xs) {
                Pill(text: "Pressure: \(memory.pressure.title)", symbolName: "gauge.with.dots.needle.33percent",
                     tone: memory.pressure == .normal ? .success : .warning)
                if memory.swapUsed > 0 {
                    Pill(text: "Swap \(ByteSize.memory(memory.swapUsed))", symbolName: "arrow.left.arrow.right")
                }
            }
        }
    }
}

// MARK: - Temperature

private struct TemperatureCard: View {
    let model: SystemMonitorViewModel
    let temperatures: TemperatureSample

    var body: some View {
        MonitorCard(
            title: "Temperature",
            symbol: "thermometer.medium",
            value: temperatures.chip.map(SystemMonitorViewModel.temperature) ?? "—",
            detail: "Chip average"
        ) {
            if temperatures.chip == nil {
                InlineNote(text: "This Mac's temperature sensors couldn't be read.")
            } else {
                Sparkline(values: model.temperatureHistory, minimum: 20, maximum: 105,
                          color: model.isHot ? AppTheme.Status.warning : Metric.temperature.solid)
                    .frame(minHeight: 38, maxHeight: .infinity)
            }

            HStack(spacing: AppTheme.Spacing.m) {
                if let memory = temperatures.memory {
                    StatRow(label: "Memory", value: SystemMonitorViewModel.temperature(memory))
                }
                if let ssd = temperatures.ssd {
                    StatRow(label: "SSD", value: SystemMonitorViewModel.temperature(ssd))
                }
                if let battery = temperatures.battery {
                    StatRow(label: "Battery", value: SystemMonitorViewModel.temperature(battery))
                }
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
                Pill(text: model.thermalTitle, symbolName: model.isHot ? "flame" : "checkmark", tone: model.isHot ? .warning : .success)
                Text(model.thermalExplanation)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Fans

private struct FansCard: View {
    let model: SystemMonitorViewModel
    let control: FanControlViewModel
    let fans: [FanSample]

    var body: some View {
        MonitorCard(
            title: "Fans",
            symbol: "fanblades",
            value: fans.isEmpty ? "None" : "\(Int(fans.map(\.rpm).max() ?? 0).formatted()) rpm",
            detail: fans.isEmpty ? "Silent, passive cooling"
                : "\(fans.count) \(fans.count == 1 ? "fan" : "fans") · \(control.isCustom ? "custom speed" : "managed by macOS")"
        ) {
            if fans.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("This Mac has no fans. It cools through its case, so it's always silent.")
                        .font(AppTheme.Typography.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("When it gets hot, macOS slows the chip a little instead of spinning a fan. If that happens often, give it a hard, cool surface and close apps you aren't using.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: AppTheme.Spacing.s) {
                    ForEach(fans) { fan in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Fan \(fan.index + 1)")
                                    .font(AppTheme.Typography.callout.weight(.medium))
                                Spacer()
                                Text("\(Int(fan.rpm).formatted()) rpm")
                                    .font(AppTheme.Typography.callout)
                                    .monospacedDigit()
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(AppTheme.Colors.track)
                                    Capsule()
                                        .fill(Metric.fans.solid)
                                        .frame(width: max(proxy.size.width * fan.fraction, 4))
                                }
                            }
                            .frame(height: 6)
                            HStack {
                                Text("\(Int(fan.minimum).formatted()) rpm")
                                Spacer()
                                Text("\(Int(fan.maximum).formatted()) rpm max")
                            }
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }
                    RowDivider(leadingInset: 0)
                    FanControlPanel(control: control, fans: fans)
                }
            }
        }
    }
}

/// Automatic or custom fan speeds, and the one-time helper setup.
private struct FanControlPanel: View {
    let control: FanControlViewModel
    let fans: [FanSample]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            switch control.status {
            case .notInstalled:
                Text("Set fan speeds yourself, for example to keep the Mac cooler during a long build.")
                    .font(AppTheme.Typography.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn On Fan Control…", action: control.install)
                Text("Installs a small helper with administrator rights. macOS asks you to allow it.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .needsApproval:
                InlineNote(text: "Allow “CachePop” in System Settings › General › Login Items & Extensions.", symbolName: "hand.raised")
                HStack {
                    Button("Open System Settings", action: control.openApprovalSettings)
                    Button("Check Again", action: control.refreshStatus)
                }
            case .unavailable(let reason):
                InlineNote(text: reason, symbolName: "exclamationmark.triangle", tone: .warning)
            case .ready:
                Picker("Fan speed", selection: modeBinding) {
                    ForEach(FanControlViewModel.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(control.isWorking)

                if control.isCustom {
                    ForEach(fans) { fan in
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text("Fan \(fan.index + 1)")
                                .font(AppTheme.Typography.callout)
                                .frame(width: 44, alignment: .leading)
                            Slider(value: targetBinding(fan), in: fan.minimum...max(fan.maximum, fan.minimum + 1), step: 100) { editing in
                                if !editing { Task { await control.apply(fans) } }
                            }
                            Text("\(Int(control.target(for: fan)).formatted()) rpm")
                                .font(AppTheme.Typography.callout)
                                .monospacedDigit()
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                    HStack {
                        Button("Full Speed") { Task { await control.applyMaximum(fans) } }
                            .controlSize(.small)
                        Spacer()
                    }
                }
                Text("Fans never go below what macOS allows, and go back to automatic when CachePop quits or the Mac gets hot.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = control.message {
                InlineNote(text: message, symbolName: "info.circle")
            }
        }
    }

    private var modeBinding: Binding<FanControlViewModel.Mode> {
        Binding(
            get: { control.mode },
            set: { mode in
                Task {
                    if mode == .custom { await control.apply(fans) } else { await control.setAutomatic() }
                }
            }
        )
    }

    private func targetBinding(_ fan: FanSample) -> Binding<Double> {
        Binding(get: { control.target(for: fan) }, set: { control.targets[fan.index] = $0 })
    }
}

// MARK: - Disk

private struct DiskCard: View {
    let model: SystemMonitorViewModel
    let disk: DiskInfo
    let throughput: Throughput
    let onOpenSection: (AppSection) -> Void

    var body: some View {
        MonitorCard(
            title: "Disk",
            symbol: "internaldrive",
            value: "\(ByteSize.string(disk.availableBytes)) free",
            detail: "Macintosh HD · \(Int((disk.usedFraction * 100).rounded()))% used"
        ) {
            DualSparkline(first: model.diskReadHistory, second: model.diskWriteHistory,
                          firstColor: Metric.incoming.solid, secondColor: Metric.outgoing.solid)
                .frame(minHeight: 38, maxHeight: .infinity)
            HStack(spacing: AppTheme.Spacing.m) {
                StatRow(label: "Read", value: SystemMonitorViewModel.rate(throughput.inPerSecond), color: Metric.incoming.solid)
                StatRow(label: "Write", value: SystemMonitorViewModel.rate(throughput.outPerSecond), color: Metric.outgoing.solid)
            }
            Button {
                onOpenSection(.diskUsage)
            } label: {
                Label("See what's using space", systemImage: "arrow.turn.down.right")
                    .font(AppTheme.Typography.callout)
            }
            .buttonStyle(.link)
        }
    }
}

// MARK: - Network

private struct NetworkCard: View {
    let model: SystemMonitorViewModel
    let throughput: Throughput

    var body: some View {
        MonitorCard(
            title: "Network",
            symbol: "arrow.up.arrow.down",
            value: SystemMonitorViewModel.rate(throughput.inPerSecond),
            detail: "Wi-Fi and Ethernet · download"
        ) {
            DualSparkline(first: model.networkInHistory, second: model.networkOutHistory,
                          firstColor: Metric.incoming.solid, secondColor: Metric.outgoing.solid)
                .frame(minHeight: 38, maxHeight: .infinity)
            HStack(spacing: AppTheme.Spacing.m) {
                StatRow(label: "Down", value: SystemMonitorViewModel.rate(throughput.inPerSecond), color: Metric.incoming.solid)
                StatRow(label: "Up", value: SystemMonitorViewModel.rate(throughput.outPerSecond), color: Metric.outgoing.solid)
            }
        }
    }
}

// MARK: - Battery

private struct BatteryCard: View {
    let battery: BatterySample
    let temperature: Double?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            IconTile(symbolName: symbol, size: 24, tone: tone)
            VStack(alignment: .leading, spacing: 1) {
                Text("Battery")
                    .font(AppTheme.Typography.headline)
                Text(status)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: AppTheme.Spacing.m)
            HStack(spacing: AppTheme.Spacing.l) {
                if let health = battery.health {
                    stat("Health", "\(Int((health * 100).rounded()))%")
                }
                if let cycles = battery.cycleCount {
                    stat("Cycles", "\(cycles)")
                }
                if let temperature {
                    stat("Temperature", SystemMonitorViewModel.temperature(temperature))
                }
            }
            Text("\(battery.percent)%")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(AppTheme.Spacing.m)
        .card()
    }

    /// Green while charging, orange when it's running low on battery; otherwise neutral.
    private var tone: IconTile.Tone {
        if battery.isCharging { return .success }
        if !battery.isPluggedIn && battery.percent < 20 { return .warning }
        return .neutral
    }

    private var symbol: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var status: String {
        var text = battery.isCharging ? "Charging" : battery.isPluggedIn ? "On power adapter" : "On battery"
        if let minutes = battery.minutesRemaining {
            let time = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            text += battery.isCharging ? " · full in \(time)" : " · \(time) left"
        }
        return text
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(AppTheme.Typography.headline)
                .monospacedDigit()
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Processes

private struct ProcessesCard: View {
    @Bindable var model: SystemMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            CardHeader("Busiest apps and processes", subtitle: "What's using the most \(model.processSort == .cpu ? "CPU" : "memory") right now",
                       symbolName: "list.number") {
                Picker("Sort by", selection: $model.processSort) {
                    ForEach(ProcessSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
            RowDivider(leadingInset: 0)

            if model.processes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                let top = model.topProcesses
                let largest = model.processSort == .cpu
                    ? max(top.first?.cpuPercent ?? 1, 1)
                    : Double(max(top.first?.memoryBytes ?? 1, 1))
                ForEach(Array(top.enumerated()), id: \.element.id) { index, process in
                    if index > 0 { RowDivider(leadingInset: AppTheme.Spacing.m + AppTheme.Layout.rowIcon + AppTheme.Spacing.s) }
                    ProcessRow(model: model, process: process, largest: largest)
                }
            }
        }
        .card()
    }
}

private struct ProcessRow: View {
    let model: SystemMonitorViewModel
    let process: ProcessUsage
    let largest: Double

    private var app: NSRunningApplication? { model.app(for: process) }
    private var value: Double { model.processSort == .cpu ? process.cpuPercent : Double(process.memoryBytes) }

    var body: some View {
        let running = model.runningApp(for: process)
        HStack(spacing: AppTheme.Spacing.s) {
            Group {
                if let icon = running?.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.Colors.tile))
                }
            }
            .frame(width: AppTheme.Layout.rowIcon, height: AppTheme.Layout.rowIcon)

            VStack(alignment: .leading, spacing: 3) {
                Text(running?.localizedName ?? process.name)
                    .font(AppTheme.Typography.body.weight(.medium))
                    .lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.Colors.track)
                        Capsule()
                            .fill((model.processSort == .cpu ? Metric.cpu : Metric.memory).solid.opacity(0.85))
                            .frame(width: max(proxy.size.width * min(value / largest, 1), 3))
                    }
                }
                .frame(height: 4)
                .frame(maxWidth: 240)
            }

            Spacer(minLength: AppTheme.Spacing.s)

            Text(model.processSort == .cpu ? String(format: "%.1f%%", process.cpuPercent) : ByteSize.memory(process.memoryBytes))
                .font(AppTheme.Typography.size)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)

            if app != nil {
                Button("Quit") { model.processToQuit = process }
                    .controlSize(.small)
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 7)
        .hoverHighlight()
    }
}
