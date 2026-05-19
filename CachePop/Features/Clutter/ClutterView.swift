//
//  ClutterView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct ClutterView: View {
    var onBack: () -> Void = {}

    var body: some View {
        ClutterManagerContent(onBack: onBack)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClutterManagerContent: View {
    let onBack: () -> Void
    let snapshot: CareScanSnapshot?

    init(onBack: @escaping () -> Void = {}, snapshot: CareScanSnapshot? = nil) {
        self.onBack = onBack
        self.snapshot = snapshot
    }

    var body: some View {
        MyClutterManager(
            onBack: onBack,
            initialResult: snapshot.map {
                ClutterScanResult(
                    details: $0.clutterDetails,
                    permissions: $0.permissionMessages
                )
            }
        )
    }
}

private struct MyClutterManager: View {
    let onBack: () -> Void
    let initialResult: ClutterScanResult?
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

                Divider()

                ClutterFilesPane(
                    section: selectedSection,
                    items: scanResult.items(for: selectedSection),
                    permissions: scanResult.permissions,
                    duplicateCounts: scanResult.duplicateCountByRepresentativeID,
                    selectedItemID: $selectedItemID,
                    isScanning: isScanning
                )
                    .frame(width: 284)

                Divider()

                ClutterPreviewPane(
                    item: selectedItem,
                    relatedItems: relatedItems,
                    section: selectedSection
                )
            }

            MyClutterBottomBar(result: scanResult)
        }
        .background(Color.white)
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
        selectedSection = initialResult.largeFiles.isEmpty && !initialResult.duplicates.isEmpty ? .duplicates : .largeFiles
        selectedItemID = scanResult.items(for: selectedSection).first?.id
        isScanning = false
    }
}

private struct MyClutterToolbar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6F7DFF))

                    Text("Back")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.9))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("My Clutter Manager")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.92))

            Spacer()

            HStack(spacing: 28) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x6F7DFF))

                HStack(spacing: 6) {
                    Text("Sort by:")
                        .foregroundStyle(.black.opacity(0.9))

                    Text("Size")
                        .foregroundStyle(Color(hex: 0x6F7DFF))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6F7DFF))
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 22)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct MyClutterCategories: View {
    let selectedSection: ClutterSection
    let result: ClutterScanResult
    let onSelect: (ClutterSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ClutterSection.allCases) { section in
                Button {
                    onSelect(section)
                } label: {
                    HStack {
                        Text(section.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        Spacer()

                        Text("\(result.items(for: section).count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedSection == section ? .white : .black.opacity(0.42))
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedSection == section ? .black.opacity(0.92) : .black.opacity(0.56))
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0xCBB4F5).opacity(0.78))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 42)
        .background(Color.white)
    }
}

private struct ClutterFilesPane: View {
    let section: ClutterSection
    let items: [CareScanDetailItem]
    let permissions: [String]
    let duplicateCounts: [String: Int]
    @Binding var selectedItemID: String?
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.bottom, 12)

            Text(section.description)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            HStack(spacing: 6) {
                Text("Show:")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.9))

                Text("All Files")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xC13ABF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC13ABF))
            }
            .padding(.bottom, 30)

            if isScanning {
                ClutterEmptyState(title: "Scanning Downloads...", subtitle: "Checking files above 100 MB and comparing duplicate file contents.")
            } else if items.isEmpty {
                ClutterEmptyState(title: "Nothing found", subtitle: section.emptyMessage)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                selectedItemID = item.id
                            } label: {
                                ClutterFileRow(
                                    item: item,
                                    section: section,
                                    duplicateTotal: section == .duplicates ? duplicateCounts[item.id, default: 2] : nil,
                                    isSelected: selectedItemID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }

            if !permissions.isEmpty {
                Text(permissions[0])
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.46))
                    .lineLimit(3)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

}

private struct ClutterEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .opacity(title.hasPrefix("Scanning") ? 1 : 0)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.86))

            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.46))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xF6F2FA))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: 0xE7DDF1), lineWidth: 1)
                }
        }
    }
}

private struct ClutterFileRow: View {
    let item: CareScanDetailItem
    let section: ClutterSection
    let duplicateTotal: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ClutterFileIcon(item: item, section: section)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.92))
                    .lineLimit(1)

                Text(item.formattedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.48))
            }

            Spacer()

            if let duplicateTotal {
                HStack(spacing: 0) {
                    Text("1")
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: 0xC13ABF))

                    Text("\(duplicateTotal)")
                        .foregroundStyle(.black.opacity(0.58))
                        .frame(width: 22, height: 22)
                        .background(Color(hex: 0xE7E0EE))
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: section.symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC13ABF))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xDECDF4), Color(hex: 0xF1E9FA)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

private struct ClutterFileIcon: View {
    let item: CareScanDetailItem
    let section: ClutterSection

