import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            case "Privacy Traces":
                item.kind == "Privacy Trace"
            case "Downloaded Installers":
                item.kind == "Installer Leftover"
            case "Protection Review":
                item.kind == "Privacy Trace" || item.kind == "Installer Leftover"
            case "Login Items":
                item.kind == "Login Item"
            case "Launch Agents":
                item.kind == "Background Item"
            case "Launch Daemons":
                item.kind == "Background Item"
            case "Background Helpers":
                item.kind == "Login Item" || item.kind == "Background Item"
            case "Applications", "Update Candidates", "Recently Modified", "Inventory":
                item.kind == "Application"
            case "Large & Old Files":
                item.kind == "Large File"
            case "Duplicates", "Similar Names":
                item.kind == "Duplicate Candidate"
            case "Downloads":
                item.path.localizedCaseInsensitiveContains("/Downloads/")
            case "Cleanup":
                item.kind == "Browser Cache"
                    || item.kind == "App Cache"
                    || item.kind == "System Cache"
                    || item.kind == "Log File"
                    || item.kind == "Temporary File"
                    || item.kind == "Developer Cache"
                    || item.kind == "Package Cache"
            case "Protection":
                item.kind == "Privacy Trace" || item.kind == "Installer Leftover"
            case "Performance":
                item.kind == "Login Item" || item.kind == "Background Item"
            case "My Clutter":
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
        if detail.category == .cleanup {
            JunkCleanerManagerContent(detail: detail, onBack: onBack)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if detail.category == .performance {
            PerformanceManagerContent(detail: detail, onBack: onBack)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if detail.category == .myClutter {
            ClutterManagerContent(onBack: onBack, snapshot: detail.snapshot)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            VStack(spacing: 0) {
                DetailTopBar(title: detail.category.detailTitle, onBack: onBack)

                HStack(spacing: 0) {
                    DetailSectionList(category: detail.category, sections: sections, selectedSection: $selectedSection)
                        .frame(width: 270)

                    Divider()
                        .overlay(AppTheme.Colors.border)

                    DetailItemList(
                        category: detail.category,
                        title: sections[safe: selectedSection] ?? detail.category.label,
                        subtitle: detail.category.detailSubtitle,
                        items: filteredItems,
                        selectedItemID: $selectedItemID,
                        fallbackLines: detail.category.lines(snapshot: detail.snapshot, cleaned: detail.cleaned),
                        permissions: detail.snapshot.permissionMessages
                    )
                    .frame(width: 360)

                    Divider()
                        .overlay(AppTheme.Colors.border)

                    DetailPreviewPane(
                        item: selectedItem,
                        category: detail.category,
                        cleaned: detail.cleaned,
                        permissions: detail.snapshot.permissionMessages
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                DetailBottomBar(
                    category: detail.category,
                    itemCount: max(filteredItems.count, sourceItems.count),
                    sizeBytes: sourceItems.reduce(Int64(0)) { $0 + $1.sizeBytes },
                    cleaned: detail.cleaned
                )
            }
            .background(AppTheme.Colors.appBackground)
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
    let onBack: () -> Void
    let initialSection: PerformanceSection

    @State private var selectedSection: PerformanceSection
    @State private var selectedItemIDs = Set<String>()
    @State private var allItems: [CareScanDetailItem]
    @State private var isRemoving = false
    @State private var removalResult: StartupItemRemovalResult?
    @State private var errorMessage: String?

    init(detail: CareLogDetail, onBack: @escaping () -> Void) {
        self.init(snapshot: detail.snapshot, initialSection: .loginItems, onBack: onBack)
    }

    init(snapshot: CareScanSnapshot, initialSection: PerformanceSection = .loginItems, onBack: @escaping () -> Void) {
        self.initialSection = initialSection
        self.onBack = onBack
        _selectedSection = State(initialValue: initialSection)
        _allItems = State(initialValue: snapshot.startupDetails)
    }

    private var loginItems: [CareScanDetailItem] {
        allItems
            .filter { $0.kind == "Login Item" }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var backgroundItems: [CareScanDetailItem] {
        allItems
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

    /// Only items CachePop can actually act on count toward the Remove button.
    private var actionableSelection: [CareScanDetailItem] {
        allItems.filter { selectedItemIDs.contains($0.id) && StartupItemService.canAct(on: $0) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                PerformanceManagerTopBar(onBack: onBack)

                if let removalResult {
                    StartupRemovalBanner(result: removalResult) {
                        self.removalResult = nil
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 14)
                }

                if let errorMessage {
                    InlineWarningBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 14)
                }

                PerformanceSectionList(
                    selectedSection: selectedSection,
                    loginCount: loginItems.count,
                    backgroundCount: backgroundItems.count
                ) { section in
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedSection = section
                    }
                }
                .frame(height: 54)

                PerformanceItemList(
                    section: selectedSection,
                    items: selectedRows,
                    selectedItemIDs: $selectedItemIDs
                )

                PerformanceManagerBottomBar(
                    selectedCount: actionableSelection.count,
                    isRemoving: isRemoving,
                    onRemove: performRemoval
                )
            }

            if isRemoving {
                UninstallProgressOverlay()
            }
        }
        .background(AppTheme.Colors.appBackground)
    }

    private func performRemoval() {
        let targets = actionableSelection
        guard !targets.isEmpty else { return }

        isRemoving = true
        errorMessage = nil
        removalResult = nil

        Task {
            let result = await StartupItemService.remove(items: targets)

            // Drop everything that was successfully handled from the list.
            let failed = Set(result.failedPaths)
            let handledIDs = Set(
                targets
                    .filter { !failed.contains($0.path) }
                    .map(\.id)
            )

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    allItems.removeAll { handledIDs.contains($0.id) }
                }
                selectedItemIDs.subtract(handledIDs)
                isRemoving = false
                removalResult = result

                if result.hasFailures {
                    errorMessage = "\(result.failedPaths.count) item(s) could not be changed. Grant Full Disk Access, or handle them manually in System Settings."
                }
            }
        }
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
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Back")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                }
            }
            .buttonStyle(.appInteractive)

            Spacer()

            Text("Performance Manager")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))

            Spacer()

            HStack(spacing: 28) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                HStack(spacing: 6) {
                    Text("Sort by:")
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
                    Text("Name")
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 28)
        .background(AppTheme.Colors.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Colors.border)
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
        HStack(spacing: 8) {
            ForEach(PerformanceSection.allCases) { section in
                Button {
                    onSelect(section)
                } label: {
                    HStack(spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Text("\(count(for: section))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedSection == section ? .white : AppTheme.Colors.textTertiary)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selectedSection == section
                                          ? AnyShapeStyle(FeatureAccent.boost.solid)
                                          : AnyShapeStyle(AppTheme.Colors.border))
                            }
                    }
                    .foregroundStyle(selectedSection == section ? FeatureAccent.boost.solid : AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background {
                        Capsule(style: .continuous)
                            .fill(selectedSection == section ? FeatureAccent.boost.tint : AppTheme.Colors.glassBg)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(
                                        selectedSection == section
                                            ? FeatureAccent.boost.solid.opacity(0.35)
                                            : AppTheme.Colors.border,
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .buttonStyle(.appInteractive)
            }

            Spacer()
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.appBackground)
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

    fileprivate var actionableItems: [CareScanDetailItem] {
        items.filter { StartupItemService.canAct(on: $0) }
    }

    fileprivate var allActionableSelected: Bool {
        !actionableItems.isEmpty && actionableItems.allSatisfy { selectedItemIDs.contains($0.id) }
    }

    fileprivate func toggleAll() {
        if allActionableSelected {
            actionableItems.forEach { selectedItemIDs.remove($0.id) }
        } else {
            actionableItems.forEach { selectedItemIDs.insert($0.id) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.description)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.56))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 660, alignment: .leading)
                .padding(.bottom, 20)

            HStack(spacing: 10) {
                Button(action: toggleAll) {
                    Text(allActionableSelected ? "Deselect all" : "Select all removable")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(FeatureAccent.boost.solid)
                }
                .buttonStyle(.plain)
                .disabled(actionableItems.isEmpty)

                Text("·")
                    .foregroundStyle(AppTheme.Colors.textTertiary)

                Text("\(selectedItemIDs.count) selected")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.bottom, 22)

            if items.isEmpty {
                Text(section.emptyMessage)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.56))
                    .padding(.top, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
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

    private var removability: StartupItemRemovability {
        StartupItemService.removability(for: item)
    }

    private var isLocked: Bool { removability == .requiresAdmin }

    var body: some View {
        Button(action: { if !isLocked { onToggle() } }) {
            HStack(spacing: 18) {
                PerformanceCheckbox(isSelected: isSelected, isDisabled: isLocked)

                PerformanceItemIcon(item: item)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(isLocked ? 0.5 : 0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(removability.explanation)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                switch removability {
                case .removable:
                    AccentPillBadge(accent: .boost, text: "Removable")
                case .quittable:
                    StatusPillBadge(color: AppTheme.Status.success, text: "Running")
                case .requiresAdmin:
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Locked")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                }

                Button {
                    StartupItemService.revealInFinder(item.path)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? FeatureAccent.boost.tint : AppTheme.Colors.glassBg)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.72 : 1)
        .help(isLocked ? removability.explanation : "")
    }
}

private struct PerformanceCheckbox: View {
    let isSelected: Bool
    var isDisabled = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isSelected ? FeatureAccent.boost.solid : Color.clear)
            .frame(width: 19, height: 19)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isDisabled ? AppTheme.Colors.border
                            : (isSelected ? FeatureAccent.boost.solid : AppTheme.Colors.glassBorder),
                        lineWidth: 1.5
                    )
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .opacity(isDisabled ? 0.4 : 1)
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
                .foregroundStyle(AppTheme.Colors.textPrimary)
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
    let isRemoving: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Text(selectedCount == 0 ? "No Items Selected" : "\(selectedCount) Item\(selectedCount == 1 ? "" : "s") Selected")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer()

            Button(action: onRemove) {
                Text(isRemoving ? "Removing…" : "Remove")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(selectedCount == 0 ? 0.6 : 1))
                    .frame(width: 116, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FeatureAccent.boost.gradient.opacity(selectedCount == 0 ? 0.45 : 1))
                    }
            }
            .buttonStyle(.appInteractive)
            .raisedButtonChrome(cornerRadius: 12)
            .disabled(selectedCount == 0 || isRemoving)
        }
        .frame(height: 72)
        .padding(.horizontal, 18)
        .background(AppTheme.Colors.appBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(height: 1)
        }
    }
}

