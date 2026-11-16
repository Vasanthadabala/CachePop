import Darwin

nonisolated enum MemoryResources {
    /// Best-effort release of unused allocator pages after the window UI is gone
    /// or macOS reports memory pressure. Never runs on every reading or frame.
    @concurrent
    static func releaseUnusedPages() async {
        guard !Task.isCancelled else { return }
        _ = malloc_zone_pressure_relief(nil, 0)
    }
}
