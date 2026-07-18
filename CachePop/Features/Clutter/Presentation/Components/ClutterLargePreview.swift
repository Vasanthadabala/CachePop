import SwiftUI

struct ClutterLargePreview: View {
    let item: CareScanDetailItem
    let section: ClutterSection

    var body: some View {
        ZStack {
            if let image = NSImage(contentsOfFile: item.path), section == .duplicates {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FeatureAccent.clutter.gradient)

                Image(systemName: section.symbolName)
                    .font(.system(size: 82, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
