import AppKit
import SwiftUI

struct CareLogDetailContent: View {
    let detail: CareLogDetail
    let onBack: () -> Void

    @State private var selectedSection = 0
    @State private var selectedItemID: String?

    private var sections: [String] {
        detail.category.detailSections
    }

    private var sourceItems: [CareScanDetailItem] {
        detail.snapshot.detailItems(for: detail.category)
    }

    private var filteredItems: [CareScanDetailItem] {
        let items = sourceItems
        guard selectedSection < sections.count else { return items }

        let section = sections[selectedSection]
        let sectionItems = items.filter { item in
            switch section {
            case "Browser Caches":
                item.kind == "Browser Cache"
            case "Application Caches":
                item.kind == "App Cache"
            case "System Caches":
                item.kind == "System Cache"
            case "Logs":
                item.kind == "Log File"
            case "Temporary Files":
                item.kind == "Temporary File"
            case "Developer Junk":
                item.kind == "Developer Cache" || item.kind == "Package Cache"
            case "Permissions":
                false
            case "Login Items":
                item.kind == "Startup Item"
            case "Launch Agents":
                item.kind == "Launch Agent"
            case "Launch Daemons":
                item.kind == "Launch Daemon"
            case "Background Helpers":
                item.kind == "Startup Item" || item.kind == "Launch Agent" || item.kind == "Launch Daemon"
            case "Applications", "Update Candidates", "Recently Modified", "Inventory":
                item.kind == "Application"
            case "Large & Old Files":
                item.kind == "Large File"
            case "Duplicates", "Similar Names":
                item.kind == "Duplicate Candidate"
            case "Downloads":
                item.path.localizedCaseInsensitiveContains("/Downloads/")
            case "Junk Cleaner":
                item.kind == "Browser Cache"
                    || item.kind == "App Cache"
                    || item.kind == "System Cache"
                    || item.kind == "Log File"
                    || item.kind == "Temporary File"
                    || item.kind == "Developer Cache"
                    || item.kind == "Package Cache"
            case "Boost":
                item.kind == "Startup Item" || item.kind == "Launch Agent" || item.kind == "Launch Daemon"
            case "App Manager":
                item.kind == "Application"
            case "Clutter":
                item.kind == "Large File" || item.kind == "Duplicate Candidate"
            default:
                true
            }
        }

        return sectionItems.isEmpty ? items : sectionItems
    }

    private var selectedItem: CareScanDetailItem? {
        filteredItems.first { $0.id == selectedItemID } ?? filteredItems.first
    }

