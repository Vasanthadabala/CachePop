import SwiftUI

/// The panel that opens from the temperature's menu bar item: the CPU, drive, memory and
/// battery temperatures, updated live while it's open.
struct TemperatureMenuContent: View {
    let model: AppModel
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var monitor: SystemMonitorViewModel { model.monitor }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("Temperature")
                    .accessibilityIdentifier("temperatureMenuTitle")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Pill(text: monitor.thermalTitle, tone: monitor.isHot ? .warning : .neutral)
            }

            VStack(spacing: 5) {
                ForEach(Self.rows(monitor.snapshot?.temperatures), id: \.title) { row in
                    TemperatureRow(row: row)
                }
            }
            Divider()
            VStack(spacing: 2) {
                MenuRow(title: "System Monitor", symbol: AppSection.systemMonitor.symbolName) {
                    close { model.show(.systemMonitor) }
                }
                MenuRow(title: "Menu Bar Settings", symbol: "menubar.rectangle") {
                    close {
                        model.settings.selectedTab = .menuBar
                        model.show(.settings)
                    }
                }
                MenuRow(title: "Quit CachePop", symbol: "power") { model.quitCompletely() }
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(width: 256)
        .onExitCommand { dismissMenu() }
    }

    /// The CPU always (a dash until the first reading), the drive, memory and battery where this
    /// Mac has a sensor for them.
    static func rows(_ temperatures: TemperatureSample?) -> [TemperatureRow.Content] {
        var rows = [TemperatureRow.Content(title: "CPU", symbol: "cpu", celsius: temperatures?.chip)]
        if let gpu = temperatures?.gpu { rows.append(.init(title: "GPU", symbol: "display", celsius: gpu)) }
        if let memory = temperatures?.memory {
            rows.append(.init(title: "Memory", symbol: "memorychip", celsius: memory))
        }
        if let ssd = temperatures?.ssd {
            rows.append(.init(title: "Drive", symbol: "internaldrive", celsius: ssd))
        }
        if let battery = temperatures?.battery {
            rows.append(.init(title: "Battery", symbol: "battery.75percent", celsius: battery))
        }
        return rows
    }

    private func dismissMenu() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func close(_ action: @escaping () -> Void) {
        dismissMenu()
        action()
    }
}

/// Neutral component icons keep this menu focused on temperature readings.
struct TemperatureRow: View {
    struct Content {
        let title: String
        let symbol: String
        let celsius: Double?
    }

    let row: Content

    private var value: String { row.celsius.map(SystemMonitorViewModel.temperature) ?? "—" }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            Image(systemName: row.symbol)
                .symbolRenderingMode(.monochrome)
                .frame(width: 16)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(row.title)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer(minLength: AppTheme.Spacing.s)
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .font(AppTheme.Typography.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(value)")
    }
}