private struct StartupRemovalBanner: View {
    let result: StartupItemRemovalResult
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.totalHandled > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(result.totalHandled > 0 ? AppTheme.Status.success : AppTheme.Colors.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.summary)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if result.skippedAdminCount > 0 {
                    Text("\(result.skippedAdminCount) system-level item(s) skipped — those need administrator rights.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.Status.successTint)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(AppTheme.Status.success.opacity(0.3), lineWidth: 1)
                }
        }
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
        .background(AppTheme.Colors.appBackground)
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
            .fill(AppTheme.Colors.border.opacity(0.7))
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
                .foregroundStyle(AppTheme.JunkCleanerManager.accent)
            }
            .buttonStyle(.appInteractive)

            Spacer()

            Text("Cleanup Manager")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.JunkCleanerManager.text)

            Spacer()

            HStack(spacing: 26) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.JunkCleanerManager.accent)

                HStack(spacing: 7) {
                    Text("Sort by:")
                        .foregroundStyle(AppTheme.JunkCleanerManager.text)

                    Text("Size")
                        .foregroundStyle(AppTheme.JunkCleanerManager.accent)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.JunkCleanerManager.accent)
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .frame(width: 236, alignment: .trailing)
        }
        .frame(height: 70)
        .padding(.horizontal, 34)
        .background(AppTheme.Colors.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Colors.border.opacity(0.7))
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
                            .foregroundStyle(selectedSectionID == section.id ? AppTheme.JunkCleanerManager.text : AppTheme.JunkCleanerManager.secondary)
                            .lineLimit(1)

                        if !section.items.isEmpty {
                            Text("\(section.items.count) items")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.JunkCleanerManager.secondary.opacity(0.72))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background {
                        if selectedSectionID == section.id {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.JunkCleanerManager.selection)
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
        .background(AppTheme.Colors.appBackground)
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
                    .foregroundStyle(AppTheme.JunkCleanerManager.text)

                Text(section?.description ?? "Run Scan to populate this view with real junk files.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
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
        .background(AppTheme.Colors.appBackground)
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
                        .fill(AppTheme.JunkCleanerManager.blueGradient)

                    Image(systemName: group.symbolName)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.JunkCleanerManager.text)
                        .lineLimit(1)

                    Text(group.subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
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
                            .fill(AppTheme.JunkCleanerManager.accent)
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppTheme.JunkCleanerManager.selection : AppTheme.JunkCleanerManager.panel)
            }
            .rowHoverBorder()
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
                    .foregroundStyle(AppTheme.JunkCleanerManager.text)

                    Text(group?.description ?? "Select a category to review scanned items.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                toggleVisibleRows()
            } label: {
                HStack(spacing: 8) {
                    Text("Select:")
                        .foregroundStyle(AppTheme.JunkCleanerManager.text)

                    Text(allRowsSelected ? "None" : "All")
                        .foregroundStyle(AppTheme.JunkCleanerManager.accent)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.JunkCleanerManager.accent)
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .buttonStyle(.appInteractive)

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
        .background(AppTheme.Colors.appBackground)
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
                    .foregroundStyle(isSelected ? AppTheme.JunkCleanerManager.accent : AppTheme.JunkCleanerManager.secondary)

                FileSystemIconView(
                    item: item,
                    fallbackSymbolName: iconName,
                    fallbackColor: AppTheme.JunkCleanerManager.icon
                )
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.JunkCleanerManager.text)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.formattedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
                    .frame(width: 78, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppTheme.JunkCleanerManager.accent)
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppTheme.JunkCleanerManager.selection.opacity(0.72) : AppTheme.JunkCleanerManager.panel)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.JunkCleanerManager.panel)
                    .frame(width: 50, height: 50)

                Image(systemName: "tray")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.JunkCleanerManager.text)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.JunkCleanerManager.panel.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
        }
    }
}

