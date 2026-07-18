import SwiftUI

enum MyClutterSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }
}

#Preview {
    ClutterView()
        .frame(width: 1180, height: 760)
}
