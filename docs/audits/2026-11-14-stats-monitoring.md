# Focused monitoring update — 14 November 2026

Inspected the installed Stats 3.0.26 app, including its dashboard, CPU, GPU, RAM, disk, sensors, battery and other module screens. The final CachePop changes follow the requested six-module scope.

| Module | CachePop behavior |
| --- | --- |
| CPU | Live total, user/system load, per-core bars, efficiency/performance grouping from reported logical core IDs, and top processes. |
| GPU | Available device utilization, renderer and tiler activity, bounded usage history, and driver-reported memory in use. Missing readings stay unavailable. |
| Drive | Existing storage and I/O charts plus local mounted-volume capacity, filesystem and read-only status. APFS volumes can share free space. The main capacity card includes Finder-style purgeable estimates; cached mount statistics can differ. |
| Memory | Breakdown, pressure, swap and history, with the process list initially sorted by memory. |
| Sensors | Grouped CPU/chip, GPU, memory, drive and battery temperature readings. Existing fan controls and sensor peak/status tools remain accessible. |
| Battery | Existing charge, health, cycles and time estimate plus reported voltage/current and calculated battery power. This is battery power, not total power at the wall. |

The six-page selector replaces the long mixed card layout. The existing menu bar settings link is a small toolbar button. Charts retain at most 240 readings per device. Process commands run while CPU or Memory is visible, or another process popup requests them. Drive metadata uses one utility task with a 15-second cache, so a slow read cannot block live sampling or accumulate duplicate jobs. Cancelling an old metadata request prevents it from publishing stale results.

GPU and core-group data come from optional driver/device-tree properties read through IOKit. The implementation handles missing or invalid statistics and releases registry entries, iterators and copied properties. Apple's [IORegistry property-copy API documentation](https://developer.apple.com/documentation/iokit/1514310-ioregistryentrycreatecfpropertie) describes the snapshot and ownership contract used by these readers.

## Validation

- All 245 unit tests passed, including invalid GPU values, logical core mapping, battery units, bounded histories, device removal and blocked/cancelled metadata requests.
- The native hardware probe found one GPU, ten mapped logical cores, local mounted volumes and a battery on this laptop.
- Existing main scan/review/navigation UI flow passed.
- All six monitoring pages passed UI checks in both light and dark appearances. A first test attempt used an ambiguous CPU selector; the final test scopes it to the module selector. Exported screenshots were visually reviewed at the compact window size.
- Universal Release archive built as version 1.0, build 10. Both app and fan helper contain arm64 and x86_64 code. DMG packaging verified app/helper signatures, team requirements, the packaged app signature and image integrity.

Logs, test results, source manifest, archive and previews: `build/stats-inspired-2026-11-14/`. The local installer is `build/CachePop-1.0-dev.dmg`, development-signed and not notarized.
