import AppKit
import SwiftUI

struct ThumbnailView: View {
    let kind: ThumbnailKind

    var body: some View {
        switch kind {
        case .oasis:
            OasisPreview()
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        case .zip:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.Colors.accentStrong)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }

                VStack(spacing: 2) {
                    Image(systemName: "zipper.page")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.55))
                    Text("ZIP")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.42))
                }
            }
        case .people:
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF3C1A4), Color(hex: 0x406D8D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -8) {
                    Circle().fill(Color(hex: 0x2B2B2F)).frame(width: 16, height: 16)
                    Circle().fill(Color(hex: 0xE7B08D)).frame(width: 17, height: 17)
                }
                .offset(y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }
}
