import Foundation

nonisolated enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case videos, diskImages, archives, audio, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videos:     "Videos"
        case .diskImages: "Disk images & installers"
        case .archives:   "Archives"
        case .audio:      "Audio"
        case .other:      "Other"
        }
    }

}
