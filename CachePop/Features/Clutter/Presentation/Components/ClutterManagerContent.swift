import SwiftUI

struct ClutterManagerContent: View {
    let onBack: () -> Void
    let snapshot: CareScanSnapshot?
    private let result: ClutterScanResult?
    private let reviewTarget: ClutterReviewTarget
    @Binding private var duplicateSelectionsByGroupID: [String: Set<String>]

    init(onBack: @escaping () -> Void = {}, snapshot: CareScanSnapshot? = nil) {
        self.onBack = onBack
        self.snapshot = snapshot
        self.result = nil
        self.reviewTarget = .all
        self._duplicateSelectionsByGroupID = .constant([:])
    }

    init(
        onBack: @escaping () -> Void = {},
        result: ClutterScanResult?,
        reviewTarget: ClutterReviewTarget = .all,
        duplicateSelectionsByGroupID: Binding<[String: Set<String>]> = .constant([:])
    ) {
        self.onBack = onBack
        self.snapshot = nil
        self.result = result
        self.reviewTarget = reviewTarget
        self._duplicateSelectionsByGroupID = duplicateSelectionsByGroupID
    }

    var body: some View {
        MyClutterManager(
            onBack: onBack,
            initialResult: (result ?? snapshot.map {
                ClutterScanResult(
                    details: $0.clutterDetails,
                    permissions: $0.permissionMessages
                )
            })?.filtered(for: reviewTarget),
            initialReviewTarget: reviewTarget,
            duplicateSelectionsByGroupID: $duplicateSelectionsByGroupID
        )
    }
}
