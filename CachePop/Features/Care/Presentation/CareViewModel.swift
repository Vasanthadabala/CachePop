import SwiftUI

@Observable
@MainActor
final class CareViewModel {
    var selectedItem: CareSidebarItem = .smartCare
    var scanPhase: ScanPhase = .idle
    var scanProgress = 0.0
    var cleaningProgress = 0.0
    var scanSnapshot = CareScanSnapshot.empty
    var activeDetail: CareLogDetail?
    
    private var scanTask: Task<Void, Never>?
    
    func startScan() {
        guard scanPhase != .scanning else { return }

        scanTask?.cancel()
        scanProgress = 0
        cleaningProgress = 0
        scanSnapshot = .empty

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            scanPhase = .scanning
        }

        scanTask = Task {
            var snapshot = CareScanSnapshot.empty

            updateScan(progress: 0.04, snapshot: snapshot.withDetail("Preparing local scan..."))
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }

            updateScan(progress: 0.10, snapshot: snapshot.withDetail("Scanning browser junk caches."))
            let browserCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanBrowserCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += browserCacheResult.bytes
            snapshot.cacheItems += browserCacheResult.items
            snapshot.cacheDetails.append(contentsOf: browserCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: browserCacheResult.permissions)
            updateScan(progress: 0.22, snapshot: snapshot.withDetail("Scanning app, system, log, temp, and developer junk."))
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled { return }

            let appCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanApplicationCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += appCacheResult.bytes
            snapshot.cacheItems += appCacheResult.items
            snapshot.cacheDetails.append(contentsOf: appCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: appCacheResult.permissions)
            let trashResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanTrashItems()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += trashResult.bytes
            snapshot.cacheItems += trashResult.items
            snapshot.cacheDetails.append(contentsOf: trashResult.details)
            snapshot.permissionMessages.append(contentsOf: trashResult.permissions)
            updateScan(progress: 0.38, snapshot: snapshot.withDetail("Finished browser and app junk scan."))
            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            updateScan(progress: 0.44, snapshot: snapshot.withDetail("Checking privacy traces and downloaded installer leftovers."))
            let protectionResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanProtectionItems()
            }.value
            if Task.isCancelled { return }
            snapshot.protectionItems = protectionResult.count
            snapshot.protectionDetails = protectionResult.details
            snapshot.permissionMessages.append(contentsOf: protectionResult.permissions)
            updateScan(progress: 0.55, snapshot: snapshot.withDetail("Finished protection checks."))
            try? await Task.sleep(for: .milliseconds(160))
            if Task.isCancelled { return }

            updateScan(progress: 0.61, snapshot: snapshot.withDetail("Scanning startup items and background helpers."))
            let startupResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanStartupItems()
            }.value
            if Task.isCancelled { return }
            snapshot.startupItems = startupResult.count
            snapshot.startupDetails = startupResult.details
            snapshot.permissionMessages.append(contentsOf: startupResult.permissions)
            updateScan(progress: 0.70, snapshot: snapshot.withDetail("Finished performance scan."))
            try? await Task.sleep(for: .milliseconds(160))
            if Task.isCancelled { return }

            updateScan(progress: 0.76, snapshot: snapshot.withDetail("Checking installed applications."))
            let appResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanApplications()
            }.value
            if Task.isCancelled { return }
            snapshot.appsChecked = appResult.count
            snapshot.appDetails = appResult.details
            snapshot.permissionMessages.append(contentsOf: appResult.permissions)
            updateScan(progress: 0.84, snapshot: snapshot.withDetail("Finished applications scan."))
            try? await Task.sleep(for: .milliseconds(160))
            if Task.isCancelled { return }

            updateScan(progress: 0.89, snapshot: snapshot.withDetail("Scanning large files and duplicate candidates."))
            let clutterResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanClutter()
            }.value
            if Task.isCancelled { return }
            snapshot.largeFiles = clutterResult.largeFiles
            snapshot.duplicateFiles = clutterResult.duplicateFiles
            snapshot.clutterDetails = clutterResult.details
            snapshot.permissionMessages.append(contentsOf: clutterResult.permissions)
            updateScan(progress: 1, snapshot: snapshot.withDetail("Finished comparing large files and duplicates."))

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    scanPhase = snapshot.hasFindings ? .readyToRun : .complete
                }
            }
        }
    }

    func runReadyTasks() {
        scanTask?.cancel()
        cleaningProgress = 0

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            selectedItem = .smartCare
            scanPhase = .cleaning
        }

        scanTask = Task {
            let pathsToClean = scanSnapshot.cacheDetails.map { $0.path }
            
            await MainActor.run {
                withAnimation(.linear(duration: 0.2)) {
                    cleaningProgress = 0.2
                    scanSnapshot.currentDetail = "Cleaning browser and application cache selections..."
                }
            }
            
            let result = await FileActionService.shared.moveToTrash(paths: pathsToClean)
            if Task.isCancelled { return }
            
            await MainActor.run {
                withAnimation(.linear(duration: 0.2)) {
                    cleaningProgress = 0.6
                    scanSnapshot.currentDetail = "Applying protection review selections..."
                }
            }
            
            let protectionPaths = scanSnapshot.protectionDetails.map { $0.path }
            let protectionResult = await FileActionService.shared.moveToTrash(paths: protectionPaths)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.linear(duration: 0.2)) {
                    cleaningProgress = 1.0
                    scanSnapshot.currentDetail = "Writing after-cleaning result logs..."
                }
            }

            // Update the snapshot to reflect cleaned items
            await MainActor.run {
                scanSnapshot.cacheBytes -= result.bytesFreed
                scanSnapshot.cacheItems -= result.itemsRemoved
                scanSnapshot.cacheDetails.removeAll()
                
                scanSnapshot.protectionItems -= protectionResult.itemsRemoved
                scanSnapshot.protectionDetails.removeAll()
                
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    scanPhase = .complete
                }
            }
        }
    }

    func resetScan() {
        scanTask?.cancel()
        scanTask = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            scanProgress = 0
            cleaningProgress = 0
            activeDetail = nil
            scanPhase = .idle
            selectedItem = .smartCare
        }
    }
    
    func hideActiveDetail() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            self.activeDetail = nil
        }
    }

    func showLog(_ category: CareLogCategory, cleaned: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            activeDetail = CareLogDetail(
                category: category,
                snapshot: scanSnapshot,
                cleaned: cleaned
            )
        }
    }
    
    func selectSidebarItem(_ item: CareSidebarItem) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            selectedItem = item
        }
    }

    private func updateScan(progress: Double, snapshot: CareScanSnapshot) {
        withAnimation(.linear(duration: 0.16)) {
            scanProgress = progress
            scanSnapshot = snapshot
        }
    }
    
    func cancel() {
        scanTask?.cancel()
    }
}
