import AppKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class PermissionsManager {
    static let shared = PermissionsManager()
    
    var hasFullDiskAccess: Bool = false
    
    private init() {
        checkFullDiskAccess()
    }
    
    func checkFullDiskAccess() {
        // macOS checks FDA by seeing if it can list the contents of protected directories like Library/Application Support/com.apple.TCC
        let path = "/Library/Application Support/com.apple.TCC"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            let isReadable = FileManager.default.isReadableFile(atPath: path)
            hasFullDiskAccess = isReadable
        } else {
            hasFullDiskAccess = false
        }
    }
    
    func requestFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
