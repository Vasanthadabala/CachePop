import SwiftUI

struct MyClutterToolbar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text("Back")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
                }
            }
            .buttonStyle(.appInteractive)

            Spacer()

            Text("Clutter Manager")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))

            Spacer()

            HStack(spacing: 28) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 6) {
                    Text("Sort by:")
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))

                    Text("Size")
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .frame(height: 66)
        .padding(.horizontal, 22)
        .background(AppTheme.Colors.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(height: 1)
        }
    }
}
