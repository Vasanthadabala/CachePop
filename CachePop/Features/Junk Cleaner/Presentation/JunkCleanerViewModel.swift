import SwiftUI

@Observable
@MainActor
final class JunkCleanerViewModel {
    var phase: CleanupPhase = .intro
    var scanProgress = 0.0
    var scanSnapshot = CareScanSnapshot.empty
    var currentPath: String {
        scanSnapshot.currentDetail
    }

    private var scanTask: Task<Void, Never>?

    func startScan() {
        guard phase != .scanning else { return }
        scanTask?.cancel()
        scanProgress = 0
        scanSnapshot = .empty

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .scanning
        }

        scanTask = Task {
            var snapshot = CareScanSnapshot.empty

            updateScan(progress: 0.06, snapshot: snapshot.withCleanupDetail("Preparing local junk scan..."))
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }

            updateScan(progress: 0.18, snapshot: snapshot.withCleanupDetail("Scanning Safari, Chrome, Firefox, Edge, Brave, Arc, and other browser caches."))
            let browserCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanBrowserCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += browserCacheResult.bytes
            snapshot.cacheItems += browserCacheResult.items
            snapshot.cacheDetails.append(contentsOf: browserCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: browserCacheResult.permissions)

            updateScan(progress: 0.46, snapshot: snapshot.withCleanupDetail("Scanning application caches, HTTP storage, WebKit data, saved states, and logs."))
            let appCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanApplicationCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += appCacheResult.bytes
            snapshot.cacheItems += appCacheResult.items
            snapshot.cacheDetails.append(contentsOf: appCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: appCacheResult.permissions)

            updateScan(progress: 0.74, snapshot: snapshot.withCleanupDetail("Scanning Trash Bins and removable junk candidates."))
            let trashResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanTrashItems()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += trashResult.bytes
            snapshot.cacheItems += trashResult.items
            snapshot.cacheDetails.append(contentsOf: trashResult.details)
            snapshot.permissionMessages.append(contentsOf: trashResult.permissions)

            updateScan(progress: 1, snapshot: snapshot.withCleanupDetail("Junk scan complete."))
            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .found
                }
            }
        }
    }

    func resetCleanup() {
        scanTask?.cancel()
        scanTask = nil
        scanProgress = 0
        scanSnapshot = .empty

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .intro
        }
    }

    func finishCleaning() {
        scanTask?.cancel()

        scanTask = Task {
            let pathsToClean = scanSnapshot.cacheDetails.map { $0.path }
            
            // For UI feedback during cleaning
            await MainActor.run {
                withAnimation(.linear(duration: 0.2)) {
                    scanSnapshot.currentDetail = "Cleaning junk files..."
                }
            }
            
            let result = await FileActionService.shared.moveToTrash(paths: pathsToClean)
            if Task.isCancelled { return }

            await MainActor.run {
                scanSnapshot.cacheBytes -= result.bytesFreed
                scanSnapshot.cacheItems -= result.itemsRemoved
                scanSnapshot.cacheDetails.removeAll()
                
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .complete
                }
            }
        }
    }

    private func updateScan(progress: Double, snapshot: CareScanSnapshot) {
        withAnimation(.linear(duration: 0.18)) {
            scanProgress = progress
            scanSnapshot = snapshot
        }
    }

    func cancel() {
        scanTask?.cancel()
    }
}