    var body: some View {
        ZStack {
            if let image = NSImage(contentsOfFile: item.path), section == .duplicates {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0xC13ABF).opacity(0.9))

                Image(systemName: section.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

private struct ClutterPreviewPane: View {
    let item: CareScanDetailItem?
    let relatedItems: [CareScanDetailItem]
    let section: ClutterSection
    @State private var selectedDuplicateIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(section == .duplicates ? "Select:" : "Source:")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.9))

                Text(section == .duplicates ? "Smartly" : "Downloads")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xC13ABF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC13ABF))
                    .opacity(section == .duplicates ? 1 : 0)
            }
            .padding(.top, 42)
            .padding(.bottom, 30)

            if let item {
                VStack(alignment: .leading, spacing: 24) {
                    if section == .duplicates {
                        DuplicateRelatedGrid(
                            items: relatedItems,
                            selectedIDs: $selectedDuplicateIDs
                        )
                        .frame(maxWidth: 470)
                        .frame(height: 290)
                    } else {
                        ClutterLargePreview(item: item, section: section)
                            .frame(width: 270, height: 270)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.92))
                            .lineLimit(2)

                        Text(item.path)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.38))
                            .lineLimit(3)

                        FileInfoGrid(item: item)
                    }
                    .padding(.leading, 2)
                }
            } else {
                ClutterEmptyState(title: "No selection", subtitle: "Run the scan to populate this Downloads-only view.")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            resetSelection()
        }
        .onChange(of: item?.id) { _, _ in
            resetSelection()
        }
    }

    private func resetSelection() {
        guard section == .duplicates else {
            selectedDuplicateIDs = []
            return
        }

        selectedDuplicateIDs = Set(relatedItems.dropFirst().map(\.id))
    }
}

private struct DuplicateRelatedGrid: View {
    let items: [CareScanDetailItem]
    @Binding var selectedIDs: Set<String>

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 142), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    DuplicateSelectablePreview(
                        item: item,
                        isSelected: selectedIDs.contains(item.id)
                    ) {
                        if selectedIDs.contains(item.id) {
                            selectedIDs.remove(item.id)
                        } else {
                            selectedIDs.insert(item.id)
                        }
                    }
                    .frame(height: 118)
                }
            }
            .padding(.trailing, 6)
        }
    }
}

private struct DuplicateSelectablePreview: View {
    let item: CareScanDetailItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                duplicatePreview
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color(hex: 0xC13ABF) : Color(hex: 0xE3DAEA), lineWidth: isSelected ? 3 : 1)
                    }

                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? Color(hex: 0xC13ABF) : .white.opacity(0.78))
                        .frame(width: 22, height: 22)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(isSelected ? Color(hex: 0xC13ABF) : .white, lineWidth: 2)
                        }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .padding(7)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var duplicatePreview: some View {
        if let image = NSImage(contentsOfFile: item.path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(hex: 0xF4EEF9)
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC13ABF))
            }
        }
    }
}

private struct ClutterLargePreview: View {
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
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xE8D9F6), Color(hex: 0xC13ABF).opacity(0.52)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: section.symbolName)
                    .font(.system(size: 82, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

private struct FileInfoGrid: View {
    let item: CareScanDetailItem

    private var rows: [(String, String)] {
        [
            ("Modified:", item.modifiedText),
            ("Location:", "Downloads"),
            ("Size:", item.formattedSize),
            ("File type:", fileType)
        ]
    }

    private var fileType: String {
        let ext = URL(fileURLWithPath: item.path).pathExtension
        if ext.isEmpty {
            return item.kind
        }
        return ext.uppercased()
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 14) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.44))
                    Text(row.1)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

private struct MyClutterBottomBar: View {
    let result: ClutterScanResult

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 12) {
                Text("\(result.selectedCount) Items Selected")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)

                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(width: 1, height: 20)

                Text(result.selectedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.45))
            }

            Spacer()

            Button("Remove") {}
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .frame(width: 92, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x7B6DFF), Color(hex: 0x4B31C8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color(hex: 0xF7F4FA))
    }
}

private enum ClutterSection: String, CaseIterable, Identifiable {
    case largeFiles
    case duplicates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeFiles:
            "Large Files"
        case .duplicates:
            "Duplicates"
        }
    }

    var description: String {
        switch self {
        case .largeFiles:
            "Files above 100 MB found in your Downloads folder."
        case .duplicates:
            "Identical files found inside your Downloads folder by comparing file contents."
        }
    }

    var emptyMessage: String {
        switch self {
        case .largeFiles:
            "No files above 100 MB were found in Downloads."
        case .duplicates:
            "No identical duplicate files were found in Downloads."
        }
    }

    var symbolName: String {
        switch self {
        case .largeFiles:
            "doc.fill"
        case .duplicates:
            "doc.on.doc.fill"
        }
    }
}

private struct ClutterScanResult {
    let largeFiles: [CareScanDetailItem]
    let duplicates: [CareScanDetailItem]
    let duplicateGroups: [ClutterDuplicateGroup]
    let permissions: [String]

    static let empty = ClutterScanResult(details: [], permissions: [])