private struct JunkCleanerPermissionNotice: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More access may be needed")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.JunkCleanerManager.text)

            Text(messages.prefix(2).joined(separator: " "))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.JunkCleanerManager.panel)
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
                    .foregroundStyle(AppTheme.JunkCleanerManager.text)

                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 27)

                Text(formatBytes(sizeBytes))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.JunkCleanerManager.secondary)
            }

            Spacer()

            Button("Done", action: onDone)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppTheme.JunkCleanerManager.actionGradient)
                }
                .accentGlow(.cleanup, radius: 10, y: 4)
                .raisedButtonChrome(cornerRadius: 13)
        }
        .padding(.horizontal, 28)
        .frame(height: 74)
        .background(AppTheme.JunkCleanerManager.bottomBar)
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

private struct DetailTopBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))

                    Text("Back")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .buttonStyle(.appInteractive)

            Spacer()

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Care.heading)

            Spacer()

            HStack(spacing: 30) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 8) {
                    Text("Sort by:")
                        .foregroundStyle(AppTheme.Care.heading)

                    Text("Size")
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(width: 250, alignment: .trailing)
        }
        .frame(height: 74)
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(height: 1)
        }
    }
}

private struct DetailSectionList: View {
    let category: CareLogCategory
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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedSection == index ? AppTheme.Colors.inverseText : AppTheme.Colors.textPrimary.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .frame(height: 54)
                        .background {
                            if selectedSection == index {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(category.accent.gradient)
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
    let category: CareLogCategory
    let title: String
    let subtitle: String
    let items: [CareScanDetailItem]
    @Binding var selectedItemID: String?
    let fallbackLines: [String]
    let permissions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Care.heading)

            Text(subtitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.55))
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
                            DetailFileRow(category: category, item: item, isSelected: selectedItemID == item.id) {
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
    let category: CareLogCategory
    let item: CareScanDetailItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DetailFileIcon(item: item)
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.Colors.inverseText : AppTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(item.formattedSize)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.Colors.inverseText.opacity(0.74) : AppTheme.Colors.textPrimary.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(category.accent.gradient)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DetailFallbackRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.Colors.glassBg)
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
                    .foregroundStyle(AppTheme.Care.heading)

