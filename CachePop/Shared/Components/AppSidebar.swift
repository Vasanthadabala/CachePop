import SwiftUI

/// The sidebar: the app's identity, the four sections grouped by what they do, a live status
/// line for each, and the disk's free space always in view.
struct AppSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrand()
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 14)

            SidebarGroupLabel("Clean")
            VStack(spacing: 2) {
                row(.cleanUp)
                row(.largeFiles)
                row(.photos)
            }

            SidebarGroupLabel("Monitor")
                .padding(.top, 14)
            VStack(spacing: 2) {
                row(.systemMonitor)
                row(.diskUsage)
            }

            SidebarGroupLabel("Manage")
                .padding(.top, 14)
            VStack(spacing: 2) {
                row(.apps)
                row(.loginItems)
            }

            Spacer(minLength: AppTheme.Spacing.m)

            SidebarFooter(
                disk: model.disk,
                isLow: model.isLowOnSpace,
                isSettingsSelected: model.section == .settings,
                onOpenDiskUsage: { withAnimation(AppTheme.Motion.standard) { model.section = .diskUsage } },
                onOpenSettings: { withAnimation(AppTheme.Motion.standard) { model.section = .settings } }
            )
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.sidebar.ignoresSafeArea())
        // A hairline down the edge, like the one under the page bar: sidebar and page are both white.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.Colors.separator)
                .frame(width: 1)
                .ignoresSafeArea()
        }
        // A fixed width: the split view otherwise gives detail screens with wide content
        // part of the sidebar, which cut off its labels.
        .navigationSplitViewColumnWidth(232)
    }

    // ⌘1–⌘5 live in the View menu (AppCommands), so they work from anywhere.
    private func row(_ section: AppSection) -> some View {
        SidebarSectionRow(model: model, section: section)
    }
}

/// One section's row. It reads its own status, so a live change in one section (a monitor
/// sample every two seconds, a folder measured, app sizes landing) redraws that row only,
/// not the whole sidebar.
private struct SidebarSectionRow: View {
    let model: AppModel
    let section: AppSection

    var body: some View {
        SidebarRow(
            section: section,
            status: model.sidebarStatus(for: section),
            isSelected: (model.section ?? .cleanUp) == section
        ) {
            withAnimation(AppTheme.Motion.standard) { model.section = section }
        }
    }
}

// MARK: - Brand

private struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            BrandMark(height: 26)
                .frame(width: 21)
            VStack(alignment: .leading, spacing: 0) {
                Text("CachePop")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Free up space on your Mac")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}

private struct SidebarGroupLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Rows

/// What a sidebar row says about its section right now.
struct SidebarStatus: Equatable {
    var subtitle: String
    /// A short figure worth acting on, e.g. "8.07 GB".
    var badge: String?
    var isBusy = false
}

private struct SidebarRow: View {
    let section: AppSection
    let status: SidebarStatus
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // Each section keeps its colour so it's easy to find; the open one is the
                // grey row.
                IconTile(symbolName: section.symbolName, size: 26, hue: section.hue)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(status.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                if status.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else if let badge = status.badge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        // Something to review: the section's colour, softly.
                        .foregroundStyle(section.hue.solid)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(section.hue.wash))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background { background }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Motion.quick) { isHovered = hovering }
        }
        .animation(AppTheme.Motion.standard, value: status)
        .accessibilityLabel("\(section.title), \(status.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if isSelected {
            // The card grey on the sidebar, flat like the cards.
            shape.fill(AppTheme.Colors.sidebarSelection)
        } else if isHovered {
            shape.fill(AppTheme.Colors.hover)
        }
    }
}

// MARK: - Footer

/// The sidebar's footer: Settings and the startup disk, each on its own card.
private struct SidebarFooter: View {
    let disk: DiskInfo
    let isLow: Bool
    let isSettingsSelected: Bool
    let onOpenDiskUsage: () -> Void
    let onOpenSettings: () -> Void

    private static let radius: CGFloat = 12

    var body: some View {
        VStack(spacing: 6) {
            settingsCard
            diskCard
        }
    }

    /// Opens Settings in the detail area.
    private var settingsCard: some View {
        FooterButton(help: "Open Settings", action: onOpenSettings) { _ in
            HStack(spacing: 9) {
                IconTile(symbolName: "gearshape", size: 24, hue: AppSection.settings.hue)
                Text("Settings")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer(minLength: 4)
                KeyCap(text: "⌘ ,")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .card(radius: Self.radius)
        .accessibilityAddTraits(isSettingsSelected ? .isSelected : [])
    }

    /// The startup disk's free space. Opens Disk Usage.
    private var diskCard: some View {
        FooterButton(help: "See what's using space") {
            onOpenDiskUsage()
        } label: { isHovered in
            DiskSummary(disk: disk, isLow: isLow, showsChevron: isHovered)
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .card(radius: Self.radius)
    }
}

/// A full-width button inside the footer card, with a hover wash.
private struct FooterButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: (Bool) -> Label

    var body: some View {
        Button(action: action) {
            FooterRowLabel(content: label)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Tracks the pointer and draws the hover wash behind a footer row.
private struct FooterRowLabel<Content: View>: View {
    let content: (Bool) -> Content
    @State private var isHovered = false

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? AppTheme.Colors.hover : .clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(AppTheme.Motion.quick) { isHovered = hovering }
            }
    }
}

/// A small keyboard shortcut, drawn like a key.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(AppTheme.Colors.separator, lineWidth: 1)
            )
    }
}

// MARK: - Disk

