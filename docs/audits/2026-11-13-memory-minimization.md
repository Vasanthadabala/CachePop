**CachePop memory reductions — 13 November 2026**

The main window now releases its SwiftUI content when CachePop enters menu-bar-only mode or the window closes. Reopening rebuilds the interface from the existing models. Scan results, selections, Put Back information and recordings remain available. Temperature and fan monitoring continue.

Additional changes:

- Installed-app scans retain metadata instead of a pre-rendered bitmap for every app. Visible rows request display-sized icons as needed.
- File icons use a 128-entry/4 MiB cache target, down from 800 entries/16 MiB. Photo thumbnails use a 64-entry/8 MiB target, down from 200 entries/32 MiB. NSCache limits are advisory, not a cap on total app memory.
- Background trimming discards thumbnail/icon caches, cached related-file listings for unselected apps, inactive disk drill-down listings and unused process/app details. Current disk listings, app measurements and selected related files remain available.
- A memory-pressure notification also clears these rebuildable caches. After the window detaches, unused allocator pages are returned with `malloc_zone_pressure_relief` off the main actor. This runs once after a short delay, not on each monitor tick. The trim task and pressure observer do not retain the model.

**Measurements**

All figures below use macOS `proc_pid_rusage` physical footprint, in MiB. They are observations on this MacBook Air, not fixed requirements or an upper bound. Resident size includes other mapped pages and is reported separately in the JSON artifacts.

The same Debug UI workload ran before and after the production changes: scan disposable cleanup data, open Applications and System Monitor, analyze 69 fixture photos, scroll ten times, use Command-Q, reopen through the fan menu, verify the cleanup and photo results, then use Command-Q again. Each background figure is the median of the final three one-second samples in its hidden segment.

| Controlled workload | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| First entry into menu-bar-only mode | 203.67 MiB | 92.05 MiB | 54.8% |
| After reopening and hiding again | 152.63 MiB | 102.81 MiB | 32.6% |

The fixture creates large disposable files in-process; its temporary buffers, Vision and SwiftUI warm-up contribute to the roughly 500 MiB Debug peak. These figures do not represent a normal production launch. The changes primarily reduce retained background memory, rather than claiming to eliminate all analysis peaks.

The universal Release app was also launched with ordinary user settings, without scans, then switched to menu-bar-only mode. Five process samples gave a median physical footprint of **57.47 MiB before and 55.75 MiB after**. This idle difference is small; the larger benefit appears after using heavier views and previews. The optimized app was reopened and its normal interface restored successfully.

Measurement artifacts: [Debug comparison](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/memory-minimization/comparison.json), [before samples](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/memory-minimization/before.json), [after samples](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/memory-minimization/after.json), [Release comparison](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/memory-minimization/release-comparison.json).

**Validation**

- 215 unit tests passed, including checks that background trimming preserves review selections, temperatures, fans and recordings; retains the current disk listing and overview; and app scanning does not retain pre-rendered icons.
- The memory UI workload passed, including returning from menu-bar-only mode through the fan menu and restoring cleanup/photo results. No deletion or physical fan override was performed.
- The Release app compiled for arm64 and x86_64. No Swift compiler warnings appeared in the final unit and Release logs. `git diff --check` passed.
- Xcode's UI result contains an unsymbolicated main-thread responsiveness warning with no source location, and a runner coverage-profile download permission warning. These do not fail the test; this work does not claim to resolve the previously observed startup diagnostic.

The updated local app is [CachePop.app](/Volumes/Personal/Mac/Code/Work/MacOS/CachePop/build/menu-bar-release/DerivedData/Build/Products/Release/CachePop.app). The public DMG was not regenerated as part of this memory change.
