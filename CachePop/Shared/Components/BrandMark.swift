import SwiftUI

/// CachePop's symbol on its own, with no tile: black in light mode, white in dark mode.
/// The glyph is cut from the app icon's artwork as a template image (`BrandGlyph`), so it
/// matches the icon exactly and takes whatever colour the appearance calls for.
struct BrandMark: View {
    /// Height of the symbol; the width follows its proportions.
    var height: CGFloat = 30

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("BrandGlyph")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 32) {
        BrandMark(height: 30)
        BrandMark(height: 72)
        BrandMark(height: 72)
            .padding(12)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }
    .padding(40)
}
