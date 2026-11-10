import SwiftUI

/// The panel that opens from the temperature's menu bar item: the CPU, SSD, memory and
/// battery temperatures, updated live while it's open.
struct TemperatureMenuContent: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var monitor: SystemMonitorViewModel { model.monitor }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("Temperatures")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Pill(text: monitor.thermalTitle, symbolName: monitor.isHot ? "flame" : "checkmark",
                     tone: monitor.isHot ? .warning : .success)
            }

            VStack(spacing: 0) {
                ForEach(Array(Self.rows(monitor.snapshot?.temperatures).enumerated()), id: \.element.title) { index, row in
                    if index > 0 {
                        Divider().padding(.leading, 42)
                    }
                    TemperatureRow(row: row, isHot: row.title == "CPU" && monitor.isHot)
                }
            }

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
                Divider().padding(.vertical, 2)
                MenuRow(title: "Quit CachePop", symbol: "power") { model.quitCompletely() }
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(width: 260)
        .onAppear { monitor.begin("menu") }
        .onDisappear { monitor.end("menu") }
    }

    /// The CPU always (a dash until the first reading), the SSD, memory and battery where this
    /// Mac has a sensor for them.
    static func rows(_ temperatures: TemperatureSample?) -> [TemperatureRow.Content] {
        var rows = [TemperatureRow.Content(title: "CPU", symbol: "cpu", hue: Metric.cpu, celsius: temperatures?.chip)]
        if let ssd = temperatures?.ssd {
            rows.append(.init(title: "SSD", symbol: "internaldrive", hue: AppTheme.Palette.graphite, celsius: ssd))
        }
        if let memory = temperatures?.memory {
            rows.append(.init(title: "Memory", symbol: "memorychip", hue: Metric.memory, celsius: memory))
        }
        if let battery = temperatures?.battery {
            rows.append(.init(title: "Battery", symbol: "battery.75percent", hue: AppTheme.Palette.green, celsius: battery))
        }
        return rows
    }

    private func close(_ action: @escaping () -> Void) {
        dismiss()
        action()
    }
}

/// One sensor: its symbol on a coloured tile, its name and its temperature.
struct TemperatureRow: View {
    struct Content {
        let title: String
        let symbol: String
        let hue: Hue
        let celsius: Double?
    }

    let row: Content
    var isHot = false

    private var value: String { row.celsius.map(SystemMonitorViewModel.temperature) ?? "—" }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            IconTile(symbolName: row.symbol, size: 22, hue: row.hue)
            Text(row.title)
                .font(AppTheme.Typography.body)
            Spacer(minLength: AppTheme.Spacing.s)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isHot ? AppTheme.Status.warning : AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(value)")
    }
}
