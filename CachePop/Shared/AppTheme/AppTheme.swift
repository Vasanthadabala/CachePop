import AppKit
import SwiftUI

/// CachePop's design tokens.
///
/// Neutral surfaces and text, blue actions, and distinct colours for categories and data.
/// Status colours communicate success, warnings and destructive actions.
/// Colours adapt to light and dark appearances.
enum AppTheme {
    /// A compact scale: tight inside cards, a little more between them.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let medium: CGFloat = 9
        static let large: CGFloat = 14
        static let bar: CGFloat = 14
    }

    enum Colors {
        /// The one accent colour: primary buttons, selection, progress.
        static let accent = Color(nsColor: .systemBlue)
        static let accentSoft = accent.opacity(0.12)

        static let canvas = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
        static let sidebar = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
        static let sidebarSelection = Color.dynamic(light: 0xF5F5F5, dark: 0x1C1C1C)
        static let card = Color.dynamic(light: 0xF5F5F5, dark: 0x1C1C1C)
        static let raised = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2A2A)
        static let raisedBorder = Color.dynamic(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.07)
        static let raisedShadow = Color.dynamic(light: 0x000000, lightAlpha: 0.06, dark: 0x000000, darkAlpha: 0)
        /// Neutral fill for icon tiles, pills and hover.
        static let tile = Color.dynamic(light: 0x000000, lightAlpha: 0.045, dark: 0xFFFFFF, darkAlpha: 0.07)
        static let hover = Color.dynamic(light: 0x000000, lightAlpha: 0.025, dark: 0xFFFFFF, darkAlpha: 0.035)
        /// Track behind bars and rings.
        static let track = Color.dynamic(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.10)
        static let separator = Color.dynamic(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.08)

        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color.dynamic(light: 0x686868, dark: 0xAAAAAA)
    }

    /// Meaning-carrying colours. Never decorative.
    enum Status {
        static let success = Color.dynamic(light: 0x1F9D55, dark: 0x34C77B)
        static let successSoft = Color.dynamic(light: 0x1F9D55, lightAlpha: 0.12, dark: 0x34C77B, darkAlpha: 0.18)
        static let warning = Color.dynamic(light: 0xC8710E, dark: 0xF2A33A)
        static let warningSoft = Color.dynamic(light: 0xE08A1E, lightAlpha: 0.12, dark: 0xF2A33A, darkAlpha: 0.16)
    }

    /// Category colours shared by legends, charts and small identifying icons.
    enum Palette {
        static let red = Hue(.systemRed)
        static let blue = Hue(.systemBlue)
        static let graphite = Hue(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? 0x808080 : 0x555555, alpha: 1)
        })
        static let green = Hue(.systemGreen)
        static let orange = Hue(.systemOrange)
        static let turquoise = Hue(NSColor(hex: 0x13BFC8, alpha: 1))
        static let violet = Hue(NSColor(hex: 0x6C68EB, alpha: 1))
    }

    enum Typography {
        /// Hero figures: free space, amount found, amount freed.
        static let display = Font.system(size: 30, weight: .semibold)
        static let largeTitle = Font.system(size: 20, weight: .semibold)
        static let title = Font.system(size: 17, weight: .semibold)
        static let title2 = Font.system(size: 14, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let size = Font.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit()
    }

    enum Layout {
        /// A compact first-launch window; macOS may restore a size the user chose later.
        static let defaultWindowSize = CGSize(width: 1000, height: 680)
        /// Space between the window's edges and a page's content, the same on every page.
        static let pageGutter: CGFloat = 20
        /// Space left under scrolling content for the floating action bar.
        static let actionBarClearance: CGFloat = 68
        /// Icons and tiles at the start of list rows.
        static let rowIcon: CGFloat = 24
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
    }
}

/// A category colour: `solid` for icon tiles and chart parts, `wash` for a faint tint.
struct Hue: Equatable {
    let solid: Color

    init(_ color: NSColor) {
        self.solid = Color(nsColor: color)
    }

    var wash: Color { solid.opacity(0.12) }
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

    /// A colour with separate light and dark values that follows the window's appearance.
    /// Nonisolated because AppKit resolves dynamic colours on whatever thread is drawing.
    nonisolated static func dynamic(light: UInt, lightAlpha: Double = 1, dark: UInt, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { @Sendable appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

nonisolated extension NSColor {
    convenience init(hex: UInt, alpha: Double) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    /// The one primary action on a screen.
    func primaryAction() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.regular)
    }

    /// A secondary action next to the primary one.
    func secondaryAction() -> some View {
        buttonStyle(.bordered)
            .controlSize(.regular)
    }

    /// A grouped surface. Floating controls get a stronger edge and a small shadow.
    func card(padding: CGFloat = 0, radius: CGFloat = AppTheme.Radius.large, raised: Bool = false) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(raised ? AppTheme.Colors.raised : AppTheme.Colors.card)
                    .shadow(color: raised ? AppTheme.Colors.raisedShadow : .clear, radius: 6, y: 1)
            }
            .overlay {
                if raised {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(AppTheme.Colors.raisedBorder, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The window background: the plain canvas colour.
struct CanvasBackground: View {
    var body: some View {
        AppTheme.Colors.canvas
            .ignoresSafeArea()
    }
}
