import SwiftUI

struct NetworkMenuReadings: View {
    let reading: NetworkReading?
    let throughput: Throughput?
    let incoming: [Double]
    let outgoing: [Double]
    let usage: NetworkUsageHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                rate("Upload", symbol: "arrow.up", value: throughput?.outPerSecond, color: Metric.outgoing.solid)
                rate("Download", symbol: "arrow.down", value: throughput?.inPerSecond, color: Metric.incoming.solid)
            }
            VStack(spacing: 6) {
                HStack {
                    Text("Traffic").fontWeight(.medium)
                    Spacer()
                    Text("Peak \(SystemMonitorViewModel.rate(max((incoming + outgoing).filter(\.isFinite).max() ?? 0, 0)))")
                }.font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                TrafficHistoryChart(incoming: incoming, outgoing: outgoing, showsGrid: true, showsEndpoints: true)
                    .frame(height: 84)
                HStack {
                    Text("2 min ago")
                    Spacer()
                    Text("Now")
                }.font(.system(size: 10)).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Divider()
            dataUsage
            if let reading {
                Divider()
                UsageMenuRow("Interface", reading.interface ?? "No active connection")
                if let address = reading.localAddress {
                    UsageMenuRow("Local IP", address).textSelection(.enabled).help(address)
                }
            } else {
                Text("Network readings are unavailable.")
                    .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .accessibilityIdentifier("networkMenuReadings")
        .help("Traffic across physical Wi-Fi and Ethernet interfaces, including local transfers. Daily and calendar-month totals include traffic observed while CachePop collects network readings; past or unobserved usage is not reconstructed. Activity does not test internet connectivity.")
    }

    private func rate(_ title: String, symbol: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: symbol).fontWeight(.semibold).foregroundStyle(color)
                Text(title).foregroundStyle(AppTheme.Colors.textSecondary)
            }.font(AppTheme.Typography.caption)
            Text(value.map(SystemMonitorViewModel.rate) ?? "—")
                .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.Colors.tile.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
    }

    private var dataUsage: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Data usage").fontWeight(.medium)
                    Spacer()
                    usageHeading("Upload", arrow: "arrow.up", color: Metric.outgoing.solid)
                    usageHeading("Download", arrow: "arrow.down", color: Metric.incoming.solid)
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                usageRow("Today", bytes: usage.today(at: context.date))
                usageRow("This month", bytes: usage.month(at: context.date))
                if let start = usage.startedAt {
                    Text("Tracked since \(start.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func usageHeading(_ title: String, arrow: String, color: Color) -> some View {
        Label { Text(title) } icon: { Image(systemName: arrow).foregroundStyle(color) }
            .frame(width: 78, alignment: .trailing)
    }

    private func usageRow(_ title: String, bytes: ByteCounters) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
            Text(ByteSize.string(Int64(clamping: bytes.written))).frame(width: 78, alignment: .trailing)
            Text(ByteSize.string(Int64(clamping: bytes.read))).frame(width: 78, alignment: .trailing)
        }
        .font(AppTheme.Typography.callout.weight(.medium))
        .monospacedDigit()
    }
}
