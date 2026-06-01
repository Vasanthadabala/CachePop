import SwiftUI

enum AppTheme {
    enum Colors {
        static let textPrimary = Color.black.opacity(0.9)
        static let textSecondary = Color.black.opacity(0.62)
        static let textTertiary = Color.black.opacity(0.52)
        static let inverseText = Color.white
        static let appBackground = Color(hex: 0xF7F4EF)
        static let border = Color(hex: 0xDCE3F2)
        static let accent = Color(hex: 0x8EA8FF)
        static let accentStrong = Color(hex: 0x5366D6)
        static let accentDeep = Color(hex: 0x1C2A68)
        static let iconBlue = Color(hex: 0x6EB8E5)
        static let panel = Color.white.opacity(0.06)
    }

    enum Care {
        static let heading = Colors.textPrimary
        static let headingMuted = Colors.textSecondary
        static let border = Colors.border
        static let cardText = Colors.inverseText
        static let cardSubtext = Colors.inverseText.opacity(0.78)
        static let actionGlow = Color.clear
        static let actionShadow = Color.clear
        static let actionGradient = LinearGradient(
            colors: [
                Color(hex: 0x6F83EA),
                Color(hex: 0x5A6DDD),
                Color(hex: 0x4E60D0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let cardGradient = [
            Color(hex: 0x6F83EA),
            Color(hex: 0x5A6DDD),
            Color(hex: 0x4E60D0)
        ]
    }

    enum JunkCleanerManager {
        static let accent = Colors.accent
        static let text = Colors.textPrimary
        static let secondary = Colors.textTertiary
        static let icon = Colors.iconBlue
        static let panel = Colors.panel
        static let selection = Colors.accentDeep
        static let bottomBar = Colors.appBackground
        static let blueGradient = LinearGradient(
            colors: [
                Color(hex: 0x6F83EA),
                Colors.accentStrong
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let actionGradient = LinearGradient(
            colors: [
                Color(hex: 0x6F83EA),
                Colors.accentStrong
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private struct RaisedButtonChrome: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.36), lineWidth: 1)
                    .padding(1.2)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.06),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 7)
    }
}

private struct RaisedCircleButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    .padding(1.2)
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.07),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func raisedButtonChrome(cornerRadius: CGFloat) -> some View {
        modifier(RaisedButtonChrome(cornerRadius: cornerRadius))
    }

    func raisedCircleButtonChrome() -> some View {
        modifier(RaisedCircleButtonChrome())
    }
}