                Text(cleaned ? "Cleaned" : "Smartly")
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                    Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(category.accent.gradient)

                DetailPreviewSymbol(item: item, category: category)
            }
            .frame(maxWidth: 420)
            .aspectRatio(1.08, contentMode: .fit)

            VStack(alignment: .leading, spacing: 17) {
                    Text(item?.title ?? category.label)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
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
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 20)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(category.accent.gradient)
                }
                .raisedButtonChrome(cornerRadius: 10)
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
    let item: CareScanDetailItem?
    let category: CareLogCategory

    var body: some View {
        FileSystemIconView(
            item: item,
            fallbackSymbolName: symbolName,
            fallbackColor: AppTheme.Colors.inverseText.opacity(0.92),
            backgroundOpacity: 0,
            cornerRadius: 20
        )
        .padding(54)
    }

    private var symbolName: String {
        item.map { DetailFileIcon.symbolName(for: $0.kind) } ?? category.previewSymbol
    }
}

private struct DetailMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.45))
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct DetailBottomBar: View {
    let category: CareLogCategory
    let itemCount: Int
    let sizeBytes: Int64
    let cleaned: Bool

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 16) {
                Text("\(itemCount) Items Selected")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 28)

                Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.48))
            }

            Spacer()

            Button(cleaned ? "Done" : "Remove") {}
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 25)
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(category.accent.gradient)
                }
                .accentGlow(category.accent, radius: 12, y: 5)
                .raisedButtonChrome(cornerRadius: 14)
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
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(messages.prefix(2).joined(separator: " "))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.62))
                .lineLimit(3)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Colors.glassBg)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
        }
    }
}

