import SwiftUI

extension CareScanSnapshot {
    func withCleanupDetail(_ detail: String) -> CareScanSnapshot {
        var snapshot = self
        snapshot.currentDetail = detail
        return snapshot
    }
}