/// Free space on the startup disk: name, free space, how full it is, and used of total.
struct DiskSummary: View {
    let disk: DiskInfo
    var isLow = false
    var showsChevron = false

    private var hasReading: Bool { disk.totalBytes > 0 }
    private var warn: Bool { isLow || disk.isLow }
    private var percent: Int { Int((disk.usedFraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                IconTile(symbolName: "internaldrive", size: 24, tone: .warning, hue: warn ? nil : AppTheme.Palette.graphite)
                    .overlay(alignment: .topTrailing) {
                        if warn {
                            Circle()
                                .fill(AppTheme.Status.warning)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Macintosh HD")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(hasReading ? "\(ByteSize.string(disk.availableBytes)) free" : "Reading…")
                        .font(.system(size: 11))
                        .foregroundStyle(warn ? AppTheme.Status.warning : AppTheme.Colors.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .opacity(showsChevron ? 1 : 0)
            }

            UsageBar(fraction: hasReading ? disk.usedFraction : 0, color: warn ? AppTheme.Status.warning : AppTheme.Colors.accent)

            HStack(spacing: 4) {
                Text(hasReading ? "\(ByteSize.string(disk.usedBytes)) of \(ByteSize.string(disk.totalBytes)) used" : " ")
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if hasReading {
                    Text(warn ? "\(percent)% · low" : "\(percent)%")
                        .fontWeight(.semibold)
                        .foregroundStyle(warn ? AppTheme.Status.warning : AppTheme.Colors.textSecondary)
                }
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasReading
            ? "Macintosh HD, \(ByteSize.string(disk.availableBytes)) free of \(ByteSize.string(disk.totalBytes)), \(percent) percent used"
            : "Macintosh HD, reading")
    }
}

/// A slim rounded bar: a soft track and a solid fill.
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.Colors.track)
                Capsule()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(proxy.size.width * fraction, 6) : 0)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.6), value: fraction)
    }
}

/// The disk on its own, as a card (menu bar panel).
struct DiskSpaceCard: View {
    let disk: DiskInfo
    var isLow = false

    var body: some View {
        DiskSummary(disk: disk, isLow: isLow)
            .padding(10)
            .card(radius: 12)
    }
}

// MARK: - Status

extension AppModel {
    func sidebarStatus(for section: AppSection) -> SidebarStatus {
        switch section {
        case .cleanUp:
            switch cleanUp.phase {
            case .start:
                return SidebarStatus(subtitle: "Caches & developer junk")
            case .scanning:
                return SidebarStatus(subtitle: "Scanning…", isBusy: true)
            case .review:
                let found = cleanUp.result.reclaimableBytes
                return SidebarStatus(subtitle: found > 0 ? "To review" : "Nothing to clean",
                                     badge: found > 0 ? ByteSize.string(found) : nil)
            case .cleaning:
                return SidebarStatus(subtitle: "Cleaning…", isBusy: true)
            case .done:
                let freed = cleanUp.report.map { $0.measuredFreedBytes ?? $0.estimatedFreedBytes } ?? 0
                return SidebarStatus(subtitle: "Freed \(ByteSize.string(freed))")
            }

        case .largeFiles:
            switch largeFiles.phase {
            case .start:
                return SidebarStatus(subtitle: "Big files & duplicates")
            case .scanning:
                return SidebarStatus(subtitle: "Scanning…", isBusy: true)
            case .results:
                let total = largeFiles.result.largeBytes + largeFiles.result.duplicateExtraBytes
                return SidebarStatus(subtitle: total > 0 ? "To review" : "Nothing large found",
                                     badge: total > 0 ? ByteSize.string(total) : nil)
            }

        case .photos:
            switch photos.phase {
            case .start:
                return SidebarStatus(subtitle: "Similar & blurry shots")
            case .scanning:
                return SidebarStatus(subtitle: "Checking photos…", isBusy: true)
            case .results:
                let count = photos.result.reviewCount
                return SidebarStatus(subtitle: count > 0 ? "\(count) to review" : "Nothing to review")
            }

        case .systemMonitor:
            return SidebarStatus(subtitle: monitor.sidebarSummary ?? "CPU, memory & heat",
                                 badge: monitor.isHot ? monitor.thermalTitle : nil)

        case .diskUsage:
            switch diskUsage.phase {
            case .start:
                return SidebarStatus(subtitle: "What's taking up space")
            case .measuring:
                return SidebarStatus(subtitle: "Measuring…", isBusy: true)
            case .ready:
                let largest = diskUsage.overviewEntries.max { ($0.bytes ?? 0) < ($1.bytes ?? 0) }
                return SidebarStatus(subtitle: largest.map { "Largest: \($0.name)" } ?? "Measured")
            }

        case .apps:
            if apps.isScanning && !apps.hasScanned {
                return SidebarStatus(subtitle: "Measuring apps…", isBusy: true)
            }
            guard apps.hasScanned else { return SidebarStatus(subtitle: "Uninstall completely") }
            return SidebarStatus(subtitle: "\(apps.applications.count) apps · \(ByteSize.string(apps.totalSizeBytes))")

        case .loginItems:
            if loginItems.isScanning && !loginItems.hasScanned {
                return SidebarStatus(subtitle: "Checking…", isBusy: true)
            }
            guard loginItems.hasScanned else { return SidebarStatus(subtitle: "What starts at login") }
            let count = loginItems.onCount
            return SidebarStatus(subtitle: count == 0 ? "Nothing extra" : "\(count) \(count == 1 ? "item" : "items") start on their own")

        case .settings:
            return SidebarStatus(subtitle: "")
        }
    }
}
