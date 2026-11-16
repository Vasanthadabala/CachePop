import SwiftUI

struct MonitorDetailsView: View {
    let model: SystemMonitorViewModel
    let disk: DiskInfo
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var group: SensorGroup?
    @State private var search = ""

    private var sensors: [TemperatureSensor] {
        (model.snapshot?.temperatures.sensors ?? []).filter {
            (group == nil || $0.group == group) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sensors & Status").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("Details", selection: $tab) {
                Text("Temperatures & Peaks").tag(0)
                Text("Status Checks").tag(1)
            }.pickerStyle(.segmented)
            if tab == 0 {
                HStack {
                    Picker("Component", selection: $group) {
                        Text("All components").tag(Optional<SensorGroup>.none)
                        ForEach(SensorGroup.allCases) { Text($0.title).tag(Optional($0)) }
                    }.frame(width: 175)
                    TextField("Find a sensor", text: $search).textFieldStyle(.roundedBorder)
                    Button("Reset Peaks") { model.resetMaximums() }
                        .accessibilityIdentifier("resetMonitorPeaks")
                }
                HStack {
                    Text("Peak CPU \(Int((model.peakCPU * 100).rounded()))%")
                    Text("Peak memory \(Int((model.peakMemory * 100).rounded()))%")
                    Spacer()
                    Text("Current / Peak").monospacedDigit()
                }.font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sensors) { sensor in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sensor.name).font(AppTheme.Typography.callout)
                                    Text(sensor.group.title).font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                                ProgressView(value: min(max(sensor.celsius / 105, 0), 1))
                                    .tint(sensor.celsius >= 90 ? AppTheme.Status.warning : sensor.group.hue.solid)
                                    .frame(width: 110)
                                Text(SystemMonitorViewModel.temperature(sensor.celsius)).frame(width: 55, alignment: .trailing)
                                Text(SystemMonitorViewModel.temperature(model.sensorMaximums[sensor.id] ?? sensor.celsius))
                                    .foregroundStyle(AppTheme.Colors.textSecondary).frame(width: 55, alignment: .trailing)
                            }.monospacedDigit().padding(.vertical, 8)
                            Divider()
                        }
                        if sensors.isEmpty {
                            Text("No temperature readings match. Sensor availability depends on this Mac.")
                                .foregroundStyle(AppTheme.Colors.textSecondary).padding(.vertical, 30)
                        }
                    }
                }
            } else if let snapshot = model.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(MonitorStatus.checks(snapshot: snapshot, disk: disk, isHot: model.isHot)) { check in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: check.level == .warning ? "exclamationmark.triangle.fill" : check.level == .unavailable ? "questionmark.circle" : "checkmark.circle")
                                    .foregroundStyle(check.level.color)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(check.title).font(AppTheme.Typography.headline)
                                    Text(check.detail).font(AppTheme.Typography.callout)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                        }
                        Text("Live monitoring checks do not replace Apple Diagnostics or a drive hardware test.")
                            .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                }
            }
            Text("Peaks are recorded during this app session. CSV recordings keep up to \(SystemMonitorViewModel.logLimit) readings and are saved only when you choose Export CSV.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 680, height: 520)
    }
}
