# Applications and Login Items introductions — 14 November 2026

Applications and Login Items now open on an introduction screen using the same header, feature cards, and capsule button as Clean Up. Scanning starts only through Scan Applications, Scan Login Items, Enter, or the existing Scan Again command. Returning after navigation shows the introduction again.

Removed the automatic scan tasks and their unused scan-if-needed helpers. Updated the demo tour and UI workflows to start these scans explicitly.

All 238 unit tests passed. The full UI flow verified both scan buttons, no automatic scan on entry, Enter shortcuts, scan results, and resetting on navigation. Its first run failed opening Settings; after adding an explicit Settings readiness check, the complete flow passed. Exported screenshots were visually checked in light and dark appearances at the compact window size.

Built universal version 1.0, build 9. The app and fan helper both contain arm64 and x86_64 code. Packaging verified app/helper signatures, team requirements, the packaged app signature, and the disk image checksum. The installer is development-signed and not notarized.

Logs, screenshots, source manifest, and test results: `build/feature-intros-2026-11-14/`. Updated installer: `build/CachePop-1.0-dev.dmg`.
