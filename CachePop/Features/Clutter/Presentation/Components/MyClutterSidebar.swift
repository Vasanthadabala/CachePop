import SwiftUI

struct MyClutterSidebar: View {
    private let items: [MyClutterSidebarItem] = [
        .smartCare,
        .cleanup,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
                .frame(height: 118)

            ForEach(items) { item in
                MyClutterSidebarIcon(item: item)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 34, height: 34)

                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.82), AppTheme.Colors.border.opacity(0.6))
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.white.opacity(0.03))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 1)
                }
        }
    }
}

struct MyClutterSidebarIcon: View {
    let item: MyClutterSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .myClutter ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .myClutter ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), AppTheme.Colors.textPrimary.opacity(item == .myClutter ? 0.95 : 0.46))
                .frame(width: 58, height: 58)

            if item == .myClutter {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}
