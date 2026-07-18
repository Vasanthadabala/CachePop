import AppKit
import SwiftUI

struct ClutterPreviewPane: View {
    let item: CareScanDetailItem?
    let relatedItems: [CareScanDetailItem]
    let section: ClutterSection
    @Binding var duplicateSelectionsByGroupID: [String: Set<String>]
    @State private var focusedDuplicateID: String?

    private var duplicateGroupID: String {
        item?.detail ?? relatedItems.first?.detail ?? "duplicate-group-empty"
    }

    private var defaultDuplicateSelection: Set<String> {
        Set(relatedItems.dropFirst().prefix(1).map(\.id))
    }

    private var selectedDuplicateIDs: Binding<Set<String>> {
        Binding(
            get: {
                duplicateSelectionsByGroupID[duplicateGroupID] ?? defaultDuplicateSelection
            },
            set: { newValue in
                duplicateSelectionsByGroupID[duplicateGroupID] = newValue
            }
        )
    }

    private var displayedItem: CareScanDetailItem? {
        guard section == .duplicates else { return item }
        return relatedItems.first { $0.id == focusedDuplicateID } ?? item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(section == .duplicates ? "Select:" : "Source:")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.74))

                    Text(section == .duplicates ? "Smartly" : item?.subtitle ?? "Selected Folder")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .opacity(section == .duplicates ? 1 : 0)
            }
            .padding(.top, 42)
            .padding(.bottom, 30)

            if let item {
                VStack(alignment: .leading, spacing: 24) {
                    if section == .duplicates {
                        DuplicateRelatedGrid(
                            items: relatedItems,
                            focusedID: focusedDuplicateID,
                            selectedIDs: selectedDuplicateIDs
                        ) { focusedDuplicateID = $0.id
                        }
                        .frame(maxWidth: 470)
                        .frame(height: 250)
                    } else {
                        ClutterLargePreview(item: item, section: section)
                            .frame(width: 270, height: 270)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(displayedItem?.title ?? item.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                            .lineLimit(2)

                        Text(displayedItem?.path ?? item.path)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.42))
                            .lineLimit(3)

                        FileInfoGrid(item: displayedItem ?? item)
                    }
                    .padding(.leading, 2)
                }
            } else {
                ClutterEmptyState(title: "No selection", subtitle: "Run the scan to populate this folder view.")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            syncDuplicateSelection()
        }
        .onChange(of: item?.id) { _, _ in
            syncDuplicateSelection()
        }
    }

    private func syncDuplicateSelection() {
        guard section == .duplicates else {
            focusedDuplicateID = nil
            return
        }

        let validIDs = Set(relatedItems.map(\.id))
        if focusedDuplicateID.map({ !validIDs.contains($0) }) != false {
            focusedDuplicateID = relatedItems.first?.id
        }

        if let savedSelection = duplicateSelectionsByGroupID[duplicateGroupID] {
            let validSelection = savedSelection.intersection(validIDs)
            duplicateSelectionsByGroupID[duplicateGroupID] = validSelection.isEmpty ? defaultDuplicateSelection : validSelection
        } else {
            duplicateSelectionsByGroupID[duplicateGroupID] = defaultDuplicateSelection
        }
    }
}
