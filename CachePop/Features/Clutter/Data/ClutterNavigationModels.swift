import SwiftUI

enum ClutterViewPhase {
    case welcome
    case scanning
    case summary
    case manager
}

enum ClutterReviewTarget {
    case all
    case duplicatePhotos
    case duplicateOtherFiles
    case largeFiles

    var initialSection: ClutterSection {
        switch self {
        case .all, .largeFiles:
            .largeFiles
        case .duplicatePhotos, .duplicateOtherFiles:
            .duplicates
        }
    }
}
