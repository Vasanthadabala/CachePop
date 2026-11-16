import AppKit
import Foundation

extension ApplicationDetails {
    /// Running copies of this very bundle. Another copy with the same identifier (Xcode next to
    /// Xcode-beta) doesn't count, so uninstalling one never quits or waits for the other.
    var runningInstances: [NSRunningApplication] {
        guard !bundleIdentifier.isEmpty else { return [] }
        let bundlePath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { instance in
            // No location, an iPhone app run from inside its wrapper, or a quarantined copy
            // macOS runs from a temporary mount: count it.
            guard let url = instance.bundleURL else { return true }
            let runningPath = url.resolvingSymlinksInPath().path
            return runningPath == bundlePath || runningPath.hasPrefix(bundlePath + "/")
                || runningPath.contains("/AppTranslocation/")
        }
    }

    var isRunning: Bool { !runningInstances.isEmpty }

}
