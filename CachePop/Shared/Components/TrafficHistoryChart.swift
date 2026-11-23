import SwiftUI

/// Outgoing traffic rises above the center; incoming traffic falls below it.
/// Both directions share a scale and fill toward the baseline.
struct TrafficHistoryChart: View {
    let incoming: [Double]
    let outgoing: [Double]
    var capacity = SystemMonitorViewModel.historyLength
    var showsGrid = false
    var showsEndpoints = false

    var body: some View {
        GeometryReader { proxy in
            let maximum = max((incoming + outgoing).filter(\.isFinite).max() ?? 0, 1)
            ZStack {
                if showsGrid {
                    Path { path in
                        for fraction in [0.25, 0.75] {
                            let y = proxy.size.height * fraction
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                    }.stroke(AppTheme.Colors.separator.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                Rectangle().fill(AppTheme.Colors.separator).frame(height: 0.5)
                series(outgoing, upper: true, maximum: maximum, size: proxy.size, color: Metric.outgoing.solid)
                series(incoming, upper: false, maximum: maximum, size: proxy.size, color: Metric.incoming.solid)
            }
        }
        .background(AppTheme.Colors.tile.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func series(_ values: [Double], upper: Bool, maximum: Double, size: CGSize, color: Color) -> some View {
        let points = TrafficChartGeometry.points(values, upper: upper, maximum: maximum, capacity: capacity, in: size)
        return ZStack {
            if let first = points.first, let last = points.last {
                Path { path in
                    path.move(to: CGPoint(x: first.x, y: size.height / 2))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: size.height / 2))
                    path.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.75), color.opacity(0.4)],
                                      startPoint: upper ? .top : .bottom, endPoint: upper ? .bottom : .top))
                Path { path in
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                if showsEndpoints, values.last ?? 0 > 0 {
                    Circle().fill(color).frame(width: 3, height: 3)
                        .position(x: min(last.x, size.width - 1.5), y: last.y)
                }
            }
        }
    }
}

enum TrafficChartGeometry {
    static func points(_ values: [Double], upper: Bool, maximum: Double, capacity: Int, in size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0, capacity > 1 else { return [] }
        let samples = Array(values.suffix(capacity))
        guard samples.count > 1 else { return [] }
        let step = size.width / CGFloat(capacity - 1)
        let start = size.width - step * CGFloat(samples.count - 1)
        let middle = size.height / 2
        let amplitude = max(middle - 2, 0)
        let top = maximum.isFinite && maximum > 0 ? maximum : 1
        return samples.enumerated().map { index, value in
            let fraction = value.isFinite ? min(max(value / top, 0), 1) : 0
            return CGPoint(x: start + CGFloat(index) * step,
                           y: middle + (upper ? -1 : 1) * amplitude * fraction)
        }
    }
}
