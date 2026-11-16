import Foundation

nonisolated enum PhotoScope: String, CaseIterable, Identifiable, Sendable {
    case both, library, folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both:    "Photos library and folders"
        case .library: "Photos library"
        case .folders: "Pictures, Desktop, Downloads and Documents"
        }
    }

    var includesLibrary: Bool { self != .folders }
    var includesFolders: Bool { self != .library }
}
