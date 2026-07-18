import Foundation

struct CleanupJunkSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbolName: String
    let isWide: Bool
    let isPrimary: Bool

    static func makeSummaries(from snapshot: CareScanSnapshot) -> [CleanupJunkSummary] {
        let systemItems = snapshot.cacheDetails.filter { item in
            item.kind == "Browser Cache"
                || item.kind == "App Cache"
                || item.kind == "System Cache"
                || item.kind == "Log File"
                || item.kind == "Temporary File"
                || item.kind == "Package Cache"
        }
        let developerItems = snapshot.cacheDetails.filter { $0.kind == "Developer Cache" }
        let trashItems = snapshot.cacheDetails.filter { $0.kind == "Trash Item" }

        let systemBytes = systemItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let developerBytes = developerItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let trashBytes = trashItems.reduce(Int64(0)) { $0 + $1.sizeBytes }

        let primaryTitle: String
        let primarySubtitle: String

        if systemBytes > 0 {
            primaryTitle = "\(format(systemBytes)) of System Junk Found"
            primarySubtitle = "Browser caches, application caches, logs, temporary files, and package caches ready for review."
        } else if snapshot.cacheItems > 0 {
            primaryTitle = "\(snapshot.formattedCacheSize) of Junk Found"
            primarySubtitle = "Review scanned junk categories before cleaning selected files."
        } else {
            primaryTitle = "Your Mac looks clean"
            primarySubtitle = "No removable cache, log, temporary, developer, or Trash items were found."
        }

        let secondary: CleanupJunkSummary
        if developerBytes > 0 {
            secondary = CleanupJunkSummary(
                id: "developer-junk",
                title: "\(format(developerBytes)) of Xcode Junk\nFound",
                subtitle: nil,
                symbolName: "hammer.fill",
                isWide: false,
                isPrimary: false
            )
        } else if trashBytes > 0 {
            secondary = CleanupJunkSummary(
                id: "trash-bins",
                title: "\(format(trashBytes)) in Trash Bins\nFound",
                subtitle: nil,
                symbolName: "trash.fill",
                isWide: false,
                isPrimary: false
            )
        } else {
            secondary = CleanupJunkSummary(
                id: "scan-coverage",
                title: "Browser, app, log,\nand Trash scan",
                subtitle: nil,
                symbolName: "checkmark.shield.fill",
                isWide: false,
                isPrimary: false
            )
        }

        return [
            CleanupJunkSummary(
                id: "system-junk",
                title: primaryTitle,
                subtitle: primarySubtitle,
                symbolName: snapshot.cacheItems > 0 ? "checkmark.circle.fill" : "checkmark.shield.fill",
                isWide: true,
                isPrimary: true
            ),
            secondary
        ]
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
