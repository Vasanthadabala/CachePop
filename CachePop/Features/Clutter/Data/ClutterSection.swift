import Foundation

enum ClutterSection: String, CaseIterable, Identifiable {
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
            "Files above 100 MB found in the scanned folder."
        case .duplicates:
            "Identical files found inside the scanned folder by comparing file contents."
        }
    }

    var emptyMessage: String {
        switch self {
        case .largeFiles:
            "No files above 100 MB were found in this folder."
        case .duplicates:
            "No identical duplicate files were found in this folder."
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