    init(details: [CareScanDetailItem], permissions: [String]) {
        self.largeFiles = details
            .filter { $0.kind == "Large File" }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        let duplicateItems = details
            .filter { $0.kind == "Duplicate Candidate" }
            .sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }
        self.duplicateGroups = Dictionary(grouping: duplicateItems) { item in
            item.detail.hasPrefix("duplicate-group-") ? item.detail : "\(item.sizeBytes)-\(item.title)"
        }
        .values
        .map { items in
            let sortedItems = items.sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }
            return ClutterDuplicateGroup(items: sortedItems)
        }
        .sorted { $0.totalBytes > $1.totalBytes }
        self.duplicates = duplicateGroups.compactMap(\.representative)
        self.permissions = permissions
    }

    var duplicateCountByRepresentativeID: [String: Int] {
        Dictionary(uniqueKeysWithValues: duplicateGroups.compactMap { group in
            guard let representative = group.representative else { return nil }
            return (representative.id, group.items.count)
        })
    }

    var selectedCount: Int {
        largeFiles.count + duplicates.count
    }

    var selectedSize: String {
        let bytes = (largeFiles + duplicates).reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func items(for section: ClutterSection) -> [CareScanDetailItem] {
        switch section {
        case .largeFiles:
            largeFiles
        case .duplicates:
            duplicates
        }
    }

    func relatedItems(for item: CareScanDetailItem, in section: ClutterSection) -> [CareScanDetailItem] {
        guard section == .duplicates else { return [item] }
        return duplicateGroups.first { $0.representative?.id == item.id }?.items ?? [item]
    }
}

private struct ClutterDuplicateGroup {
    let items: [CareScanDetailItem]

    var representative: CareScanDetailItem? {
        items.first
    }

    var totalBytes: Int64 {
        items.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }
}

private struct ThumbnailView: View {
    let kind: ThumbnailKind

    var body: some View {
        switch kind {
        case .oasis:
            OasisPreview()
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        case .zip:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: 0x1B1C24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }

                VStack(spacing: 2) {
                    Image(systemName: "zipper.page")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("ZIP")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
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

private struct OasisPreview: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xEEF2FF),
                        Color(hex: 0x7D98F6),
                        Color(hex: 0x3320A8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.03, y: proxy.size.height * 0.92))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.46, y: proxy.size.height * 0.48),
                        control1: CGPoint(x: proxy.size.width * 0.17, y: proxy.size.height * 0.68),
                        control2: CGPoint(x: proxy.size.width * 0.27, y: proxy.size.height * 0.5)
                    )
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.97, y: proxy.size.height * 0.86),
                        control1: CGPoint(x: proxy.size.width * 0.66, y: proxy.size.height * 0.46),
                        control2: CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.78)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0x241572).opacity(0.8))

                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: proxy.size.width * 0.28, height: proxy.size.width * 0.28)
                    .blur(radius: 2)
                    .offset(x: -proxy.size.width * 0.05, y: -proxy.size.height * 0.05)

                RoundedRectangle(cornerRadius: proxy.size.height * 0.16, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: max(proxy.size.width * 0.03, 2))
                    .frame(width: proxy.size.width * 0.66, height: proxy.size.height * 0.58)
                    .offset(x: -proxy.size.width * 0.14, y: -proxy.size.height * 0.04)

                ForEach(0..<10) { index in
                    Circle()
                        .fill(Color(hex: 0x7896FF).opacity(0.68))
                        .frame(width: max(proxy.size.width * 0.032, 3))
                        .offset(
                            x: CGFloat(index % 5) * proxy.size.width * 0.14 - proxy.size.width * 0.28,
                            y: CGFloat(index / 5) * proxy.size.height * 0.11 + proxy.size.height * 0.23
                        )
                }
            }
        }
    }
}

private struct MyClutterSidebar: View {
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
                    .foregroundStyle(.white.opacity(0.82), Color(hex: 0xDCE4FF).opacity(0.6))
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

private struct MyClutterSidebarIcon: View {
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
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0x8EA8FF).opacity(item == .myClutter ? 0.95 : 0.46))
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

private struct MyClutterBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x2C1B86),
                    Color(hex: 0x5142C8),
                    Color(hex: 0x13084F)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x6F7DFF).opacity(0.46),
                    .clear
                ],
                center: UnitPoint(x: 0.22, y: 0.42),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct DuplicateFile: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let selected: Int
    let total: Int
    let thumbnail: ThumbnailKind
    let isSelected: Bool

    static let samples = [
        DuplicateFile(name: "oasis_.png", size: "1,2 GB", selected: 6, total: 7, thumbnail: .oasis, isSelected: true),
        DuplicateFile(name: "selfie_2024.zip", size: "841 MB", selected: 4, total: 5, thumbnail: .zip, isSelected: false),
        DuplicateFile(name: "wow.png", size: "21,8 MB", selected: 2, total: 3, thumbnail: .oasis, isSelected: false),
        DuplicateFile(name: "selfie_1.jpg", size: "15,3 MB", selected: 3, total: 4, thumbnail: .people, isSelected: false),
        DuplicateFile(name: "love.jpg", size: "1,6 MB", selected: 1, total: 2, thumbnail: .people, isSelected: false)
    ]
}

private enum ThumbnailKind {
    case oasis
    case zip
    case people
}

private enum MyClutterSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#Preview {
    ClutterView()
        .frame(width: 1180, height: 760)
}
