import Foundation
import AppKit

struct ApplicationDetails: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let bundleIdentifier: String
    let icon: NSImage?
    let version: String
    let sizeBytes: Int64
    let lastUsedDate: Date?
    var relatedFiles: [ApplicationRelatedFile] = []
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct ApplicationRelatedFile: Identifiable {
    let id = UUID()
    let path: String
    let sizeBytes: Int64
    let category: String // e.g., "Preferences", "Caches", "Application Support"
}

final class AppUninstallerEngine: Sendable {
    static let shared = AppUninstallerEngine()
    
    private init() {}
    
    func scanApplications() async -> [ApplicationDetails] {
        // Run the scan off the main thread
        await Task.detached(priority: .userInitiated) {
            var apps: [ApplicationDetails] = []
            let fileManager = FileManager.default
            let appDirectories = [
                "/Applications",
                "\(NSHomeDirectory())/Applications"
            ]
            
            for directory in appDirectories {
                guard let enumerator = fileManager.enumerator(atPath: directory) else { continue }
                
                while let relativePath = enumerator.nextObject() as? String {
                    // Only looking for .app bundles at the top level
                    if relativePath.hasSuffix(".app") {
                        enumerator.skipDescendants()
                        let fullPath = "\(directory)/\(relativePath)"
                        if let appDetails = self.extractAppDetails(at: fullPath) {
                            apps.append(appDetails)
                        }
                    }
                }
            }
            return apps.sorted { $0.sizeBytes > $1.sizeBytes }
        }.value
    }
    
    private func extractAppDetails(at path: String) -> ApplicationDetails? {
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url),
              let infoDictionary = bundle.infoDictionary else {
            return nil
        }
        
        let name = (infoDictionary["CFBundleDisplayName"] as? String) ??
                   (infoDictionary["CFBundleName"] as? String) ??
                   url.deletingPathExtension().lastPathComponent
        
        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        let version = (infoDictionary["CFBundleShortVersionString"] as? String) ?? "Unknown"
        
        // Size
        var sizeBytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
                   let allocatedSize = values.totalFileAllocatedSize {
                    sizeBytes += Int64(allocatedSize)
                }
            }
        }
        
        // Last used date (fallback to modification date)
        var lastUsedDate: Date? = nil
        if let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey]) {
            lastUsedDate = values.contentAccessDate ?? values.contentModificationDate
        }
        
        // Icon
        let workspace = NSWorkspace.shared
        let icon = workspace.icon(forFile: path)
        
        return ApplicationDetails(
            name: name,
            path: path,
            bundleIdentifier: bundleIdentifier,
            icon: icon,
            version: version,
            sizeBytes: sizeBytes,
            lastUsedDate: lastUsedDate
        )
    }
    
    func findRelatedFiles(for app: ApplicationDetails) async -> [ApplicationRelatedFile] {
        await Task.detached(priority: .userInitiated) {
            guard !app.bundleIdentifier.isEmpty else { return [] }
            
            let fileManager = FileManager.default
            let home = NSHomeDirectory()
            var relatedFiles: [ApplicationRelatedFile] = []
            
            let searchPaths: [(String, String)] = [
                ("\(home)/Library/Application Support/\(app.name)", "Application Support"),
                ("\(home)/Library/Application Support/\(app.bundleIdentifier)", "Application Support"),
                ("\(home)/Library/Caches/\(app.bundleIdentifier)", "Caches"),
                ("\(home)/Library/Preferences/\(app.bundleIdentifier).plist", "Preferences"),
                ("\(home)/Library/Saved Application State/\(app.bundleIdentifier).savedState", "Saved State"),
                ("\(home)/Library/Containers/\(app.bundleIdentifier)", "Containers"),
                ("\(home)/Library/Group Containers/\(app.bundleIdentifier)", "Group Containers"),
                ("\(home)/Library/Logs/\(app.name)", "Logs"),
                ("\(home)/Library/Logs/\(app.bundleIdentifier)", "Logs")
            ]
            
            for (path, category) in searchPaths {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: path, isDirectory: &isDir) {
                    let size = self.calculateSize(at: path, isDirectory: isDir.boolValue)
                    relatedFiles.append(ApplicationRelatedFile(path: path, sizeBytes: size, category: category))
                }
            }
            
            return relatedFiles
        }.value
    }
    
    private func calculateSize(at path: String, isDirectory: Bool) -> Int64 {
        let url = URL(fileURLWithPath: path)
        var sizeBytes: Int64 = 0
        if isDirectory {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
                       let allocatedSize = values.totalFileAllocatedSize {
                        sizeBytes += Int64(allocatedSize)
                    }
                }
            }
        } else {
            if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                sizeBytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return sizeBytes
    }
}
