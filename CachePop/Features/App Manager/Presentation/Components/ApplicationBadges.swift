import SwiftUI

struct AppMainUpdateBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)

            Circle()
                .stroke(Color(hex: 0xE83932), lineWidth: 12)
                .frame(width: 54, height: 54)

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 35, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(AppTheme.Colors.accentStrong, AppTheme.Colors.textPrimary)

            Rectangle()
                .fill(Color(hex: 0xE83932))
                .frame(width: 66, height: 9)
                .rotationEffect(.degrees(-38))
        }
    }
}

struct AppMiniBadge: View {
    enum Style {
        case cosmic
        case tiles
        case bars
        case blocked
        case pinkDisk
        case leftovers
    }

    let style: Style

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(background)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .cosmic:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFF3DC4), AppTheme.Colors.accentStrong],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 25, height: 25)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .stroke(.white.opacity(0.7), lineWidth: 2)
                        .frame(width: 39, height: 39)
                        .offset(x: -8, y: -8)
                }
        case .tiles:
            VStack(spacing: 2) {
                ForEach(0..<3) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<2) { column in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(hex: 0xEFC49B).opacity(row == column ? 1 : 0.82))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .rotationEffect(.degrees(45))
        case .bars:
            HStack(alignment: .bottom, spacing: 4) {
                ForEach([18.0, 27.0, 38.0], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(hex: 0x98D9B9))
                        .frame(width: 5, height: height)
                }
            }
        case .blocked:
            ZStack {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFE7B4))

                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 32, height: 32)

                Rectangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 36, height: 4)
                    .rotationEffect(.degrees(45))
            }
        case .pinkDisk:
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), Color(hex: 0xFF6AAE))
        case .leftovers:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 27, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), AppTheme.Colors.textTertiary)

                Circle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 21, height: 21)
                    .overlay {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accentStrong)
                    }
                    .offset(x: 7, y: 7)
            }
        }
    }

    private var background: LinearGradient {
        switch style {
        case .cosmic:
            LinearGradient(colors: [AppTheme.Colors.accentStrong, AppTheme.Colors.accentStrong], startPoint: .top, endPoint: .bottom)
        case .tiles:
            LinearGradient(colors: [AppTheme.Colors.accentStrong, AppTheme.Colors.accentStrong], startPoint: .top, endPoint: .bottom)
        case .bars:
            LinearGradient(colors: [Color(hex: 0x3EC873), Color(hex: 0x167B4A)], startPoint: .top, endPoint: .bottom)
        case .blocked:
            LinearGradient(colors: [Color(hex: 0xFF9C21), Color(hex: 0xA42B16)], startPoint: .top, endPoint: .bottom)
        case .pinkDisk:
            LinearGradient(colors: [Color(hex: 0xFF63A9), Color(hex: 0xF43D90)], startPoint: .top, endPoint: .bottom)
        case .leftovers:
            LinearGradient(colors: [AppTheme.Colors.textSecondary, AppTheme.Colors.accentStrong], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
