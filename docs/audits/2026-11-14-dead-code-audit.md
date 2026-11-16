# Dead code audit — 14 November 2026

Reviewed all 81 production Swift files, 27 test files, the Xcode target configuration, and packaging scripts. Used repository reference searches and compiler IndexStore declarations/references, then manually checked candidates for runtime dispatch, generated conformance, and shared helper use.

The cleanup changes 14 production files and removes a net 128 production lines. Earlier uncommitted work was preserved; the task's starting sources and isolated cleanup patch are in `build/dead-code-audit-2026-11-14`.

## Removed

- Obsolete CPU, memory, drive, and fan branches from the SwiftUI menu bar label. Those readings use native status item controllers. The remaining temperature label keeps its sampling lifecycle, window action, and accessibility identifier; the live capsule image renderer now has its own utility type.
- Unused photo result notes and the uncalled batch assembly helper. Moved the superseded photo grouping algorithm into test support as an independent reference oracle. Updated the small time-window test to exercise the production streaming builder directly.
- Unused large-file byte total, cleanup progress property, file action empty result, and app-related-file name/size formatting properties.
- Unused CPU tick totals, temperature-reader availability property, and the old fixed log-age constant (the active scanner uses the configured age).
- Unread simulator response fields and their obsolete coding key.
- The uncalled per-fan automatic wrapper from the app's internal controller protocol and its implementations/test doubles. Kept the shared XPC endpoint for helper protocol compatibility.

Retained runtime callbacks, SwiftUI/AppKit protocol implementations, synthesized Codable/CaseIterable support, helper-only functions, and SMC fields required for the binary message layout. Packaging scripts are all referenced by the packaging flow or setup instructions.

## Verification

- All 230 unit tests in 36 suites passed.
- Menu bar priority list and independent reading controls UI test passed.
- Temperature popup light/dark UI test passed on an isolated retry. The first combined run timed out opening the popup; the failure did not reproduce on the retry.
- Universal Release build passed; the executable contains both `arm64` and `x86_64` architectures.

Build logs and test result bundles: `build/dead-code-audit-2026-11-14/`.
