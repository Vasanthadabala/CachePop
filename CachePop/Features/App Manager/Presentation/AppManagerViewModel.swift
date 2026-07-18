import SwiftUI

@Observable
@MainActor
final class AppManagerViewModel {
    var applications: [ApplicationDetails] = []
    var isScanning: Bool = false
    
    var totalAppsFound: Int {
        applications.count
    }
    
    func scanApplications() {
        guard !isScanning else { return }
        isScanning = true
        
        Task {
            let apps = await AppUninstallerEngine.shared.scanApplications()
            
            await MainActor.run {
                self.applications = apps
                self.isScanning = false
            }
        }
    }
}
