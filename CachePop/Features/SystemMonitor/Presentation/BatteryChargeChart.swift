import SwiftUI

struct BatteryChargeChart: View {
    let history: RollingBatteryHistory
    let color: Color

    var body: some View {
        MonitorGroup(title: "Charge history") {
            HStack(spacing: 7) {
                VStack {
                    Text("100%")
                    Spacer()
                    Text("0")
                }.font(.system(size: 10)).foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 28, alignment: .trailing)
                GeometryReader { proxy in
                    ZStack {
                        VStack {
                            ForEach(0..<4) { _ in
                                Rectangle().fill(AppTheme.Colors.separator).frame(height: 0.5)
                                Spacer(minLength: 0)
                            }
                        }
                        ForEach(Array(history.segments.enumerated()), id: \.offset) { _, segment in
                            let points = segment.map { reading in
                                CGPoint(x: history.fraction(for: reading.date) * proxy.size.width,
                                        y: (1 - Double(reading.percent) / 100) * proxy.size.height)
                            }
                            if let first = points.first, let last = points.last {
                                Path { path in
                                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                                    points.forEach { path.addLine(to: $0) }
                                    path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                                    path.closeSubpath()
                                }.fill(LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                                Path { path in
                                    path.move(to: first)
                                    points.dropFirst().forEach { path.addLine(to: $0) }
                                }.stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                if points.count == 1 {
                                    Circle().fill(color).frame(width: 3, height: 3).position(first)
                                }
                            }
                        }
                    }
                    .background(AppTheme.Colors.tile.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }.accessibilityHidden(true)
            }.frame(height: 80)
            HStack {
                Text("24 hours ago")
                Spacer()
                Text("Last 24 hours")
                Spacer()
                Text("Now")
            }.font(.system(size: 10)).foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("batteryChargeHistory")
        .help("Recorded charge levels over the last 24 hours. Unrecorded periods remain blank.")
    }
}
