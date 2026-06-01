import AppKit
import SwiftUI

struct ResultCardBadge: View {
    let result: ScanResult

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: result.badgeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(result.badgeRotation))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 8)

            Image(systemName: result.symbolName)
                .font(.system(size: 48, weight: .heavy))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.9))
        }
    }
}


struct ScanResult: Identifiable {
    let id = UUID()
    let category: CareLogCategory
    let title: String
    let value: String
    let status: String
    let symbolName: String
    let backgroundColors: [Color]
    let badgeColors: [Color]
    let badgeRotation: Double
    let isWide: Bool

    static let topResults: [ScanResult] = [
        ScanResult(
            category: .cleanup,
            title: "Cleanup",
            value: "40,9 GB of junk",
            status: "Cleaned",
            symbolName: "face.smiling.inverse",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0xA8BAFF),
                Color(hex: 0x3D28BF)
            ],
            badgeRotation: -8,
            isWide: false
        ),
        ScanResult(
            category: .protection,
            title: "Protection",
            value: "0 risks",
            status: "Reviewed",
            symbolName: "shield.lefthalf.filled",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0xB5C4FF),
                Color(hex: 0x3441C4)
            ],
            badgeRotation: 7,
            isWide: false
        ),
        ScanResult(
            category: .performance,
            title: "Performance",
            value: "1 task",
            status: "Done",
            symbolName: "bolt.fill",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0xB9C8FF),
                Color(hex: 0x4D31D8)
            ],
            badgeRotation: 8,
            isWide: false
        )
    ]

    static let bottomResults: [ScanResult] = [
        ScanResult(
            category: .applications,
            title: "Applications",
            value: "6 vital updates",
            status: "Started",
            symbolName: "shippingbox.fill",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0x91ADFF),
                Color(hex: 0x2D35B8)
            ],
            badgeRotation: -10,
            isWide: true
        ),
        ScanResult(
            category: .myClutter,
            title: "My Clutter",
            value: "283 duplicate downloads",
            status: "Removed",
            symbolName: "folder.fill",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0x8EA8FF),
                Color(hex: 0x2A26A8)
            ],
            badgeRotation: 8,
            isWide: true
        )
    ]
}

struct ScanReadyResult: Identifiable {
    let id = UUID()
    let category: CareLogCategory
    let title: String
    let value: String
    let status: String
    let symbolName: String
    let backgroundColors: [Color]
    let badgeColors: [Color]
    let badgeRotation: Double
    let isWide: Bool
    let isSelected: Bool
    let showsReview: Bool

    static let topResults: [ScanReadyResult] = [
        ScanReadyResult(
            category: .cleanup,
            title: "Cleanup",
            value: "12.6 GB of junk",
            status: "to clean",
            symbolName: "face.smiling.inverse",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0xA8BAFF),
                Color(hex: 0x3D28BF)
            ],
            badgeRotation: -10,
            isWide: false,
            isSelected: true,
            showsReview: true
        ),
        ScanReadyResult(
            category: .protection,
            title: "Protection",
            value: "0 risks",
            status: "to review",
            symbolName: "shield.lefthalf.filled",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0xB5C4FF),
                Color(hex: 0x3441C4)
            ],
            badgeRotation: 7,
            isWide: false,
            isSelected: false,
            showsReview: true
        ),
        ScanReadyResult(
            category: .performance,
            title: "Performance",
            value: "4 items",
            status: "to review",
            symbolName: "bolt.fill",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0xB9C8FF),
                Color(hex: 0x4D31D8)
            ],
            badgeRotation: 8,
            isWide: false,
            isSelected: false,
            showsReview: true
        )
    ]

    static let bottomResults: [ScanReadyResult] = [
        ScanReadyResult(
            category: .applications,
            title: "Applications",
            value: "No vital updates",
            status: "to install",
            symbolName: "shippingbox.fill",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0x91ADFF),
                Color(hex: 0x2D35B8)
            ],
            badgeRotation: -10,
            isWide: true,
            isSelected: false,
            showsReview: true
        ),
        ScanReadyResult(
            category: .myClutter,
            title: "My Clutter",
            value: "3 duplicate downloads",
            status: "to remove",
            symbolName: "folder.fill",
            backgroundColors: AppTheme.Care.cardGradient,
            badgeColors: [
                Color(hex: 0x8EA8FF),
                Color(hex: 0x2A26A8)
            ],
            badgeRotation: 8,
            isWide: true,
            isSelected: true,
            showsReview: true
        )
    ]
}

enum ScanPhase {
    case idle
    case scanning
    case readyToRun
    case cleaning
    case complete
}

