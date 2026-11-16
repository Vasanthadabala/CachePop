import AppKit
import Foundation

/// Native process identity and termination stay behind a port. Retain only the displayed
/// process IDs, and release native app/icon objects when their client becomes inactive.
@MainActor
final class MacProcessApplicationController: ProcessApplicationControlling {
    private var applications: [Int32: NSRunningApplication?] = [:]

    private func application(pid: Int32) -> NSRunningApplication? {
        if let cached = applications[pid], cached?.isTerminated != true { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        applications[pid] = .some(app)
        return app
    }
    private func quittableApplication(pid: Int32) -> NSRunningApplication? {
        guard let app = application(pid: pid), app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }
    func canQuit(pid: Int32) -> Bool { quittableApplication(pid: pid) != nil }
    func quit(pid: Int32) { quittableApplication(pid: pid)?.terminate() }
    func retainDetails(for processIDs: Set<Int32>) {
        applications = applications.filter { processIDs.contains($0.key) && $0.value != nil }
    }
    func releaseDetails() { applications.removeAll(keepingCapacity: false) }
}
