# Architecture refactor — 15 November 2026

The codebase now follows feature-based MVVM with explicit domain, data, and presentation responsibilities. The app remains a single module with a separate privileged helper; source checks and an independent domain compilation enforce the boundaries. See [Architecture](architecture.md) for the maintained rules and dependency diagram.

## Changes

- Reorganized feature implementations into `Domain`, `Data`, and `Presentation`, with Menu Bar remaining presentation over existing state. Shared filesystem and command adapters live in `Core/Data`; shared values and contracts live in `Core/Domain`.
- Separated models from scanners, hardware readers, and platform APIs. Application records no longer retain `NSImage` or running-process handles. The helper's `FanSample` is separate from its IOKit implementation.
- Added injected interfaces for cleanup, file scanning/classification, disk measurement, Photos access, Trash and restoration, application management, startup enumeration, preferences, history storage, and process control. Existing sampler and fan-control interfaces are retained.
- Moved live feature constructors into `App/Composition/FeatureComposition.swift`. View models receive services; native folder selection uses a presentation collaborator. Large Files reads preferences through a contract rather than depending on the settings view model.
- Moved defaults access and app-login registration behind settings interfaces. History presentation receives value entries from a SwiftData adapter. The original `CleanRecord` entity, fields, store name/location, and preference keys are retained.
- Extracted photo-quality and cleanup-ordering rules into the domain. Preserved scanner cancellation, safety checks, bounded caches, one-second sampling, and navigation reset behavior.
- Added `scripts/check-architecture.py --typecheck` and seven service-contract tests. The checker also rejects duplicate Swift basenames, which collide in Xcode's generated outputs.

## Verification

| Check | Result |
| --- | --- |
| Source boundary checks | Passed across 146 app Swift files: 44 domain files and 49 data files |
| Independent domain compilation | Passed with warnings treated as errors, without app/UI/data sources |
| Checker negative cases | Correctly rejected domain UI imports, domain concrete-adapter dependencies, data UI imports, and concrete adapters constructed in a view model |
| Final full unit suite | 282 passed, 0 failed, 0 skipped, 0 runtime warnings |
| Native XCTest UI automation | Could not initialize; two attempts timed out while macOS enabled automation mode, before reaching CachePop |
| Read-only composed-app tour | Completed successfully, producing 37 screenshots of fixture scan/results, history, settings, monitoring, and menu panels |
| Rendered screenshot inspection | History entries/totals, Applications, Login Items, and dark monitoring/process controls checked |
| Universal Release archive | Passed for Apple silicon and Intel, including the embedded fan helper |
| Development DMG | Build 18 packaged; enclosed signatures and disk-image integrity verified after read-only mounting |
| Source consistency | All 161 frozen source/resource/project files match the release manifest |

The UI-runner initialization failure is an environment limitation, not a passing interaction test. The read-only tour exercises composed view models and rendering; it does not replace native UI interaction coverage. No real cleanup, application removal, login-item changes, fan override, or helper installation was performed by the tour.

Sidebar and battery-icon rendering sources match their pre-refactor hashes. The installed application was not replaced. The DMG is signed for local development and is not notarized.

Evidence is saved under `build/architecture-refactor-2026-11-15/`: pre-refactor source backup/manifest, move records, boundary-check output, test result bundles and summaries, read-only tour screenshots, final archive, and packaging logs.
