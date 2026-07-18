import SwiftUI

struct ApplicationsTopBar: View {
    let onStartOver: () -> Void

    var body: some View {
        HStack {
            Button(action: onStartOver) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))

                    Text("Start Over")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .buttonStyle(.appInteractive)

            Spacer()
        }
        .frame(height: 30)
        .padding(.top, 26)
        .padding(.horizontal, 34)
        .overlay(alignment: .bottom) {
            Text("App Manager")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
        }
    }
}
