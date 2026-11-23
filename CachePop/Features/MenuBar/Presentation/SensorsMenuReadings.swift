import SwiftUI

enum SensorsPopupLayout {
    /// Double the previous popup, reserving space for its title and fixed action rows.
    static func readingsHeight(rowCount: Int, availableHeight: CGFloat) -> CGFloat {
        let chrome: CGFloat = 140
        let previous = min(CGFloat(rowCount) * 23 + 60, 350)
        return max(0, min(previous * 2 + chrome, availableHeight - chrome))
    }
}

/// Full hardware sensors live here, separate from the compact Temperature popup.
struct SensorsMenuReadings: View {
    let snapshot: SystemSnapshot?
    var availableHeight: CGFloat = 900

    var body: some View {
        if let snapshot {
            ScrollView {
                SensorsMenuGroups(snapshot: snapshot)
            }
            .frame(height: SensorsPopupLayout.readingsHeight(rowCount: rowCount(snapshot), availableHeight: availableHeight))
            .accessibilityIdentifier("sensorsMenuReadings")
        } else {
            ProgressView("Reading sensors…").font(AppTheme.Typography.callout)
        }
    }

    private func rowCount(_ snapshot: SystemSnapshot) -> Int {
        TemperatureMenuContent.rows(snapshot.temperatures).count + snapshot.temperatures.sensors.count
            + snapshot.electricalSensors.count + snapshot.fans.count
    }
}

struct SensorsMenuGroups: View {
    let snapshot: SystemSnapshot
    @State private var showsOther = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("Temperature") {
                ForEach(TemperatureMenuContent.rows(snapshot.temperatures), id: \.title) { row in
                    TemperatureRow(row: row)
                }
            }
            ForEach(SensorGroup.allCases.filter { $0 != .other }) { group in
                let sensors = snapshot.temperatures.sensors.filter { $0.group == group }
                if !sensors.isEmpty {
                    section(group.title) {
                        ForEach(sensors.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { sensor in
                            UsageMenuRow(sensor.name, SystemMonitorViewModel.temperature(sensor.celsius))
                        }
                    }
                }
            }
            let other = snapshot.temperatures.sensors.filter { $0.group == .other }
            if !other.isEmpty {
                DisclosureGroup("Other temperatures", isExpanded: $showsOther) {
                    VStack(spacing: 6) {
                        ForEach(other.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { sensor in
                            UsageMenuRow(sensor.name, SystemMonitorViewModel.temperature(sensor.celsius))
                        }
                    }.padding(.top, 6)
                }.font(AppTheme.Typography.caption).tint(AppTheme.Colors.textSecondary)
            }
            if !snapshot.fans.isEmpty {
                section("Fans") {
                    ForEach(snapshot.fans, id: \.index) { fan in
                        UsageMenuRow("Fan \(fan.index + 1)", "\(Int(fan.rpm.rounded())) RPM")
                    }
                }
            }
            ForEach(ElectricalSensor.Kind.allCases, id: \.self) { kind in
                let sensors = snapshot.electricalSensors.filter { $0.kind == kind }
                if !sensors.isEmpty {
                    section(kind.rawValue) {
                        ForEach(sensors) { sensor in UsageMenuRow(sensor.name, sensor.formatted) }
                    }
                }
            }
        }.padding(.trailing, 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(title).font(AppTheme.Typography.caption.weight(.semibold)).foregroundStyle(AppTheme.Colors.textSecondary)
            content()
        }
    }
}
