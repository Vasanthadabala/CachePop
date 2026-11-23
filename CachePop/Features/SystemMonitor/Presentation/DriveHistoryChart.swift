import SwiftUI

/// Uses the same direction and common scale as the Drive menu bar popup.
struct DriveHistoryChart: View {
    let title: String
    let reads: [Double]
    let writes: [Double]

    var body: some View {
        MonitorGroup(title: title) {
            HStack(spacing: 14) {
                Label("Write", systemImage: "arrow.up").foregroundStyle(Metric.outgoing.solid)
                Label("Read", systemImage: "arrow.down").foregroundStyle(Metric.incoming.solid)
                Spacer()
                Text("Peak \(ByteSize.rate(max((reads + writes).filter(\.isFinite).max() ?? 0, 0)))")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }.font(AppTheme.Typography.caption)
            TrafficHistoryChart(incoming: reads, outgoing: writes, showsGrid: true)
                .frame(height: 100)
            HStack {
                Text("2 min ago")
                Spacer()
                Text("Now")
            }.font(.system(size: 10)).foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .accessibilityIdentifier("driveHistoryChart")
    }
}
