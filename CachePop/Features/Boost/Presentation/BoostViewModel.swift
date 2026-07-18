import SwiftUI

@Observable
@MainActor
final class BoostViewModel {
    var phase: PerformancePhase = .intro
    var scanProgress = 0.0
    var scanDetail = "Preparing performance scan..."
    var startupDetails: [CareScanDetailItem] = []
    var reviewSection: PerformanceSection?

    private var scanTask: Task<Void, Never>?

    var performanceSnapshot: CareScanSnapshot {
        var snapshot = CareScanSnapshot.empty
        snapshot.startupItems = startupDetails.count
        snapshot.startupDetails = startupDetails
        return snapshot
    }
    
    var currentPath: String {
        scanDetail
    }

    func showReview(_ section: PerformanceSection) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            reviewSection = section
        }
    }

    func hideReview() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            reviewSection = nil
        }
    }

    func startScan() {
        guard phase != .scanning else { return }
        scanTask?.cancel()
        scanProgress = 0
        scanDetail = "Preparing performance scan..."
        startupDetails = []

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .scanning
        }

        scanTask = Task {
            updateScan(progress: 0.12, detail: "Checking apps that open when you log in...")
            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            updateScan(progress: 0.42, detail: "Scanning third-party login items...")
            let result = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanStartupItems()
            }.value
            if Task.isCancelled { return }

            await MainActor.run {
                startupDetails = result.details
            }

            updateScan(progress: 0.72, detail: "Checking third-party background applications and processes...")
            try? await Task.sleep(for: .milliseconds(360))
            if Task.isCancelled { return }

            if let sample = result.details.first(where: { $0.kind == "Background Item" }) ?? result.details.first {
                updateScan(progress: 0.9, detail: sample.path)
            } else {
                updateScan(progress: 0.9, detail: "No third-party startup or background items found")
            }

            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            updateScan(progress: 1, detail: "Performance scan complete")

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .ready
                }
            }
        }
    }

    func resetScan() {
        scanTask?.cancel()
        scanTask = nil
        scanProgress = 0
        scanDetail = "Preparing performance scan..."
        startupDetails = []

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .intro
        }
    }

    private func updateScan(progress: Double, detail: String) {
        withAnimation(.linear(duration: 0.18)) {
            scanProgress = progress
            scanDetail = detail
        }
    }

    func cancel() {
        scanTask?.cancel()
    }
}
