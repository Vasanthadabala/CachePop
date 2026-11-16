**CachePop codebase resource and reliability audit — 13 November 2026**

The audit inventoried the app, shared SMC code, fan helper and packaging scripts, searched the complete source inventory for resource ownership and expensive operations, and reviewed the affected execution paths. The resulting app/shared/helper inventory contains 81 Swift files. Earlier fixes and the requested half-second CPU, memory and temperature refresh remain in place.

Additional confirmed issues were fixed in source and verified in a universal Release build. This audit did not rebuild either DMG.

**Changes**

| Area | Problem and resulting behavior |
| --- | --- |
| Large-file scan memory | The file walk lacked a per-item autorelease pool, and retained result URLs could keep prefetched metadata. Each iteration now drains temporary objects; retained URLs discard the metadata cache. File identities are collected only for files actually kept for review or duplicate comparison. Photo and old-log result URLs also discard cached metadata. |
| File-type cache | Every distinct extension could grow a process-wide dictionary for the rest of the session. The cache now has a strict 512-entry bound and is cleared during transient-memory trimming. |
| Metadata reads | Project manifests, AI-model manifests and Android configuration files could be read completely regardless of size. A shared reader caps these small metadata inputs at 1 MiB, rejects directories and named pipes, checks cancellation and closes its descriptor. Launch-agent and archive property lists use the same reader. Device-backup metadata retains its existing behavior because those property lists can legitimately be large. Login Items reuses its parsed property list rather than reading it twice. |
| Cancellation | Old-log enumeration, project-database/workspace checks and model-directory traversal could continue after Stop. These paths now check cancellation. A cancelled Mail attachment edit check keeps the attachment instead of declaring it removable. Existing cancellable directory sizing, subprocess and photo-worker behavior is preserved. |
| UI icon loading | Finder icons performed file checks, Launch Services lookup and bitmap conversion while SwiftUI evaluated view bodies. Visible rows now load icons asynchronously. Login Items and process rows use the same display-sized cache, and disappearing views release their image state. Cache generations prevent an old in-flight lookup from repopulating a cleared cache. |
| Thumbnail invalidation | The generation check and thumbnail cache insertion were separate operations, allowing a concurrent clear to be followed by an old insertion. They now occur under the same lock. |
| Monitor updates | Every sensor reading wrote peak values even when they had not increased. CPU, memory and sensor peaks now publish only a new maximum, reducing unnecessary observer invalidations while preserving live refresh. |
| Fan safety requests | A slow helper could receive another automatic-release request on every hot reading. Concurrent heat checks now share one pending safety release and can retry after it finishes. The regression submits 40 heat checks to a stalled fake controller and verifies one helper request. |
| Disk Usage | An Applications folder already inside the overview's home folder could be added a second time, producing duplicate row identities and measurements. The overview now deduplicates the supplied and discovered entries. |
| Reviewed files | Large Files and folder-photo results stored only paths. A replacement or edited file at that path could be removed after the user reviewed an older file. Results now carry device/inode, size and modification/change timestamps. The Trash service checks them before measurement and immediately before moving; changed files remain and the UI requests a rescan. |
| Duplicate detection | Different hard-link names for the same inode could appear as extra duplicate copies. Duplicate comparison now deduplicates storage identities, while independent copies still form duplicate groups. |
| Put Back | Restoring a reviewed file changes its metadata. Successful restoration now refreshes that file's review identity so the new safety checks do not break subsequent review/removal. Other result identities remain unchanged. |
| Large-file totals | Reclaimable-space calculation no longer allocates intermediate flattened and filtered file arrays just to compute the total. Existing double-counting regressions still pass. |
| Native-menu recovery | The main-window action was registered only by views appearing on screen, which was unreliable when restoring a native-menu-only launch. App commands now register the window action before a window appears. The UI check closes the window, terminates the app, relaunches without the saved-state override, and opens System Monitor from the native fan menu. Its capture is restricted to the app window. |

**Verification**

- Baseline: 218 unit tests passed. Final: **230 unit tests passed**, including [12 new audit regressions](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/CachePopTests/FullResourceAuditTests.swift). Existing lifetime, cancellation, half-second refresh, fan-control, scan, cleanup and restoration tests remain green. [Final unit log](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/undo-tests.log).
- **Two UI scenarios passed:** the all-sections demo flow and native-menu recovery after ordinary relaunch. The first covers cleanup review/confirmation cancellation, Large Files, photo results, monitor details, Disk Usage navigation, uninstall confirmation cancellation, Login Items, settings accessibility and appearance. [UI log](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/final-tests.log). App-window captures of Applications and System Monitor were visually inspected; the native relaunch capture was subsequently changed to omit unrelated displays.
- The optimized app and embedded helper both compile for **arm64 and x86_64**. No Swift compiler warnings occurred; Xcode emits its generic destination/App Intents metadata notices. [Final Release log](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/final-release-build.log).
- Apple's `leaks` reported **0 leaks / 0 leaked bytes** in the sampled fixed demo process. It reported a 70.1 MB physical footprint and a 76.2 MB startup peak. This was a short runtime snapshot, not proof that every workflow or long session is leak-free. [Leak report](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/leaks-after.txt).

**Measurements**

An optimized standalone harness used the actual before/after `LargeFilesScanner` implementations and the same canonical-path routine. It scanned 10,000 disposable empty files, using a zero-byte review threshold to retain every result. Each variant ran twice in before/after/after/before order; the table shows medians. This isolates metadata/result overhead rather than photo decoding, duplicate hashing or the entire app's RAM.

| 10,000 retained scan results | Before | After |
| --- | ---: | ---: |
| Peak physical footprint | 15.32 MiB | 13.10 MiB |
| Scan duration | 0.570 s | 0.537 s |

Peak memory in this fixture decreased approximately **14.5%**, including the newly stored review identities. The small timing difference is an observation from two runs per variant, not a general speed guarantee. A separate scan retaining no results showed little memory difference. [Retained-results measurements](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/scan-retained-memory-comparison.json), [non-retaining measurements](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/scan-memory-comparison.json).

A separate Debug demo run with the CPU menu item enabled used an eight-second warm-up followed by 20 one-second memory samples. CPU was calculated from process CPU time over elapsed wall time. Median physical footprint was **69.66 MiB before / 70.08 MiB after**; CPU averaged **2.54% / 2.49% of one core**. These idle observations do not show a meaningful overall memory or CPU reduction. They were not controlled for other applications and are not production Release measurements. [Samples and summary](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/idle-runtime-comparison.json).

**Remaining limits**

Xcode still records a startup main-thread responsiveness warning. Its saved issue contains no source location and only address-based frames; inspecting the result and attempting symbolication did not identify an actionable app call. It is not counted as fixed. [Issue data](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/ui-legacy-summary-0.json), [symbolication attempt](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/full-resource-audit-2026-11-13/warning-symbols.txt).

Runtime checks ran on Apple silicon with disposable fixtures and demo controllers; physical fan speeds and real login items were not changed. Long-session Instruments traces, large real Photos libraries, slow external-volume behavior and Intel runtime testing remain outside this verification. Existing scan results, selections, undo state, recordings and live refresh behavior are preserved.