    var body: some View {
        if detail.category == .junkCleaner {
            JunkCleanerManagerContent(detail: detail, onBack: onBack)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if detail.category == .boost {
            PerformanceManagerContent(detail: detail, onBack: onBack)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if detail.category == .clutter {
            ClutterManagerContent(onBack: onBack, snapshot: detail.snapshot)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            VStack(spacing: 0) {
                DetailTopBar(title: detail.category.detailTitle, onBack: onBack)

                HStack(spacing: 0) {
                    DetailSectionList(sections: sections, selectedSection: $selectedSection)
                        .frame(width: 270)

                    Divider()
                        .overlay(.white.opacity(0.12))

                    DetailItemList(
                        title: sections[safe: selectedSection] ?? detail.category.label,
                        subtitle: detail.category.detailSubtitle,
                        items: filteredItems,
                        selectedItemID: $selectedItemID,
                        fallbackLines: detail.category.lines(snapshot: detail.snapshot, cleaned: detail.cleaned),
                        permissions: detail.snapshot.permissionMessages
                    )
                    .frame(width: 360)

                    Divider()
                        .overlay(.white.opacity(0.12))

                    DetailPreviewPane(
                        item: selectedItem,
                        category: detail.category,
                        cleaned: detail.cleaned,
                        permissions: detail.snapshot.permissionMessages
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                DetailBottomBar(
                    itemCount: max(filteredItems.count, sourceItems.count),
                    sizeBytes: sourceItems.reduce(Int64(0)) { $0 + $1.sizeBytes },
                    cleaned: detail.cleaned
                )
            }
            .background(Color.black)
            .onAppear {
                selectedItemID = filteredItems.first?.id
            }
            .onChange(of: selectedSection) { _, _ in
                selectedItemID = filteredItems.first?.id
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}

struct PerformanceManagerContent: View {
    let snapshot: CareScanSnapshot
    let onBack: () -> Void
    let initialSection: PerformanceSection

    @State private var selectedSection: PerformanceSection
    @State private var selectedItemIDs = Set<String>()

    init(detail: CareLogDetail, onBack: @escaping () -> Void) {
        self.init(snapshot: detail.snapshot, initialSection: .loginItems, onBack: onBack)
    }

    init(snapshot: CareScanSnapshot, initialSection: PerformanceSection = .loginItems, onBack: @escaping () -> Void) {
        self.snapshot = snapshot
        self.initialSection = initialSection
        self.onBack = onBack
        _selectedSection = State(initialValue: initialSection)
    }

    private var loginItems: [CareScanDetailItem] {
        snapshot.startupDetails
            .filter { $0.kind == "Login Item" }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var backgroundItems: [CareScanDetailItem] {
        snapshot.startupDetails
            .filter { $0.kind == "Background Item" }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var selectedRows: [CareScanDetailItem] {
        switch selectedSection {
        case .loginItems:
            loginItems
        case .backgroundItems:
            backgroundItems
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PerformanceManagerTopBar(onBack: onBack)

            PerformanceItemList(
                section: selectedSection,
                items: selectedRows,
                selectedItemIDs: $selectedItemIDs
            )

            PerformanceManagerBottomBar(selectedCount: selectedItemIDs.count)
        }
        .background(Color.black)
    }
}

enum PerformanceSection: String, CaseIterable, Identifiable {
    case loginItems
    case backgroundItems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loginItems:
            "Login Items"
        case .backgroundItems:
            "Background Items"
        }
    }

    var description: String {
        switch self {
        case .loginItems:
            "Manage the list of applications that get automatically opened every time you log in. Don't make your Mac waste its performance on the processes you don't need."
        case .backgroundItems:
            "Manage the list of third-party processes and applications that run in the background. You may not need or want part of them."
        }
    }

    var emptyMessage: String {
        switch self {
        case .loginItems:
            "No third-party login items were found."
        case .backgroundItems:
            "No third-party background items were found."
        }
    }
}

private struct PerformanceManagerTopBar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x8EA8FF))
                    Text("Back")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Performance Manager")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            Spacer()

            HStack(spacing: 28) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))

                HStack(spacing: 6) {
                    Text("Sort by:")
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Name")
                        .foregroundStyle(Color(hex: 0x8EA8FF))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x8EA8FF))
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 28)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct PerformanceSectionList: View {
    let selectedSection: PerformanceSection
    let loginCount: Int
    let backgroundCount: Int
    let onSelect: (PerformanceSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(PerformanceSection.allCases) { section in
                Button {
                    onSelect(section)
                } label: {
                    HStack {
                        Text(section.title)
                        Spacer()
                        Text("\(count(for: section))")
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedSection == section ? .white.opacity(0.94) : .white.opacity(0.56))
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0x1C2A68))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 42)
        .background(Color.black)
    }

    private func count(for section: PerformanceSection) -> Int {
        switch section {
        case .loginItems:
            loginCount
        case .backgroundItems:
            backgroundCount
        }
    }
}