struct CareScanSnapshot: Equatable {
    var cacheBytes: Int64 = 0
    var cacheItems: Int = 0
    var protectionItems: Int = 0
    var startupItems: Int = 0
    var appsChecked: Int = 0
    var largeFiles: Int = 0
    var duplicateFiles: Int = 0
    var currentDetail = "Preparing scan..."
    var cacheDetails: [CareScanDetailItem] = []
    var protectionDetails: [CareScanDetailItem] = []
    var startupDetails: [CareScanDetailItem] = []
    var appDetails: [CareScanDetailItem] = []
    var clutterDetails: [CareScanDetailItem] = []
    var permissionMessages: [String] = []

    static let empty = CareScanSnapshot()

    var formattedCacheSize: String {
        let gigabytes = Double(cacheBytes) / 1_073_741_824

        if gigabytes >= 0.1 {
            return "\(String(format: "%.1f", gigabytes)) GB"
        }

        let megabytes = Double(cacheBytes) / 1_048_576
        return "\(max(Int(megabytes.rounded()), 0)) MB"
    }

    var startupSummary: String {
        "\(startupItems) items"
    }

    var protectionSummary: String {
        protectionItems == 1 ? "1 item" : "\(protectionItems) items"
    }

    var appSummary: String {
        "\(appsChecked) apps"
    }

    var clutterSummary: String {
        "\(largeFiles + duplicateFiles) files"
    }

    var hasFindings: Bool {
        cacheItems > 0 || protectionItems > 0 || startupItems > 0 || largeFiles > 0 || duplicateFiles > 0
    }

    func detailItems(for category: CareLogCategory) -> [CareScanDetailItem] {
        switch category {
        case .cleanup:
            cacheDetails
        case .protection:
            protectionDetails
        case .performance:
            startupDetails
        case .applications:
            appDetails
        case .myClutter:
            clutterDetails
        case .all:
            cacheDetails + protectionDetails + startupDetails + appDetails + clutterDetails
        }
    }
}

struct CareScanDetailItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let path: String
    let sizeBytes: Int64
    let kind: String
    let modified: Date?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var modifiedText: String {
        modified?.formatted(date: .abbreviated, time: .omitted) ?? "Not available"
    }
}

enum CareLogCategory: String, CaseIterable, Identifiable {
    case cleanup
    case protection
    case performance
    case applications
    case myClutter
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanup:
            "Cleanup Logs"
        case .protection:
            "Protection Logs"
        case .performance:
            "Performance Logs"
        case .applications:
            "Applications Logs"
        case .myClutter:
            "My Clutter Logs"
        case .all:
            "Result Logs"
        }
    }

    var label: String {
        switch self {
        case .cleanup:
            "Cleanup"
        case .protection:
            "Protection"
        case .performance:
            "Performance"
        case .applications:
            "Applications"
        case .myClutter:
            "My Clutter"
        case .all:
            "All Logs"
        }
    }

    func lines(snapshot: CareScanSnapshot, cleaned: Bool) -> [String] {
        let cleaningState = cleaned ? "Cleaned" : "Ready"

        switch self {
        case .cleanup:
            return [
                "Browser junk scanned: Safari, Chrome, Edge, Firefox, Brave, Opera, Vivaldi, and Arc.",
                "Deep junk folders scanned: app caches, system caches, logs, temp files, Xcode caches, simulator caches, and package manager caches.",
                "Junk files found: \(snapshot.cacheItems).",
                "Recoverable junk size: \(snapshot.formattedCacheSize).",
                "Status: \(cleaningState)."
            ]
        case .protection:
            return [
                "Protection checks scanned: browser privacy traces and downloaded installer leftovers.",
                "Review items found: \(snapshot.protectionItems).",
                "CachePop uses local safety heuristics; it does not replace a dedicated malware engine.",
                "Status: \(cleaningState)."
            ]
        case .performance:
            return [
                "Startup locations scanned: user LaunchAgents, system LaunchAgents, system LaunchDaemons.",
                "Startup items found: \(snapshot.startupItems).",
                "Performance-impacting helpers are ready for review.",
                "Status: \(cleaningState)."
            ]
        case .applications:
            return [
                "Application folders scanned: /Applications and ~/Applications.",
                "Installed apps checked: \(snapshot.appsChecked).",
                "Update check prepared for installed application inventory.",
                "Status: \(cleaningState)."
            ]
        case .myClutter:
            return [
                "Locations scanned: Downloads, Desktop, Documents, Pictures, Movies, Music, and Public.",
                "Large files found: \(snapshot.largeFiles).",
                "Duplicate file candidates found: \(snapshot.duplicateFiles).",
                "Total clutter candidates: \(snapshot.largeFiles + snapshot.duplicateFiles).",
                "Status: \(cleaningState)."
            ]
        case .all:
            return CareLogCategory.allCases
                .filter { $0 != .all }
                .flatMap { category in
                    ["\(category.label):"] + category.lines(snapshot: snapshot, cleaned: cleaned).map { "  \($0)" }
                }
        }
    }
}

struct CareLogDetail: Identifiable, Equatable {
    let id = UUID()
    let category: CareLogCategory
    let snapshot: CareScanSnapshot
    let cleaned: Bool
}
