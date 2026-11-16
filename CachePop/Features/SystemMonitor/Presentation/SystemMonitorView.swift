import AppKit
import SwiftUI

/// Six focused pages, using one sampler and the same compact visual language as the menus.
struct SystemMonitorView: View {
    @Bindable var model: SystemMonitorViewModel
    let fanControl: FanControlViewModel
    let disk: DiskInfo
    let onOpenMenuBarSettings: () -> Void
    let onOpenSection: (AppSection) -> Void
    @State private var showsDetails = false
    private var page: MonitorPage {
        get { model.activePage }
        nonmutating set { model.activePage = newValue }
    }
    @State private var exportError: String?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("\(model.chipName) · \(ByteSize.memory(Int64(ProcessInfo.processInfo.physicalMemory)))")
                        .font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer(minLength: 4)
                    Button("Sensors & Status", systemImage: "list.bullet.rectangle") { showsDetails = true }
                        .accessibilityIdentifier("monitorDetails")
                    Button(model.isRecording ? "Stop Recording" : "Record", systemImage: model.isRecording ? "stop.circle" : "record.circle") {
                        if model.isRecording { model.stopRecording() } else { model.startRecording() }
                    }.accessibilityIdentifier("monitorRecording")
                    Menu {
                        Button("Export CSV", systemImage: "square.and.arrow.up", action: exportLog).disabled(model.logRecords.isEmpty)
                        Button("Menu Bar Settings", systemImage: "menubar.rectangle", action: onOpenMenuBarSettings)
                        if !model.logRecords.isEmpty { Text("\(model.logRecords.count) recorded readings") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 28, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Monitor options")
                    .accessibilityLabel("Monitor options")
                    .accessibilityIdentifier("monitorOptions")
                }.controlSize(.small)
                if let exportError { InlineNote(text: exportError, tone: .warning) }
                Picker("Monitor page", selection: $model.activePage) {
                    ForEach(MonitorPage.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("monitorPages")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let snapshot = model.snapshot {
                            switch page {
                            case .cpu: CPUOverview(model: model, snapshot: snapshot)
                            case .gpu: GPUOverview(model: model, snapshot: snapshot)
                            case .drive: DriveOverview(model: model, snapshot: snapshot, disk: disk, onOpenSection: onOpenSection)
                            case .memory: MemoryOverview(model: model, snapshot: snapshot)
                            case .sensors: SensorsOverview(model: model, snapshot: snapshot, fanControl: fanControl)
                            case .battery: BatteryOverview(model: model, snapshot: snapshot)
                            }
                        } else {
                            ProgressView("Reading sensors…").frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }.frame(maxWidth: .infinity).padding(.bottom, 12).id("monitorPageTop")
                }.accessibilityIdentifier("monitorPageContent")
            }
            .padding(.horizontal, 18).padding(.top, 12)
            .onChange(of: page) { old, new in
                let wasProcesses = old == .cpu || old == .memory
                let wantsProcesses = new == .cpu || new == .memory
                if wasProcesses != wantsProcesses {
                    if wantsProcesses { model.begin("section") } else { model.end("section") }
                }
                if new == .cpu { model.processSort = .cpu }
                if new == .memory { model.processSort = .memory }
                proxy.scrollTo("monitorPageTop", anchor: .top)
            }
            .task(id: model.scrollToProcesses) {
                guard model.scrollToProcesses else { return }
                page = model.processSort == .memory ? .memory : .cpu
                await Task.yield()
                withAnimation { proxy.scrollTo("processes", anchor: .bottom) }
                model.scrollToProcesses = false
            }
        }
        .onAppear { model.begin("monitorDetails"); if page == .cpu || page == .memory { model.begin("section") } }
        .onDisappear { if page == .cpu || page == .memory { model.end("section") }; model.end("monitorDetails") }
        .sheet(isPresented: $showsDetails) { MonitorDetailsView(model: model, disk: disk) }
        .confirmationDialog("Quit \(model.processToQuit?.name ?? "")?",
                            isPresented: Binding(get: { model.processToQuit != nil }, set: { if !$0 { model.processToQuit = nil } }),
                            presenting: model.processToQuit) { process in
            Button("Quit") { model.quit(process) }
            Button("Cancel", role: .cancel) { model.processToQuit = nil }
        } message: { _ in Text("It quits the same way as choosing Quit in the app. If something isn't saved, the app asks first.") }
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CachePop-monitor.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try MonitorLogRecord.csv(model.logRecords).write(to: url, atomically: true, encoding: .utf8); exportError = nil }
        catch { exportError = "The recording couldn't be saved: \(error.localizedDescription)" }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color?
    var body: some View {
        HStack(spacing: 6) {
            if let color {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(label).foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().lineLimit(1)
        }.font(AppTheme.Typography.callout)
    }
}

/// Automatic or custom fan speeds, and the one-time helper setup.
struct FanControlPanel: View {
    let control: FanControlViewModel
    let fans: [FanSample]
    @State private var showsBoostRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            switch control.status {
            case .notInstalled:
                Text("Set fan speeds yourself, for example to keep the Mac cooler during a long build.")
                    .font(AppTheme.Typography.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn On Fan Control…", action: control.install)
                    .accessibilityIdentifier("enableFanControl")
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
                .accessibilityIdentifier("fanControlMode")

                if control.isCustom {
                    ForEach(fans) { fan in
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text("Fan \(fan.index + 1)")
                                .font(AppTheme.Typography.callout)
                                .frame(width: 44, alignment: .leading)
                            Slider(value: targetBinding(fan), in: fan.minimum...max(fan.maximum, fan.minimum + 1), step: 100) { editing in
                                if !editing { Task { await control.apply(fans) } }
                            }
                            .accessibilityLabel("Fan \(fan.index + 1) target speed")
                            .accessibilityIdentifier("fanTarget\(fan.index)")
                            .disabled(control.isWorking)
                            Text("\(Int(control.target(for: fan)).formatted()) rpm")
                                .font(AppTheme.Typography.callout)
                                .monospacedDigit()
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                    HStack {
                        Button("Full Speed") { Task { await control.applyMaximum(fans) } }
                            .controlSize(.small)
                            .disabled(control.isWorking)
                        Spacer()
                    }
                }
                if control.mode == .autoBoost {
                    Text(control.activeBoostPercent.map { "Boosting to \(Int($0))% of maximum." }
                         ?? "Watching temperatures. macOS controls the fans until a rule matches.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Auto Boost Rules…") { showsBoostRules = true }
                    .controlSize(.small)
                    .accessibilityIdentifier("fanBoostRules")
                Text("Fans never go below what macOS allows, and go back to automatic when CachePop quits or the Mac gets hot.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = control.message {
                InlineNote(text: message, symbolName: "info.circle")
            }
        }
        .sheet(isPresented: $showsBoostRules) { FanBoostRulesView(control: control) }
    }

    private var modeBinding: Binding<FanControlViewModel.Mode> {
        Binding(
            get: { control.mode },
            set: { mode in
                Task {
                    switch mode {
                    case .custom: await control.apply(fans)
                    case .automatic: await control.setAutomatic()
                    case .autoBoost: await control.enableAutoBoost(fans)
                    }
                }
            }
        )
    }

    private func targetBinding(_ fan: FanSample) -> Binding<Double> {
        Binding(get: { control.target(for: fan) }, set: { control.targets[fan.index] = $0 })
    }
}
