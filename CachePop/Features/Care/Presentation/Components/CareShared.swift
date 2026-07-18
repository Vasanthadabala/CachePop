import AppKit
import SwiftUI

struct ResultCardBadge: View {
    let result: ScanResult

    private var accent: FeatureAccent { result.category.accent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(accent.tint)
                .rotationEffect(.degrees(result.badgeRotation))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 4)

            Image(systemName: result.symbolName)
                .font(.system(size: 44, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(accent.solid)
        }
    }
}

