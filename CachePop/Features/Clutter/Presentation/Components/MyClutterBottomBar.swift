import SwiftUI

struct MyClutterBottomBar: View {
    let result: ClutterScanResult
    var onRemove: () -> Void = {}

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 12) {
                Text("\(result.selectedCount) Items Selected")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))

                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 20)

                Text(result.selectedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.52))
            }

            Spacer()

            Button("Remove") {
                onRemove()
            }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.appInteractive)
                .frame(width: 92, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FeatureAccent.clutter.gradient)
                }
                .accentGlow(.clutter, radius: 12, y: 5)
                .raisedButtonChrome(cornerRadius: 12)
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(AppTheme.Colors.appBackground)
    }
}
