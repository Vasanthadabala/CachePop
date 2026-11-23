import Foundation

/// Uses only paths already offered by a scanner. It never discovers additional cleanup roots.
nonisolated enum CleanupEntryBuilder {
    static func populate(_ group: CleanupGroup, neverClean: NeverCleanList) -> CleanupGroup {
        var group = group
        group.items = group.items.map { item in
            guard item.entries.isEmpty, !item.isBlocked, !Task.isCancelled else { return item }
            var updated = item
            updated.entries = entries(for: item, neverClean: neverClean)
            return updated
        }
        return group
    }

    static func entries(for item: CleanupItem, neverClean: NeverCleanList) -> [CleanupEntry] {
        // Erase/Delete choices and model manifests with shared blobs are atomic.
        guard item.actions.count == 1,
              !(item.id.hasPrefix("dev.ollama.") && item.id != "dev.ollama.unused") else { return [] }
        let action = item.defaultAction
        switch action.operation {
        case .command:
            // Tool scanners supply entries when the tool supports individual targets.
            return []
        case .delete(let urls):
            if item.group == .browsers {
                // Keep SQLite databases, WAL/SHM/journal files and the same profile together.
                let profiles = Dictionary(grouping: urls) { url in
                    let parent = url.deletingLastPathComponent()
                    return parent.lastPathComponent == "Network" ? parent.deletingLastPathComponent() : parent
                }
                return sorted(profiles.compactMap { profile, files in
                    make(title: profile.lastPathComponent, urls: files, operation: .delete(files),
                         actionID: action.id, neverClean: neverClean, location: profile)
                })
            }
            return sorted(urls.compactMap { url in
                make(title: name(url, item: item), urls: [url], operation: .delete([url]),
                     actionID: action.id, neverClean: neverClean, location: url)
            })
        case .moveToTrash(let urls):
            return sorted(urls.compactMap { url in
                guard neverClean.protectedFolders(inside: url).isEmpty else { return nil }
                return make(title: name(url, item: item), urls: [url], operation: .moveToTrash([url]),
                            actionID: action.id, neverClean: neverClean, location: url)
            })
        case .deleteContents(let folders):
            if item.inUseCheck == .appCacheOwners {
                let apps = Dictionary(grouping: folders) { AppCacheOwnership.ownerFolderName(of: $0) }
                return sorted(apps.compactMap { owner, caches in
                    make(title: IDECachePolicy.displayName(for: owner) ?? owner, urls: caches,
                         operation: .deleteContents(caches), actionID: action.id,
                         neverClean: neverClean, location: caches.count == 1 ? caches.first : nil)
                })
            }
            return sorted(folders.flatMap { folder in
                guard !neverClean.protects(folder),
                      (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return [CleanupEntry]() }
                return FileManager.default.children(of: folder).compactMap { child in
                    make(title: name(child, item: item), urls: [child], operation: .delete([child]),
                         actionID: action.id, neverClean: neverClean, location: child)
                }
            })
        }
    }

    private static func make(title: String, urls: [URL], operation: CleanupOperation,
                             actionID: String, neverClean: NeverCleanList, location: URL?) -> CleanupEntry? {
        guard !Task.isCancelled else { return nil }
        let kept = urls.filter { !neverClean.protects($0) }
        guard kept.count == urls.count, !kept.isEmpty else { return nil }
        let bytes = kept.reduce(Int64(0)) { total, url in
            let protected = DirectorySizer.size(ofAll: neverClean.protectedFolders(inside: url)).bytes
            return total + max(DirectorySizer.size(of: url).bytes - protected, 0)
        }
        // Empty files can still belong to a meaningful database or a selected cache folder.
        let paths = kept.map(\.path).sorted()
        return CleanupEntry(id: paths.joined(separator: "\n"), title: title,
                            detail: paths.joined(separator: "\n"), sizeBytes: bytes,
                            operations: [actionID: operation], location: location)
    }

    private static func name(_ url: URL, item: CleanupItem) -> String {
        if item.id == "xcode.derivedData" { return XcodeScanner.projectName(url.lastPathComponent) }
        if url.pathExtension == "xcarchive" {
            return MetadataReader.propertyList(from: url.appendingPathComponent("Info.plist"))?["Name"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }

    private static func sorted(_ entries: [CleanupEntry]) -> [CleanupEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }.sorted {
            if $0.sizeBytes != $1.sizeBytes { return ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}