private struct PerformanceItemList: View {
    let section: PerformanceSection
    let items: [CareScanDetailItem]
    @Binding var selectedItemIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            Text(section.description)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.bottom, 36)

            HStack(spacing: 6) {
                Text("Select:")
                    .foregroundStyle(.white.opacity(0.9))
                Text(selectedItemIDs.isEmpty ? "None" : "\(selectedItemIDs.count)")
                    .foregroundStyle(Color(hex: 0x8EA8FF))
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .padding(.bottom, 34)

            if items.isEmpty {
                Text(section.emptyMessage)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.top, 12)
            } else {
                ScrollView {
                    VStack(spacing: 30) {
                        ForEach(items) { item in
                            PerformanceItemRow(
                                item: item,
                                isSelected: selectedItemIDs.contains(item.id)
                            ) {
                                if selectedItemIDs.contains(item.id) {
                                    selectedItemIDs.remove(item.id)
                                } else {
                                    selectedItemIDs.insert(item.id)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 18)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 34)
        .padding(.bottom, 18)
    }
}

private struct PerformanceItemRow: View {
    let item: CareScanDetailItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 28) {
                PerformanceCheckbox(isSelected: isSelected)

                PerformanceItemIcon(item: item)
                    .frame(width: 42, height: 42)

                Text(item.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(height: 54)
        }
        .buttonStyle(.plain)
    }
}

private struct PerformanceCheckbox: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isSelected ? Color(hex: 0x8EA8FF) : .clear)
            .frame(width: 18, height: 18)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(hex: 0x8EA8FF), lineWidth: 1.4)
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                }
            }
    }
}

private struct PerformanceItemIcon: View {
    let item: CareScanDetailItem

    var body: some View {
        if let icon = icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: item.kind == "Login Item" ? "app.fill" : "doc.text.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: 0x8EA8FF))
        }
    }

    private var icon: NSImage? {
        let path = item.path
        guard path.hasPrefix("/") else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

private struct PerformanceManagerBottomBar: View {
    let selectedCount: Int

    var body: some View {
        HStack {
            Spacer()

            Text(selectedCount == 0 ? "No Items Selected" : "\(selectedCount) Items Selected")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button("Remove") {}
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(selectedCount == 0 ? 0.38 : 1))
                .buttonStyle(.plain)
                .frame(width: 100, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x5366D6).opacity(selectedCount == 0 ? 0.55 : 1))
                }
                .disabled(selectedCount == 0)
        }
        .frame(height: 72)
        .padding(.horizontal, 18)
        .background(Color.black)
    }
}

private struct JunkCleanerManagerContent: View {
    let detail: CareLogDetail
    let onBack: () -> Void

    @State private var selectedSectionID: String?
    @State private var selectedGroupID: String?
    @State private var selectedItemIDs = Set<String>()

    private var sections: [JunkCleanerSection] {
        makeSections()
    }

    private var selectedSection: JunkCleanerSection? {
        sections.first { $0.id == selectedSectionID } ?? sections.first
    }

    private var groups: [JunkCleanerGroup] {
        guard let selectedSection else { return [] }
        return makeGroups(for: selectedSection)
    }

    private var selectedGroup: JunkCleanerGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    private var selectedRows: [CareScanDetailItem] {
        selectedGroup?.items.sorted { $0.sizeBytes > $1.sizeBytes } ?? []
    }

    private var selectedItems: [CareScanDetailItem] {
        sections.flatMap(\.items).filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            JunkCleanerManagerTopBar(onBack: onBack)

            HStack(spacing: 0) {
                JunkCleanerSectionList(
                    sections: sections,
                    selectedSectionID: $selectedSectionID
                )
                    .frame(width: 270)

                managerDivider

                JunkCleanerGroupList(
                    section: selectedSection,
                    groups: groups,
                    selectedGroupID: $selectedGroupID,
                    selectedItemIDs: selectedItemIDs,
                    permissions: detail.snapshot.permissionMessages
                )
                .frame(width: 330)

                managerDivider

                JunkCleanerFileList(
                    group: selectedGroup,
                    rows: selectedRows,
                    selectedItemIDs: $selectedItemIDs
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                JunkCleanerManagerBottomBar(
                    itemCount: selectedItems.count,
                    sizeBytes: selectedItems.reduce(Int64(0)) { $0 + $1.sizeBytes },
                    onDone: onBack
                )
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 12)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .onAppear {
            syncDefaultSelection()
        }
        .onChange(of: selectedSectionID) { _, _ in
            selectedGroupID = groups.first?.id
        }
    }

    private var managerDivider: some View {
            Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1)
    }

