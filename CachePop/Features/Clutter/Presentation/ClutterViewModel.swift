import SwiftUI
import AppKit

@Observable
@MainActor
final class ClutterViewModel {
    var phase: ClutterViewPhase = .welcome
    var selectedFolder = FileManager.default.homeDirectoryForCurrentUser
    var scannedResult: ClutterScanResult?
    var scanningPath = FileManager.default.homeDirectoryForCurrentUser.path
    var reviewTarget: ClutterReviewTarget = .all
    var duplicateSelectionsByGroupID: [String: Set<String>] = [:]

    private var scanTask: Task<Void, Never>?

    func startScan() {
        scanTask?.cancel()
        duplicateSelectionsByGroupID = [:]
        let folderToScan = selectedFolder
        scanningPath = sampleScanningPaths(in: folderToScan).first ?? folderToScan.path

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .scanning
        }

        scanTask = Task {
            let paths = sampleScanningPaths(in: folderToScan)
            let scanWork = Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanClutter(in: folderToScan)
            }

            for path in paths {
                if Task.isCancelled {
                    scanWork.cancel()
                    return
                }

                await MainActor.run {
                    scanningPath = path
                }

                try? await Task.sleep(for: .milliseconds(280))
            }

            let scan = await scanWork.value
            if Task.isCancelled { return }

            await MainActor.run {
                scannedResult = ClutterScanResult(details: scan.details, permissions: scan.permissions)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .summary
                }
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .welcome
        }
    }

    func resetToWelcome() {
        duplicateSelectionsByGroupID = [:]
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .welcome
        }
    }

    func reviewTarget(_ target: ClutterReviewTarget) {
        reviewTarget = target
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .manager
        }
    }

    func goBackToSummary() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .summary
        }
    }

    private func sampleScanningPaths(in folder: URL) -> [String] {
        let basePath = folder.path
        return [
            basePath,
            "\(basePath)/Downloads/archive-assets.zip",
            "\(basePath)/AndroidStudioProjects/.../components/CategoryComponent.kt",
            "\(basePath)/Pictures/IMG_2048.heic",
            "\(basePath)/Documents/export-final.mov",
            "\(basePath)/Desktop/old-installer.dmg"
        ]
    }

    func cancel() {
        scanTask?.cancel()
    }
}
