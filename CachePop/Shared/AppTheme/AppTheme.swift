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
            Color(hex: 0x7F98F4).opacity(0.92),
            Color(hex: 0x647BE5).opacity(0.88),
            Color(hex: 0x4052C7).opacity(0.95)
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