    private func syncDefaultSelection() {
        if selectedSectionID == nil || !sections.contains(where: { $0.id == selectedSectionID }) {
            selectedSectionID = sections.first?.id
        }

        if selectedGroupID == nil || !groups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = groups.first?.id
        }

        if selectedItemIDs.isEmpty {
            selectedItemIDs = Set(sections.flatMap(\.items).map(\.id))
        }
    }

    private func makeSections() -> [JunkCleanerSection] {
        let items = detail.snapshot.cacheDetails
        let trashItems = items.filter { $0.kind == "Trash Item" }
        let systemItems = items.filter { $0.kind != "Trash Item" }

        return [
            JunkCleanerSection(
                id: "system-junk",
                title: "System Junk",
                description: "User caches, Xcode files, and logs found during scan.",
                items: systemItems
            ),
            JunkCleanerSection(
                id: "trash-bins",
                title: "Trash Bins",
                description: "Items currently in your Mac Trash.",
                items: trashItems
            )
        ]
    }

    private func makeGroups(for section: JunkCleanerSection) -> [JunkCleanerGroup] {
        if section.id == "trash-bins" {
            return [
                makeGroup(
                    id: "trash-items",
                    title: "Trash Bins",
                    description: "Items currently waiting in Trash.",
                    symbolName: "trash.fill",
                    items: section.items
                )
            ]
        }

        return [
            makeGroup(
                id: "user-cache-files",
                title: "User Cache Files",
                description: "Browser, application, system, temporary, and package cache files.",
                symbolName: "checkmark.circle.fill",
                items: section.items.filter {
                    $0.kind == "Browser Cache"
                        || $0.kind == "App Cache"
                        || $0.kind == "System Cache"
                        || $0.kind == "Temporary File"
                        || $0.kind == "Package Cache"
                }
            ),
            makeGroup(
                id: "xcode-junk",
                title: "Xcode Junk",
                description: "Derived data, simulator, device support, archive, and developer cache files.",
                symbolName: "hammer.fill",
                items: section.items.filter { $0.kind == "Developer Cache" }
            ),
            makeGroup(
                id: "user-log-files",
                title: "User Log Files",
                description: "Application, crash, and system log files.",
                symbolName: "doc.text.fill",
                items: section.items.filter { $0.kind == "Log File" }
            )
        ]
    }

    private func makeGroup(id: String, title: String, description: String, symbolName: String, items: [CareScanDetailItem]) -> JunkCleanerGroup {
        let sortedItems = items.sorted { $0.sizeBytes > $1.sizeBytes }
        return JunkCleanerGroup(
            id: id,
            title: title,
            subtitle: "\(items.count) \(items.count == 1 ? "item" : "items")",
            description: description,
            path: sortedItems.first?.subtitle ?? "",
            sizeBytes: items.reduce(Int64(0)) { $0 + $1.sizeBytes },
            symbolName: symbolName,
            items: sortedItems
        )
    }

    private func groupSymbol(for kind: String) -> String {
        switch kind {
        case "Browser Cache":
            "globe"
        case "App Cache":
            "app.badge"
        case "System Cache":
            "internaldrive"
        case "Log File":
            "doc.text.fill"
        case "Temporary File":
            "clock.badge.exclamationmark"
        case "Developer Cache", "Package Cache":
            "hammer.fill"
        default:
            "folder.fill"
        }
    }

    private func cleanupBucketTitle(for item: CareScanDetailItem) -> String {
        let path = item.path
        let components = URL(fileURLWithPath: path).pathComponents

        if path.localizedCaseInsensitiveContains("/.gradle/") {
            return "Gradle"
        }
        if path.localizedCaseInsensitiveContains("/.npm/") {
            return "npm"
        }
        if path.localizedCaseInsensitiveContains("/.m2/") {
            return "Maven"
        }
        if path.localizedCaseInsensitiveContains("/Chrome/") || path.localizedCaseInsensitiveContains("/Google/") {
            return "Google"
        }
        if path.localizedCaseInsensitiveContains("/BraveSoftware/") {
            return "BraveSoftware"
        }
        if path.localizedCaseInsensitiveContains("/Firefox/") {
            return "Firefox"
        }
        if path.localizedCaseInsensitiveContains("/Microsoft Edge/") {
            return "Microsoft Edge"
        }
        if path.localizedCaseInsensitiveContains("/Arc/") || path.localizedCaseInsensitiveContains("company.thebrowser") {
            return "Arc"
        }
        if path.localizedCaseInsensitiveContains("/Safari/") || path.localizedCaseInsensitiveContains("com.apple.Safari") {
            return "Safari"
        }
        if let title = component(after: "Caches", in: components), !title.hasPrefix(".") {
            return displayTitle(title)
        }
        if let title = component(after: "Application Support", in: components), !title.hasPrefix(".") {
            return displayTitle(title)
        }
        if let title = component(after: "Developer", in: components) {
            return displayTitle(title)
        }

        return displayTitle(item.subtitle)
    }

    private func component(after marker: String, in components: [String]) -> String? {
        guard let index = components.firstIndex(of: marker),
              components.indices.contains(index + 1) else {
            return nil
        }
        return components[index + 1]
    }

    private func displayTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: ".Cache", with: "")
            .replacingOccurrences(of: " Cache", with: "")
            .replacingOccurrences(of: " Caches", with: "")
    }

    private func commonPath(for paths: [String]) -> String {
        guard let first = paths.first else { return "Not available" }
        let firstComponents = URL(fileURLWithPath: first).deletingLastPathComponent().pathComponents
        let commonComponents = paths.dropFirst().reduce(firstComponents) { partial, path in
            let components = URL(fileURLWithPath: path).deletingLastPathComponent().pathComponents
            return Array(zip(partial, components).prefix { $0 == $1 }.map(\.0))
        }
        return commonComponents.isEmpty ? first : NSString.path(withComponents: commonComponents)
    }
}

