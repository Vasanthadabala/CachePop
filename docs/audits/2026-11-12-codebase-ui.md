**CachePop codebase and UI review — 12 November 2026**

The review found useful reliability and accessibility fixes, which are now implemented in source. The existing visual structure works across the main feature areas. The next product improvements should make reviewing and finding items easier, especially photo comparison, search, selecting drives and undoing app uninstalls.

The scope covers all seven feature areas, Settings and History, the menu bar, cleanup and file actions, permissions, background lifecycle, monitoring, the privileged fan helper and release scripts. The app, shared code and helper contain 76 Swift source files. This was a review of the feature areas and important data paths, with regression tests and rendered UI checks.

**Fixes implemented**

| Area | Finding and resulting behavior |
| --- | --- |
| Exact duplicate detection | Read errors were converted to empty data, allowing an incomplete hash to look like a successful read. Quick and full hashing now fail on read/seek errors. |
| Cleaning while work starts | Process and simulator state was captured once for the whole clean. It is now refreshed before each selected item, and app-cache owners are checked again per folder. |
| Unavailable process information | A failed process-list read could look like no tools were running. Build, Gradle, CLI and emulator checks now keep affected items blocked when the required state is unavailable. Missing simulator tooling also leaves simulator state unknown. |
| Custom scan scope | Missing custom folders could silently fall back to all home folders. A custom scope now stays a custom scope, with an unreadable-location notice. |
| Incomplete scans | Large Files now tells the user about unreadable items and the scan file limit. An incomplete scan should not look like a definitive empty result. |
| Found-space totals | Large duplicate copies appeared in both Large Files and Extra Copies. The headline, sidebar and breakdown now count them once. |
| Low-space alerts | Zero bytes available now triggers the alert. The cooldown and recovery state persist across relaunches. |
| Put Back | Dangling symbolic links can be restored. Existing destinations, including dangling links, are kept. |
| Command timeouts | The timeout now covers output collection when a child inherits a tool's stdout/stderr and keeps the pipes open after its parent exits. |
| Fan input handling | Non-finite readings, numeric conversion overflow, invalid fan indices and contradictory speed limits are rejected or bounded. The helper version is now 3 so the existing replacement mechanism recognizes the update. |
| Uninstall confirmation | Repeated confirmation cannot start overlapping uninstalls. |
| Accessibility | Settings and Login Items switches have meaningful names. Disk Usage folder rows have accessibility actions and Return/Space activation. |
| Drive naming | Clean Up and Disk Usage use the actual volume name. |
| Compact layout legibility | Monitor stat labels stay on one line, while numeric values retain their width. Keep/Favourite photo badges have an opaque backing so they remain readable over busy images. |
| Demo isolation | Applications, Library measurements, Login Items and Disk Usage respect the fixture home. Shared system startup items are excluded from fixture scans. The demo includes miniature app bundles and valid camera images. The visual tour cannot clean the real home when the demo flag is omitted. |
| Concurrency diagnostics | Stateless scanner functions and constants have explicit isolation, removing the scanner actor-isolation compiler warnings. |

The regression coverage is in [AuditRegressionTests.swift](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/CachePopTests/AuditRegressionTests.swift). The interaction test is in [AppFlowUITests.swift](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/CachePopUITests/AppFlowUITests.swift).

**Recommended next work, in priority order**

| Priority | Improvement | Why it matters and a concrete acceptance check |
| --- | --- | --- |
| High | Revalidate user files before moving them | Large Files and Photos retain path-based selections. A file can be replaced or changed after scanning. Store a file identity and relevant metadata, then skip changed items and offer a rescan. Test replacing a reviewed file before confirmation. |
| High | Cold-launch and saved-window recovery coverage | Saved-window restoration suppressed the tour/test window during this review. The compact test explicitly ignores saved state. Add a separate ordinary cold-launch test after quitting in menu-bar-only mode, including a configuration with only native CPU/Memory/Drive/Fan items. Verify that menu actions can restore the main window before RootView has appeared. |
| High | Photo comparison preview | A tile click selects a photo, and folder photos can be opened externally. Add a large preview with zoom, next/previous navigation and side-by-side comparison with the suggested best shot. Include library photos and preserve selection state while previewing. |
| Medium | Search for long lists | Applications has filters and sorting but no text search. Add name/path search to Applications and Large Files, and name/PID search to processes. Test an empty result and clearing the search without losing selections. |
| Medium | Select a drive or volume | Space readings and Disk Usage start from the home volume; activity rates aggregate drives. Add a clear volume picker, volume-specific capacity and a disconnected-drive state. Keep aggregate throughput explicitly labelled. |
| Medium | Put Back after app uninstall | Other file-removal flows keep Trash destinations for one-click restoration. Uninstall results should also retain them and offer Put Back, refusing to overwrite new files. |
| Medium | Visible history persistence failures | History can fall back to an in-memory store, and save errors are currently swallowed. Show when history is session-only or could not be saved, with a retry path. Test denied writes and a full volume. |
| Medium | Improve instructional text contrast | Some Clean Up explanations, chart labels and fan-range captions are very faint. Use the secondary text treatment for meaningful instructions and validate the light/dark appearances with Increase Contrast. |
| Medium | Reproducible public releases | The DMG script requires a local Developer ID identity and notarytool profile, while this machine uses Xcode cloud signing. Add the working cloud-signing route to the release script or CI, with versioned artifacts, signature/ticket checks and a clean-machine install check. |
| Later | Timestamped monitor graphs | Graph history stores values while sampling intervals vary with visibility. Timestamp samples so time labels, pauses and resumed sessions can be explained accurately. |

**Verification and UI observations**

- 197 unit tests pass, including 12 audit regressions. [Saved unit summary](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/audit-unit-summary.json).
- The all-sections demo UI test passes: scan, review and cancel, Large Files, Photos, monitor details, Disk Usage drill-down/back, uninstall confirmation/cancel, Login Items, named settings controls, appearance switching and retaining an existing scan.
- The fan UI regression passes: centered animation, Automatic/Custom/Full Speed/Auto Boost controls, monitor details, recording and reopening after Command-Q.
- The normal-size visual tour produced 40 captures covering launch, scan/review/confirmation/results/Put Back, file filters and duplicates, photo grids, Applications, Login Items, Disk Usage, Settings, menu panels and monitor/fan states. Light and dark captures were reviewed. [Visual overview](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/audit-ui-tour/contact-sheet.jpg).
- The universal Release build succeeds. Both the app and helper contain arm64 and x86_64 binaries. Scanner concurrency warnings are resolved; Xcode still prints a generic destination metadata diagnostic.

The ordinary layouts retain clear grouping and usable action bars. Long category legends wrap rather than overlap in the reviewed normal-size captures. Photo review and app discovery would benefit more from preview/search tools than a broad visual redesign.

The compact-window interaction check also passes at a 940-point-wide window, covering all seven sections and dark Settings. Test runs ignore saved-window restoration to ensure a previous visual tour cannot suppress the test window. [Eight compact captures](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/audit-compact-ui-proof-final/contact-sheet.jpg) were reviewed. This caught and corrected wrapping memory-stat labels and low-contrast photo badges; the updated interaction test passes.

Fan controls were exercised through the demo controller; physical fan speeds were not changed. Intel binaries were compiled, with runtime testing performed on Apple silicon. These audit fixes are in source and the local Release build. The earlier public DMG still contains the previous release and needs a fresh archive, signing and notarization cycle to include them.
