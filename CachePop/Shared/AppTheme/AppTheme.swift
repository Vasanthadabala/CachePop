import AppKit
import SwiftUI

/// CachePop's design tokens.
///
/// A white canvas with soft grey cards (in light mode), one accent blue for actions, selection and progress, and
/// neutral greys for everything else. Category colours (`Palette`) appear only where they
/// tell kinds of things apart. Green, orange and red appear only where they mean something:
/// done, needs care, can't be undone. Every colour has a dark-mode value.
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
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let bar: CGFloat = 12
    }

    enum Colors {
        /// The one accent colour: primary buttons, selection, progress.
        static let accent = Color(hex: 0x2F6BF0)
        static let accentSoft = Color.dynamic(light: 0x2F6BF0, lightAlpha: 0.10, dark: 0x3D8BFF, darkAlpha: 0.18)

        /// The window behind everything: white in light mode, black in dark mode.
        static let canvas = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
        /// The sidebar: the same as the canvas, with a hairline between them.
        static let sidebar = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
        /// The open section's row in the sidebar: the card grey.
        static let sidebarSelection = Color.dynamic(light: 0xF6F6F5, dark: 0x1C1C1C)
        /// Cards and grouped lists: flat grey on the canvas, with no outline; the fill sets them apart.
        static let card = Color.dynamic(light: 0xF6F6F5, dark: 0x1C1C1C)
        /// Things that sit up off a card: the selected tab, an unticked box, the floating action
        /// bar, sheets. White in light mode, a step lighter than cards in dark mode.
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
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    }

    /// Meaning-carrying colours. Never decorative.
    enum Status {
        static let success = Color.dynamic(light: 0x1F9D55, dark: 0x34C77B)
        static let successSoft = Color.dynamic(light: 0x1F9D55, lightAlpha: 0.12, dark: 0x34C77B, darkAlpha: 0.18)
        static let warning = Color.dynamic(light: 0xC8710E, dark: 0xF2A33A)
        static let warningSoft = Color.dynamic(light: 0xE08A1E, lightAlpha: 0.12, dark: 0xF2A33A, darkAlpha: 0.16)
    }

    /// Category colours. Used only where colour tells kinds of things apart: the sidebar's
    /// section icons, Clean Up's six categories (scan, breakdown, group headers), the parts
    /// of a chart, and System Monitor's metrics. Never on buttons, plain list headers, intro
    /// cards or settings, which stay neutral.
    enum Palette {
        static let blue = Hue(0x2F6BF0)
        static let sky = Hue(0x1597D8)
        static let teal = Hue(0x12A594)
        static let rose = Hue(0xD9487D)
        static let graphite = Hue(0x6B7280)
        static let green = Hue(0x1F9D55)
        static let violet = Hue(0x7C5CE0)
    }

    enum Typography {
        /// Hero figures: free space, amount found, amount freed.
        static let display = Font.system(size: 34, weight: .semibold, design: .rounded)
        static let largeTitle = Font.system(size: 22, weight: .bold)
        static let title = Font.system(size: 18, weight: .bold)
        static let title2 = Font.system(size: 14, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let size = Font.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit()
    }

    enum Layout {
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
    let base: UInt

    init(_ base: UInt) {
        self.base = base
    }

    var solid: Color { Color(hex: base) }
    var wash: Color { Color(hex: base).opacity(0.12) }
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

    /// Card: flat grey on the canvas, with no outline. `raised` makes it the raised colour
    /// with a hairline and a whisper of shadow, for things that float.
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