private struct JunkCleanerManagerTopBar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .bold))

                    Text("Back")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(JunkCleanerManagerPalette.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Cleanup Manager")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(JunkCleanerManagerPalette.text)

            Spacer()

            HStack(spacing: 26) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(JunkCleanerManagerPalette.accent)

                HStack(spacing: 7) {
                    Text("Sort by:")
                        .foregroundStyle(JunkCleanerManagerPalette.text)

                    Text("Size")
                        .foregroundStyle(JunkCleanerManagerPalette.accent)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(JunkCleanerManagerPalette.accent)
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(width: 236, alignment: .trailing)
        }
        .frame(height: 70)
        .padding(.horizontal, 34)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct JunkCleanerSectionList: View {
    let sections: [JunkCleanerSection]
    @Binding var selectedSectionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                Button {
                    selectedSectionID = section.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedSectionID == section.id ? JunkCleanerManagerPalette.text : JunkCleanerManagerPalette.secondary)
                            .lineLimit(1)

                        if !section.items.isEmpty {
                            Text("\(section.items.count) items")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(JunkCleanerManagerPalette.secondary.opacity(0.72))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background {
                        if selectedSectionID == section.id {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(JunkCleanerManagerPalette.selection)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 42)
        .padding(.bottom, 88)
        .background(Color.black)
    }
}

private struct JunkCleanerGroupList: View {
    let section: JunkCleanerSection?
    let groups: [JunkCleanerGroup]
    @Binding var selectedGroupID: String?
    let selectedItemIDs: Set<String>
    let permissions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(section?.title ?? "Scan Results")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.text)

                Text(section?.description ?? "Run Scan to populate this view with real junk files.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !permissions.isEmpty {
                JunkCleanerPermissionNotice(messages: permissions)
            }

            if groups.isEmpty {
                JunkCleanerEmptyRowsView(
                    title: "No file groups",
                    message: "This section has no real scanned files to show."
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(groups) { group in
                            JunkCleanerGroupRow(
                                group: group,
                                isSelected: selectedGroupID == group.id
                            ) {
                                selectedGroupID = group.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 38)
        .padding(.bottom, 96)
        .background(Color.black)
    }
}

private struct JunkCleanerGroupRow: View {
    let group: JunkCleanerGroup
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(JunkCleanerManagerPalette.blueGradient)

                    Image(systemName: group.symbolName)
                        .font(.system(size: 21, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(JunkCleanerManagerPalette.text)
                        .lineLimit(1)

                    Text(group.subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(JunkCleanerManagerPalette.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(formatBytes(group.sizeBytes))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background {
                        Capsule(style: .continuous)
                            .fill(JunkCleanerManagerPalette.accent)
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? JunkCleanerManagerPalette.selection : JunkCleanerManagerPalette.panel)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct JunkCleanerFileList: View {
    let group: JunkCleanerGroup?
    let rows: [CareScanDetailItem]
    @Binding var selectedItemIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                    Text(group?.title ?? "Files")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.text)

                    Text(group?.description ?? "Select a category to review scanned items.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                toggleVisibleRows()
            } label: {
                HStack(spacing: 8) {
                    Text("Select:")
                        .foregroundStyle(JunkCleanerManagerPalette.text)

                    Text(allRowsSelected ? "None" : "All")
                        .foregroundStyle(JunkCleanerManagerPalette.accent)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(JunkCleanerManagerPalette.accent)
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .buttonStyle(.plain)

            if rows.isEmpty {
                JunkCleanerEmptyRowsView(
                    title: "No files in this group",
                    message: "This group has no real scanned file rows."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(rows) { item in
                            JunkCleanerFileRow(
                                item: item,
                                isSelected: selectedItemIDs.contains(item.id)
                            ) {
                                toggle(item)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 38)
        .padding(.bottom, 104)
        .background(Color.black)
    }

    private var allRowsSelected: Bool {
        !rows.isEmpty && rows.allSatisfy { selectedItemIDs.contains($0.id) }
    }

    private func toggle(_ item: CareScanDetailItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    private func toggleVisibleRows() {
        if allRowsSelected {
            rows.forEach { selectedItemIDs.remove($0.id) }
        } else {
            rows.forEach { selectedItemIDs.insert($0.id) }
        }
    }
}

private struct JunkCleanerFileRow: View {
    let item: CareScanDetailItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? JunkCleanerManagerPalette.accent : JunkCleanerManagerPalette.secondary)

                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(JunkCleanerManagerPalette.icon)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(JunkCleanerManagerPalette.text)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.formattedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.secondary)
                    .frame(width: 78, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(JunkCleanerManagerPalette.accent)
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? JunkCleanerManagerPalette.selection.opacity(0.72) : JunkCleanerManagerPalette.panel)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch item.kind {
        case "Browser Cache":
            "globe"
        case "App Cache":
            "app.badge"
        case "System Cache":
            "internaldrive"
        case "Log File":
            "doc.text.fill"
        case "Temporary File":
            "clock.badge.exclamationmark"
        case "Developer Cache", "Package Cache":
            "hammer.fill"
        default:
            "doc.fill"
        }
    }
}

private struct JunkCleanerEmptyRowsView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(JunkCleanerManagerPalette.text)

            Text(message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(JunkCleanerManagerPalette.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JunkCleanerManagerPalette.panel)
        }
    }
}

private struct JunkCleanerPermissionNotice: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More access may be needed")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(JunkCleanerManagerPalette.text)

            Text(messages.prefix(2).joined(separator: " "))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(JunkCleanerManagerPalette.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(JunkCleanerManagerPalette.panel)
        }
    }
}

private struct JunkCleanerManagerBottomBar: View {
    let itemCount: Int
    let sizeBytes: Int64
    let onDone: () -> Void

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 14) {
                Text("\(itemCount) Items Selected")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.text)

                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1, height: 27)

                Text(formatBytes(sizeBytes))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(JunkCleanerManagerPalette.secondary)
            }

            Spacer()

            Button("Done", action: onDone)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(JunkCleanerManagerPalette.actionGradient)
                }
        }
        .padding(.horizontal, 28)
        .frame(height: 74)
        .background(JunkCleanerManagerPalette.bottomBar)
    }
}

