import SwiftUI

struct CareLogDetail: Identifiable, Equatable {
    let id = UUID()
    let category: CareLogCategory
    let snapshot: CareScanSnapshot
    let cleaned: Bool
}