private struct DetailFileIcon: View {
    let item: CareScanDetailItem

    var body: some View {
        FileSystemIconView(
            item: item,
            fallbackSymbolName: symbolName,
            fallbackColor: AppTheme.Colors.inverseText
        )
    }

    private var symbolName: String {
        Self.symbolName(for: item.kind)
    }

    static func symbolName(for kind: String) -> String {
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
        case "Launch Agent", "Launch Daemon", "Startup Item", "Login Item", "Background Item":
            "bolt.fill"
        case "Application":
            "sparkles"
        case "Privacy Trace":
            "hand.raised.fill"
        case "Installer Leftover":
            "shield.lefthalf.filled"
        case "Duplicate Candidate":
            "doc.on.doc.fill"
        case "Large File":
            "doc.fill"
        default:
            "doc"
        }
    }
}

private struct FileSystemIconView: View {
    let item: CareScanDetailItem?
    let fallbackSymbolName: String
    let fallbackColor: AnyShapeStyle
    var backgroundOpacity: Double = 0.92
    var cornerRadius: CGFloat = 7

    init<S: ShapeStyle>(
        item: CareScanDetailItem?,
        fallbackSymbolName: String,
        fallbackColor: S,
        backgroundOpacity: Double = 0.92,
        cornerRadius: CGFloat = 7
    ) {
        self.item = item
        self.fallbackSymbolName = fallbackSymbolName
        self.fallbackColor = AnyShapeStyle(fallbackColor)
        self.backgroundOpacity = backgroundOpacity
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            if backgroundOpacity > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.Care.actionGradient)
                    .opacity(backgroundOpacity)
            }

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(backgroundOpacity > 0 ? 7 : 0)
            } else {
                Image(systemName: fallbackSymbolName)
                    .font(.system(size: backgroundOpacity > 0 ? 22 : 62, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(fallbackColor)
            }
        }
    }

    private var icon: NSImage? {
        guard let item else { return nil }
        return FileIconResolver.icon(for: item)
    }
}

private enum FileIconResolver {
    static func icon(for item: CareScanDetailItem) -> NSImage? {
        if item.path.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: item.path) {
                return NSWorkspace.shared.icon(forFile: item.path)
            }

            let fileExtension = URL(fileURLWithPath: item.path).pathExtension
            if let contentType = UTType(filenameExtension: fileExtension) {
                return NSWorkspace.shared.icon(for: contentType)
            }
        }

        if item.kind == "Application",
           let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.path) {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return nil
    }
}

private extension CareLogCategory {
    var detailTitle: String {
        switch self {
        case .cleanup:
            "Cleanup"
        case .protection:
            "Protection"
        case .performance:
            "Performance Manager"
        case .applications:
            "Applications"
        case .myClutter:
            "My Clutter Manager"
        case .all:
            "After Cleaning Result Logs"
        }
    }

    var detailSubtitle: String {
        switch self {
        case .cleanup:
            "Browser junk, app caches, logs, temporary files, and developer cache files found on this Mac."
        case .protection:
            "Privacy traces and downloaded installer leftovers ready for review."
        case .performance:
            "Startup helpers that can affect login and background performance."
        case .applications:
            "Installed apps scanned for inventory and update review."
        case .myClutter:
            "Large files, downloads, and duplicate candidates found during scan."
        case .all:
            "Complete scan and cleaning results grouped by component."
        }
    }

    var detailSections: [String] {
        switch self {
        case .cleanup:
            ["Browser Caches", "Application Caches", "System Caches", "Logs", "Temporary Files", "Developer Junk", "Permissions"]
        case .protection:
            ["Privacy Traces", "Downloaded Installers", "Protection Review"]
        case .performance:
            ["Login Items", "Launch Agents", "Launch Daemons", "Background Helpers"]
        case .applications:
            ["Applications", "Update Candidates", "Recently Modified", "Inventory"]
        case .myClutter:
            ["Large & Old Files", "Duplicates", "Downloads", "Similar Names"]
        case .all:
            ["Cleanup", "Protection", "Performance", "Applications", "My Clutter"]
        }
    }

    var previewSymbol: String {
        switch self {
        case .cleanup:
            "face.smiling.inverse"
        case .protection:
            "shield.lefthalf.filled"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
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