private struct JunkCleanerSection: Identifiable {
    let id: String
    let title: String
    let description: String
    let items: [CareScanDetailItem]
}

private struct JunkCleanerGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let path: String
    let sizeBytes: Int64
    let symbolName: String
    let items: [CareScanDetailItem]
}

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private enum JunkCleanerManagerPalette {
    static let accent = Color(hex: 0x8EA8FF)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.58)
    static let icon = Color(hex: 0x6EB8E5)
    static let panel = Color.white.opacity(0.06)
    static let selection = Color(hex: 0x1C2A68)
    static let bottomBar = Color.black
    static let blueGradient = LinearGradient(
        colors: [
            Color(hex: 0x8FA6FF),
            Color(hex: 0x5366D6)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let actionGradient = LinearGradient(
        colors: [
            Color(hex: 0x8EA8FF),
            Color(hex: 0x5366D6)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
private struct DetailTopBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 26, weight: .bold))

                    Text("Back")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(hex: 0x7180FF))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(CachePopPalette.heading)

            Spacer()

            HStack(spacing: 30) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: 0x7180FF))

                HStack(spacing: 8) {
                    Text("Sort by:")
                        .foregroundStyle(CachePopPalette.heading)

                    Text("Size")
                        .foregroundStyle(Color(hex: 0x7180FF))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x7180FF))
                }
                .font(.system(size: 19, weight: .bold, design: .rounded))
            }
            .frame(width: 250, alignment: .trailing)
        }
        .frame(height: 74)
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct DetailSectionList: View {
    let sections: [String]
    @Binding var selectedSection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
                .frame(height: 58)

            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        selectedSection = index
                    }
                } label: {
                    Text(section)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedSection == index ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .frame(height: 54)
                        .background {
                            if selectedSection == index {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: 0x1C2A68))
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

private struct DetailItemList: View {
    let title: String
    let subtitle: String
    let items: [CareScanDetailItem]
    @Binding var selectedItemID: String?
    let fallbackLines: [String]
    let permissions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CachePopPalette.heading)

            Text(subtitle)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if !permissions.isEmpty {
                PermissionNotice(messages: permissions)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if items.isEmpty {
                        if permissions.isEmpty {
                            ForEach(Array(fallbackLines.enumerated()), id: \.offset) { _, line in
                                DetailFallbackRow(text: line)
                            }
                        } else {
                            DetailFallbackRow(text: "No file rows are available yet because macOS blocked these folders. Grant access, run Scan again, and this page will show the real cache files here.")
                        }
                    } else {
                        ForEach(items.sorted { $0.sizeBytes > $1.sizeBytes }) { item in
                            DetailFileRow(item: item, isSelected: selectedItemID == item.id) {
                                selectedItemID = item.id
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 18)
    }
}

private struct DetailFileRow: View {
    let item: CareScanDetailItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DetailFileIcon(kind: item.kind)
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(item.formattedSize)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color(hex: 0x1C2A68) : .clear)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DetailFallbackRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.05))
            }
    }
}

