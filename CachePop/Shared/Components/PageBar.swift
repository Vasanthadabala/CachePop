import SwiftUI

/// The bar across the top of every section: where you are and its live status.
/// It sits in the window's title-bar row and drags the window like a title bar.
struct PageBar: View {
    let section: AppSection
    let subtitle: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Text(section.title)
                .accessibilityIdentifier("pageTitle")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.3)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                Rectangle().fill(AppTheme.Colors.separator)
                    .frame(width: 1, height: 15)
                    .accessibilityHidden(true)
                Text(subtitle)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

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
