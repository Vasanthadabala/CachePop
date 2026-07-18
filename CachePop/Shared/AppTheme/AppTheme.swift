import SwiftUI

enum AppTheme {
    enum Colors {
        // Core text
        static let textPrimary   = Color(hex: 0x111111)
        static let textSecondary = Color(hex: 0x6B7280)
        static let textTertiary  = Color(hex: 0x9CA3AF)
        static let inverseText   = Color.white

        // Surfaces
        static let appBackground = Color.white
        static let sidebarBg     = Color(hex: 0xF9FAFB)
        static let cardBg        = Color.white
        static let glassBg       = Color(hex: 0xF9FAFB)
        static let glassStrong   = Color(hex: 0xF3F4F6)

        // Borders
        static let border        = Color(hex: 0xE5E7EB)
        static let glassBorder   = Color(hex: 0xD1D5DB)

        // Accents (black-based for minimal theme)
        static let accent        = Color(hex: 0x111111)
        static let accentStrong  = Color(hex: 0x374151)
        static let accentDeep    = Color(hex: 0x6B7280)

        // Glows — disabled for minimal theme
        static let glowPrimary   = Color.black.opacity(0.06)
        static let glowViolet    = Color.clear
        static let glowCyan      = Color.clear

        // Legacy
        static let iconBlue      = Color(hex: 0x6B7280)
        static let panel         = Color(hex: 0xF3F4F6)
    }

    enum Care {
        static let heading       = Colors.textPrimary
        static let headingMuted  = Colors.textSecondary
        static let border        = Colors.border
        static let cardText      = Colors.textPrimary
        static let cardSubtext   = Colors.textSecondary
        static let actionGlow    = Color.clear
        static let actionShadow  = Color.black.opacity(0.10)
        static let actionGradient = LinearGradient(
            colors: [
                Color(hex: 0x111111),
                Color(hex: 0x1F2937)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // White card gradient (used as card backgrounds)
        static let cardGradient: [Color] = [Color.white]

        static let glassCard = LinearGradient(
            colors: [Color.white, Color.white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum JunkCleanerManager {
        static let accent        = FeatureAccent.cleanup.solid
        static let text          = Colors.textPrimary
        static let secondary     = Colors.textTertiary
        static let icon          = Colors.iconBlue
        static let panel         = Colors.panel
        static let selection     = FeatureAccent.cleanup.solid.opacity(0.16)
        static let bottomBar     = Colors.appBackground
        static let blueGradient  = FeatureAccent.cleanup.gradient
        static let actionGradient = FeatureAccent.cleanup.gradient
    }
}

// MARK: - Feature Accent System
// Each major feature gets its own identity color, used for its sidebar icon,
// dashboard shortcut, and the CTAs/progress rings within that feature's own screens.
enum FeatureAccent: CaseIterable {
    case dashboard
    case cleanup
    case boost
    case appManager
    case clutter
    case assistant

    var solid: Color {
        switch self {
        case .dashboard:  Color(hex: 0x3D6BF0)
        case .cleanup:    Color(hex: 0x0FB88A)
        case .boost:      Color(hex: 0xFF9736)
        case .appManager: Color(hex: 0x8B5CF6)
        case .clutter:    Color(hex: 0xF3487E)
        case .assistant:  Color(hex: 0x6366F1)
        }
    }

    var deep: Color {
        switch self {
        case .dashboard:  Color(hex: 0x2A4FC4)
        case .cleanup:    Color(hex: 0x0A8F6C)
        case .boost:      Color(hex: 0xDE7A1B)
        case .appManager: Color(hex: 0x6D3FD1)
        case .clutter:    Color(hex: 0xC92F63)
        case .assistant:  Color(hex: 0x4740C6)
        }
    }

    /// Very light background wash for cards/badges on the white surface.
    var tint: Color { solid.opacity(0.12) }
    var tintStrong: Color { solid.opacity(0.2) }

    /// Flat two-stop gradient for hero surfaces — kept close in value, no gloss highlight.
    var gradient: LinearGradient {
        LinearGradient(colors: [solid, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var shadow: Color { solid.opacity(0.32) }

    var title: String {
        switch self {
        case .dashboard:  "Smart Care"
        case .cleanup:    "Junk Cleaner"
        case .boost:      "Boost"
        case .appManager: "App Manager"
        case .clutter:    "Clutter"
        case .assistant:  "Assistant"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard:  "sparkles"
        case .cleanup:    "trash.fill"
        case .boost:      "bolt.fill"
        case .appManager: "square.grid.2x2.fill"
        case .clutter:    "folder.fill"
        case .assistant:  "circle.grid.cross.fill"
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double(hex         & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Raised Button Chrome
private struct RaisedButtonChrome: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
    }
}

private struct RaisedCircleButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
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

// MARK: - Interactive Button Style (subtle hover/press feedback, no gradients/glow)
struct AppInteractiveButtonStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.015
    var pressScale: CGFloat = 0.965

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonBody(configuration: configuration, hoverScale: hoverScale, pressScale: pressScale)
    }

    private struct InteractiveButtonBody: View {
        let configuration: Configuration
        let hoverScale: CGFloat
        let pressScale: CGFloat

        @State private var isHovered = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressScale : (isHovered ? hoverScale : 1.0))
                .opacity(configuration.isPressed ? 0.88 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.78), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == AppInteractiveButtonStyle {
    static var appInteractive: AppInteractiveButtonStyle { AppInteractiveButtonStyle() }
}

// MARK: - Card Hover Chrome (subtle lift on hover for tappable cards, no glow)
private struct CardHoverChrome: ViewModifier {
    var scale: CGFloat = 1.012
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.09 : 0.05), radius: isHovered ? 14 : 10, x: 0, y: isHovered ? 5 : 3)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func cardHoverChrome(scale: CGFloat = 1.012) -> some View {
        modifier(CardHoverChrome(scale: scale))
    }
}

// MARK: - Row Hover Highlight (subtle background tint on hover for list rows)
private struct RowHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 8
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.Colors.border.opacity(0.4))
                }
            }
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func rowHoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(RowHoverHighlight(cornerRadius: cornerRadius))
    }
}

// MARK: - Row Hover Border (for rows with an opaque fill already, tints via a top border instead)
private struct RowHoverBorder: ViewModifier {
    var cornerRadius: CGFloat = 10
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.textPrimary.opacity(isHovered ? 0.16 : 0), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func rowHoverBorder(cornerRadius: CGFloat = 10) -> some View {
        modifier(RowHoverBorder(cornerRadius: cornerRadius))
    }
}

// MARK: - Card Modifier (white card with border)
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, opacity: Double = 1.0) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, opacity: opacity))
    }

    /// Soft, accent-tinted elevation shadow for hero surfaces/buttons in that feature's color.
    func accentGlow(_ accent: FeatureAccent, radius: CGFloat = 20, y: CGFloat = 8) -> some View {
        self.shadow(color: accent.shadow, radius: radius, x: 0, y: y)
    }
}

// MARK: - Plain White Background (replaces DarkMeshBackground)
struct DarkMeshBackground: View {
    var body: some View {
        Color.white
    }
}
