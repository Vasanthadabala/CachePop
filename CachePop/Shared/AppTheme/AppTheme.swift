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

        // Accent — the single blue used across the app (see FeatureAccent).
        static let accent        = Color(hex: 0x2F6BF0)
        static let accentStrong  = Color(hex: 0x1E4FC4)
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
        static let actionGradient = FeatureAccent.dashboard.gradient
        // White card gradient (used as card backgrounds)
        static let cardGradient: [Color] = [Color.white]

        static let glassCard = LinearGradient(
            colors: [Color.white, Color.white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Meaning-carrying colours. Use these only where the hue tells the user something
    /// (a healthy reading, a warning, a critical problem) — never as decoration.
    enum Status {
        static let success      = Color(hex: 0x14A06B)
        static let successTint  = Color(hex: 0x14A06B).opacity(0.12)

        static let warning      = Color(hex: 0xD98324)
        static let warningTint  = Color(hex: 0xD98324).opacity(0.13)

        static let danger       = Color(hex: 0xD64545)
        static let dangerTint   = Color(hex: 0xD64545).opacity(0.12)
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
//
// The app is intentionally monochromatic: white and gray surfaces with a single blue accent.
// Every feature shares that blue for buttons, progress, and selection so the product reads as
// one cohesive tool rather than a set of differently-branded modules.
//
// Colour beyond the blue is reserved for `AppTheme.Status`, where a hue actually carries
// meaning (healthy / warning / critical). Never use it for decoration.
enum FeatureAccent: CaseIterable {
    case dashboard
    case cleanup
    case boost
    case appManager
    case clutter
    case assistant

    /// The single accent blue shared by the whole app.
    static let primary = Color(hex: 0x2F6BF0)
    static let primaryDeep = Color(hex: 0x1E4FC4)

    var solid: Color { Self.primary }
    var deep: Color { Self.primaryDeep }

    /// Very light background wash for cards/badges on the white surface.
    var tint: Color { solid.opacity(0.10) }
    var tintStrong: Color { solid.opacity(0.18) }

    /// Flat two-stop gradient for hero surfaces — kept close in value, no gloss highlight.
    var gradient: LinearGradient {
        LinearGradient(colors: [solid, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var shadow: Color { solid.opacity(0.28) }

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
