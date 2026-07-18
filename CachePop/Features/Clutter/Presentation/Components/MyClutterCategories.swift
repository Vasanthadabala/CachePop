import SwiftUI

struct MyClutterCategories: View {
    let selectedSection: ClutterSection
    let result: ClutterScanResult
    let onSelect: (ClutterSection) -> Void

    private var visibleSections: [ClutterSection] {
        let sections = ClutterSection.allCases.filter { !result.items(for: $0).isEmpty }
        return sections.isEmpty ? [selectedSection] : sections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(visibleSections) { section in
                Button {
                    onSelect(section)
                } label: {
                    HStack {
                        Text(section.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        Spacer()

                        if selectedSection == section {
                            Rectangle()
                                .fill(AppTheme.Colors.inverseText.opacity(0.34))
                                .frame(width: 1, height: 18)
                                .padding(.trailing, 8)
                        }

                        Text("\(result.items(for: section).count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedSection == section ? AppTheme.Colors.inverseText : AppTheme.Colors.textPrimary.opacity(0.46))
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedSection == section ? AppTheme.Colors.inverseText : AppTheme.Colors.textPrimary.opacity(0.6))
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(FeatureAccent.clutter.gradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.22), lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 42)
        .background(AppTheme.Colors.appBackground)
    }
}