private struct DetailPreviewPane: View {
    let item: CareScanDetailItem?
    let category: CareLogCategory
    let cleaned: Bool
    let permissions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Text("Select:")
                    .foregroundStyle(CachePopPalette.heading)

                Text(cleaned ? "Cleaned" : "Smartly")
                    .foregroundStyle(Color(hex: 0x7180FF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x7180FF))
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xA8B9FF),
                                Color(hex: 0x6D82F0),
                                Color(hex: 0x312994)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                DetailPreviewSymbol(category: category)
            }
            .frame(maxWidth: 420)
            .aspectRatio(1.08, contentMode: .fit)

            VStack(alignment: .leading, spacing: 17) {
                Text(item?.title ?? category.label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                DetailMetaRow(label: "Location:", value: item?.path ?? "No item selected")
                DetailMetaRow(label: "Modified:", value: item?.modifiedText ?? "Not available")
                DetailMetaRow(label: "Size:", value: item?.formattedSize ?? "0 KB")
                DetailMetaRow(label: "File type:", value: item?.kind ?? category.label)
            }

            if !permissions.isEmpty {
                Button("Grant Access") {
                    openPrivacySettings()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CachePopPalette.actionGradient)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 54)
        .padding(.bottom, 22)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct DetailPreviewSymbol: View {
    let category: CareLogCategory

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .stroke(.white.opacity(0.86), lineWidth: 8)
                .frame(width: 210, height: 160)

            Image(systemName: category.previewSymbol)
                .font(.system(size: 72, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

private struct DetailMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct DetailBottomBar: View {
    let itemCount: Int
    let sizeBytes: Int64
    let cleaned: Bool

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 16) {
                Text("\(itemCount) Items Selected")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 28)

                Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            Button(cleaned ? "Done" : "Remove") {}
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .padding(.horizontal, 25)
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CachePopPalette.actionGradient)
                }
                .padding(.trailing, 32)
        }
        .frame(height: 86)
    }
}

