import SwiftUI

struct MyClutterManager: View {
    let onBack: () -> Void
    @State var initialResult: ClutterScanResult?
    let initialReviewTarget: ClutterReviewTarget
    @Binding var duplicateSelectionsByGroupID: [String: Set<String>]
    @State private var selectedSection: ClutterSection = .largeFiles
    @State private var selectedItemID: String?
    @State private var isScanning = true
    @State private var scanResult = ClutterScanResult.empty
    @State private var scanTask: Task<Void, Never>?

    private var selectedItem: CareScanDetailItem? {
        scanResult.items(for: selectedSection).first { $0.id == selectedItemID }
            ?? scanResult.items(for: selectedSection).first
    }

    private var relatedItems: [CareScanDetailItem] {
        guard let selectedItem else { return [] }
        return scanResult.relatedItems(for: selectedItem, in: selectedSection)
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MyClutterToolbar(onBack: onBack)

                HStack(spacing: 0) {
                    MyClutterCategories(
                        selectedSection: selectedSection,
                        result: scanResult
                    ) { section in
                        selectedSection = section
                        selectedItemID = scanResult.items(for: section).first?.id
                    }
                        .frame(width: 252)

                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(width: 1)

                    ClutterFilesPane(
                        section: selectedSection,
                        items: scanResult.items(for: selectedSection),
                        permissions: scanResult.permissions,
                        duplicateCounts: scanResult.duplicateCountByRepresentativeID,
                        selectedItemID: $selectedItemID,
                        isScanning: isScanning
                    )
                        .frame(width: 284)

                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(width: 1)

                    ClutterPreviewPane(
                        item: selectedItem,
                        relatedItems: relatedItems,
                        section: selectedSection,
                        duplicateSelectionsByGroupID: $duplicateSelectionsByGroupID
                    )
                }

                MyClutterBottomBar(result: scanResult, onRemove: removeSelectedItems)
            }
        }
        .background(AppTheme.Colors.appBackground)
        .onAppear {
            applyInitialResultIfNeeded()
        }
        .task {
            startScan()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func startScan() {
        guard initialResult == nil, scanTask == nil else { return }

        scanTask = Task {
            let scan = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanClutter()
            }.value

            if Task.isCancelled { return }

            await MainActor.run {
                let result = ClutterScanResult(details: scan.details, permissions: scan.permissions)
                scanResult = result
                selectedSection = .largeFiles
                selectedItemID = result.largeFiles.first?.id ?? result.duplicates.first?.id
                isScanning = false
            }
        }
    }

    private func applyInitialResultIfNeeded() {
        guard let initialResult, isScanning else { return }

        scanResult = initialResult
        let preferredSection = initialReviewTarget.initialSection
        selectedSection = initialResult.items(for: preferredSection).isEmpty
            ? (initialResult.largeFiles.isEmpty && !initialResult.duplicates.isEmpty ? .duplicates : .largeFiles)
            : preferredSection
        selectedItemID = scanResult.items(for: selectedSection).first?.id
        isScanning = false
    }

    private func removeSelectedItems() {
        let itemsToDelete = scanResult.items(for: selectedSection).filter { item in
            if selectedSection == .duplicates {
                return duplicateSelectionsByGroupID.values.contains { $0.contains(item.id) }
            } else {
                // For large files, if we supported selection we'd use it, 
                // but currently everything in the large files list could be considered "selected" 
                // if there were checkboxes. 
                // Let's assume for now large files need to be explicitly selected to be removed.
                // Assuming selectedItemID is the only one to delete if we are in large files for now?
                // Wait, if it's large files, the user might expect all visible to be deleted or only the selected one.
                // Let's just delete the currently selected item ID for large files for now, as a safe default.
                return item.id == selectedItemID
            }
        }

        let paths = itemsToDelete.map { $0.path }
        guard !paths.isEmpty else { return }

        Task {
            _ = await FileActionService.shared.moveToTrash(paths: paths)
            
            await MainActor.run {
                // For a proper update, we should rescan or filter deeply, but for now we can just 
                // trigger a rescan to keep it perfectly accurate, or we can just pop back.
                // Let's just start a new scan.
                self.isScanning = true
                self.scanTask?.cancel()
                self.initialResult = nil // clear initial so it actually scans
                startScan()
            }
        }
    }
}
