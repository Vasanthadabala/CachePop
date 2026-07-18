import Foundation

extension CareScanSnapshot {
    func withDetail(_ detail: String) -> CareScanSnapshot {
        var snapshot = self
        snapshot.currentDetail = detail
        return snapshot
    }
}
