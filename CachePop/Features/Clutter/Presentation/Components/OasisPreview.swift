import SwiftUI

struct OasisPreview: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        AppTheme.Colors.glassBg,
                        AppTheme.Colors.textSecondary,
                        AppTheme.Colors.accentStrong
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.03, y: proxy.size.height * 0.92))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.46, y: proxy.size.height * 0.48),
                        control1: CGPoint(x: proxy.size.width * 0.17, y: proxy.size.height * 0.68),
                        control2: CGPoint(x: proxy.size.width * 0.27, y: proxy.size.height * 0.5)
                    )
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.97, y: proxy.size.height * 0.86),
                        control1: CGPoint(x: proxy.size.width * 0.66, y: proxy.size.height * 0.46),
                        control2: CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.78)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(AppTheme.Colors.accentStrong.opacity(0.8))

                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: proxy.size.width * 0.28, height: proxy.size.width * 0.28)
                    .blur(radius: 2)
                    .offset(x: -proxy.size.width * 0.05, y: -proxy.size.height * 0.05)

                RoundedRectangle(cornerRadius: proxy.size.height * 0.16, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: max(proxy.size.width * 0.03, 2))
                    .frame(width: proxy.size.width * 0.66, height: proxy.size.height * 0.58)
                    .offset(x: -proxy.size.width * 0.14, y: -proxy.size.height * 0.04)

                ForEach(0..<10) { index in
                    Circle()
                        .fill(AppTheme.Colors.textTertiary.opacity(0.68))
                        .frame(width: max(proxy.size.width * 0.032, 3))
                        .offset(
                            x: CGFloat(index % 5) * proxy.size.width * 0.14 - proxy.size.width * 0.28,
                            y: CGFloat(index / 5) * proxy.size.height * 0.11 + proxy.size.height * 0.23
                        )
                }
            }
        }
    }
}
