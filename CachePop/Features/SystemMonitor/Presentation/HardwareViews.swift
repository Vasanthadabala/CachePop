import SwiftUI

enum MonitorPage: String, CaseIterable, Identifiable {
    case cpu = "CPU", gpu = "GPU", memory = "Memory", drive = "Drive", battery = "Battery", sensors = "Sensors"
    var id: String { rawValue }
}

struct MonitorInfoPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(AppTheme.Typography.headline)
            content
        }.padding(AppTheme.Spacing.m).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct MonitorInfoRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
        }.font(AppTheme.Typography.callout)
    }
}

struct MountedVolumesView: View {
    let environment: MonitorEnvironment
    var body: some View {
        MonitorInfoPanel(title: "Mounted drives", symbol: "externaldrive") {
            ForEach(environment.volumes) { volume in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(volume.name).font(AppTheme.Typography.headline)
                        Spacer()
                        Text("\(ByteSize.string(volume.available)) available").monospacedDigit()
                    }
                    ProgressView(value: volume.usedFraction).tint(volume.usedFraction > 0.9 ? AppTheme.Status.warning : AppTheme.Colors.accent)
                    HStack {
                        Text("\(volume.format) · \(ByteSize.string(volume.total))\(volume.isReadOnly ? " · Read-only" : "")")
                        Spacer()
                        Text("\(Int((volume.usedFraction * 100).rounded()))% used")
                    }.font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                }.padding(.vertical, 6)
            }
            if environment.volumes.isEmpty {
                Text(environment.hasLoaded ? "No local drive information available." : "Reading mounted drives…")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Text("Local, browsable volumes only. APFS volumes may share free space. Drive hardware health is not inferred from capacity.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
        }.accessibilityIdentifier("mountedDrives")
    }
}

struct SensorReadingsView: View {
    let sensors: [TemperatureSensor]
    @State private var search = ""
    var body: some View {
        MonitorInfoPanel(title: "Sensor readings", symbol: "thermometer.medium") {
            TextField("Find a sensor", text: $search).textFieldStyle(.roundedBorder)
            ForEach(SensorGroup.allCases) { group in
                let readings = sensors.filter { $0.group == group && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if !readings.isEmpty {
                    if group == .other && search.isEmpty {
                        DisclosureGroup("Other sensors · \(readings.count)") { rows(readings) }
                            .font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary)
                    } else {
                        Label {
                            Text(group.title).foregroundStyle(AppTheme.Colors.textSecondary)
                        } icon: {
                            Circle().fill(group.hue.solid).frame(width: 6, height: 6)
                        }.font(AppTheme.Typography.caption.weight(.semibold))
                        rows(readings)
                    }
                    if group != sensors.last?.group { Divider() }
                }
            }
            if sensors.isEmpty {
                Text("Individual sensor readings are unavailable on this Mac.")
                    .font(AppTheme.Typography.callout).foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }.accessibilityIdentifier("sensorReadings")
    }
    private func rows(_ readings: [TemperatureSensor]) -> some View {
        ForEach(readings) { sensor in MonitorInfoRow(title: sensor.name, value: SystemMonitorViewModel.temperature(sensor.celsius)) }
    }
}
