import Foundation

/// Something the user told CachePop never to clean: a folder, or one item from a scan.
struct NeverCleanEntry: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case folder, item }

    let kind: Kind
    /// A folder path, or an item ID such as "general.appCaches".
    let value: String
    /// What to show in Settings: the folder's path or the item's title.
    let title: String

    var id: String { "\(kind.rawValue):\(value)" }
}


/// When to untick data that has to be downloaded again.
enum RedownloadThreshold: Int, CaseIterable, Identifiable {
    case mb50 = 50, mb100 = 100, mb250 = 250, mb500 = 500, gb1 = 1000, never = 0

    var id: Int { rawValue }
    var bytes: Int64? { self == .never ? nil : Int64(rawValue) * 1_000_000 }
    var title: String {
        switch self {
        case .never: "Never — keep them ticked"
        case .gb1:   "Over 1 GB"
        default:     "Over \(rawValue) MB"
        }
    }
}


/// When to warn that the disk is nearly full.
enum LowSpaceThreshold: Int, CaseIterable, Identifiable {
    case tenPercent = 0, gb5 = 5, gb10 = 10, gb20 = 20, gb50 = 50

    var id: Int { rawValue }
    var title: String {
        self == .tenPercent ? "Under 10% of the disk" : "Under \(rawValue) GB"
    }

    func bytes(totalBytes: Int64) -> Int64 {
        self == .tenPercent ? totalBytes / 10 : Int64(rawValue) * 1_000_000_000
    }
}