private struct PermissionNotice: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More access may be needed")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(messages.prefix(2).joined(separator: " "))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(3)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct DetailFileIcon: View {
    let kind: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CachePopPalette.actionGradient)
                .opacity(0.92)

            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
    }

    private var symbolName: String {
        switch kind {
        case "Browser Cache":
            "globe"
        case "App Cache":
            "app.badge"
        case "System Cache":
            "internaldrive"
        case "Log File":
            "doc.text.magnifyingglass"
        case "Temporary File":
            "clock.badge.exclamationmark"
        case "Developer Cache", "Package Cache":
            "hammer.fill"
        case "Launch Agent", "Launch Daemon", "Startup Item":
            "bolt.fill"
        case "Application":
            "sparkles"
        case "Duplicate Candidate":
            "doc.on.doc.fill"
        case "Large File":
            "doc.fill"
        default:
            "doc"
        }
    }
}

private extension CareLogCategory {
    var detailTitle: String {
        switch self {
        case .junkCleaner:
            "Junk Cleaner"
        case .boost:
            "Boost Manager"
        case .appManager:
            "App Manager"
        case .clutter:
            "Clutter Manager"
        case .all:
            "After Cleaning Result Logs"
        }
    }

    var detailSubtitle: String {
        switch self {
        case .junkCleaner:
            "Browser junk, app caches, logs, temporary files, and developer cache files found on this Mac."
        case .boost:
            "Startup helpers that can affect login and background performance."
        case .appManager:
            "Installed apps scanned for inventory and update review."
        case .clutter:
            "Large files, downloads, and duplicate candidates found during scan."
        case .all:
            "Complete scan and cleaning results grouped by component."
        }
    }

    var detailSections: [String] {
        switch self {
        case .junkCleaner:
            ["Browser Caches", "Application Caches", "System Caches", "Logs", "Temporary Files", "Developer Junk", "Permissions"]
        case .boost:
            ["Login Items", "Launch Agents", "Launch Daemons", "Background Helpers"]
        case .appManager:
            ["Applications", "Update Candidates", "Recently Modified", "Inventory"]
        case .clutter:
            ["Large & Old Files", "Duplicates", "Downloads", "Similar Names"]
        case .all:
            ["Junk Cleaner", "Boost", "App Manager", "Clutter"]
        }
    }

    var previewSymbol: String {
        switch self {
        case .junkCleaner:
            "face.smiling.inverse"
        case .boost:
            "bolt.fill"
        case .appManager:
            "sparkles"
        case .clutter:
            "folder.fill"
        case .all:
            "checkmark.circle.fill"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
