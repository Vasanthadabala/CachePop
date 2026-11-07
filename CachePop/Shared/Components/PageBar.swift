import SwiftUI

/// The bar across the top of every section: where you are and its live status.
/// It sits in the window's title-bar row and drags the window like a title bar.
struct PageBar: View {
    let section: AppSection
    let subtitle: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                }
            }
            .animation(AppTheme.Motion.quick, value: subtitle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .frame(height: PageBar.height)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.Colors.separator).frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    static let height: CGFloat = 48
}
