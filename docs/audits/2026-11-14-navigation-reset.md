# Section navigation reset — 14 November 2026

Changing the selected section now clears the outgoing section's temporary state, regardless of whether navigation comes from the sidebar, keyboard, menu bar, or an in-page link. Selecting the current section again keeps its current state.

- Clean Up, Large Files, Photos, and Disk Usage return to their initial screen. Scan results, progress, selections, confirmation dialogs, temporary filters, and previews are released. Abandoned scans are cancelled and late callbacks cannot restore their results.
- Applications and Login Items discard their lists and refresh when opened again. Their views also refresh if the user returns before an active uninstall or login-item change finishes.
- Clean, Trash, Put Back, uninstall, and login-item changes already in progress finish before their temporary state is cleared. A clean still records its history. Returning during an operation keeps its busy state until it finishes, preventing duplicate work.
- System Monitor resets its temporary process selection and sort; Settings returns to General. Live readings, recordings, fan control, saved settings, and clean history remain available.

Verification: all 238 unit tests passed, including navigation, cancellation, late system replies, deferred cleanup and restoration, saved login-item changes, and recording preservation. The full scan/review/navigation UI flow passed. A fresh universal Release archive and development DMG were built as version 1.0, build 8. App and fan helper contain both arm64 and x86_64; packaging verified their signatures and the completed disk image.

Logs and test results: `build/navigation-reset-2026-11-14/`. The refreshed local installer is `build/CachePop-1.0-dev.dmg`.
