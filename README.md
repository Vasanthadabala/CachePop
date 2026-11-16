<div align="center">

<img src="CachePop/Assets.xcassets/CachePop.imageset/CachePop.png" width="120" alt="CachePop logo" />

# CachePop

**Free up space on your Mac, safely.**

A native macOS app that finds the gigabytes developers and everyday apps leave behind (Xcode builds, simulators, package caches, old logs, leftovers of deleted apps) and lets you clean them with a clear view of what comes back and what doesn't.

![macOS](https://img.shields.io/badge/macOS-26.4%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![Tests](https://img.shields.io/badge/tests-Swift%20Testing-2F6BF0)

</div>

---

## Why CachePop

Most cleaners show one big number and a "Clean" button. CachePop shows you **what each thing is, how big it is, and whether it comes back**, and nothing is removed until you confirm.

- 🧹 **Built for developers.** Knows Xcode, simulators, Android emulators, npm, Gradle, CocoaPods, Docker, Homebrew and more.
- 🔍 **Honest about every item.** Each one is labelled *Comes back automatically*, *Downloaded again when needed*, *Moved to the Trash* or *Doesn't come back*.
- 🛡️ **Safe by design.** Paths are re-checked right before deletion, anything in use is skipped, and you can mark folders as *Never Clean*.
- 📏 **Real numbers.** Freed space is measured from the disk afterwards, not guessed from file sizes.

---

## What's inside

| Section | What it does |
|---|---|
| 🗑️ **Clean Up** | Scans for caches and junk, groups them by type, and cleans only what you tick. |
| 📄 **Large Files** | Finds big files and exact duplicates in your personal folders and moves the ones you choose to the Trash. |
| 🖼️ **Photos** | Finds similar shots and blurry, too-dark or overexposed photos in your Photos library and folders. |
| 📈 **System Monitor** | Battery, CPU, GPU, Drive, Memory and Sensors, with live histories and busy processes. |
| 🥧 **Disk Usage** | Shows what's taking up space, folder by folder. |
| 🧩 **Applications** | Uninstalls apps together with the settings and caches they leave in your Library. |
| ⏻ **Login Items** | Lists everything that starts on its own and lets you switch it off. |
| ⚙️ **Settings** | Appearance, startup, alerts, the menu bar, what starts ticked, and your Never Clean list. |

### What Clean Up finds

| Group | Examples |
|---|---|
| **Xcode** | Derived data, iOS device support, old device crash logs, Xcode caches, archives older than 3 months |
| **Simulators & emulators** | Parallel-testing clones, SwiftUI preview simulators, broken simulators, unused runtimes, every simulator and Android emulator (erase or delete), unused Android system images |
| **Developer caches** | npm, Yarn, Bun, Gradle, SwiftPM, CocoaPods, pip, Go, Cargo, Maven, Flutter, Android SDK, JetBrains, Playwright, Deno, Codex, Docker, Homebrew, `~/.cache`, and local AI models from Ollama and LM Studio. Never ticked for you |
| **iPhone & iPad** | Device backups Finder made, and iOS update files |
| **Deleted apps & projects** | Data left by apps you've removed, broken login items, and Claude Code, Codex and editor data for project folders that no longer exist |
| **App caches, logs & Trash** | App caches, Safari's cache, web caches inside apps (Claude, VS Code, Slack…), Mail attachments, old logs and crash reports, installers in Downloads, Time Machine local snapshots, the Trash |
| **Browser history & cookies** | History and cookies in Safari, Chrome, Firefox, Brave, Edge, Arc and Vivaldi. Never ticked for you; bookmarks and passwords are never touched |

### In the menu bar

- **CachePop menu:** free space, live readings, and a quick scan.
- **Live readings (optional):** CPU, GPU, memory, Drive storage used, battery charge, chip temperature and fan speed, each as its own menu bar item. Battery uses a compact icon with charge fill and a charging bolt, without text; hover or open it for the percentage. Turn each item on in **Settings › Menu Bar**. GPU and Battery start off.
- **Reading controls:** Settings lists Fan speed, Temperature, CPU, GPU, Memory, Drive and Battery in that order. The fan switch stays off, disabled and dimmed when no fans are available. Hold ⌘ and drag an item to arrange it in the macOS menu bar.
- **Appearance:** menu bar readings are white. Popup titles have no colored dots; charts and data legends retain their identifying colors.
- **Live refresh:** CPU, memory and temperatures update once a second, including in menu-bar-only mode. Enabled CPU and memory menu items refresh their top processes in the background once a second, so the rows are ready before opening a popup. Process queries run separately so they don't delay the live readings; only the small set of top rows is retained while popups are closed.
- **Keep readings running:** when a menu bar item is enabled, ⌘Q switches CachePop to menu-bar-only mode, removing it from the Dock and app switcher. Reopen the main window from the menu bar or Finder. Choose **Quit CachePop** in a menu bar popup or the Dock's Quit command to stop everything.
- **Temperature popup:** CPU → GPU → Memory → Drive → Battery, with neutral icons and right-aligned readings. CPU shows a dash until a reading is available; other components appear when supported. Power, voltage and current readings are available in System Monitor's Sensors page.
- **CPU temperature:** uses CPU-specific SMC sensors for the detected chip, with CPU-specific HID sensors as a fallback. Generic power-management die sensors stay separate. Offline/invalid readings are excluded, and fan safety uses the hottest valid CPU sensor. Sensor identities are cross-checked against [Stats' CPU reader](https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift).
- **Fan panel:** a spinning fan indicator, individual RPM readings, Automatic, Custom and Auto Boost controls. Reduce Motion keeps the indicator still.
- **Individual usage panels:** CPU shows load, frequency, core activity and busy processes; Memory shows pressure, usage breakdown, swap and top processes; Drive shows capacity, health and read/write activity; GPU shows utilisation, temperature and busy clients; Battery shows charge, health, electrical readings and energy impact. GPU and Battery open their corresponding System Monitor pages.
- **Keyboard access:** while CachePop is active, Control–Command–C/G/M/D/B opens an enabled CPU/GPU/Memory/Drive/Battery panel. These are ordinary app shortcuts and need no global keyboard permissions.
- **Low-space alerts:** one notification when free space drops below the level you pick, at most once a day.

---

### System Monitor tools

- **Page order:** Battery → CPU → GPU → Drive → Memory → Sensors. The compact selector keeps Battery first and Sensors last.
- **CPU:** usage breakdown and history, per-core efficiency/performance bars, 1/5/15-minute load averages, reported cluster frequencies and top processes with PIDs. Frequencies use active-state residency and require supported Apple Silicon IOReport channels.
- **GPU:** usage, renderer and tiler histories, memory, temperature, available power and busy GPU clients. Display activity counts compositor swaps across displays; it is not an individual game's frame rate. Neural Engine power appears only when available; utilisation is not guessed from power.
- **Memory:** used/total, app/wired/compressed/free breakdown, pressure and swap histories, with top processes and PIDs.
- **Drive:** volume selection, per-device read/write rates and histories, capacity, filesystem, BSD name, writable/encrypted flags and busy I/O processes. Supported NVMe drives expose read-only SMART temperature, remaining life, lifetime transfers, spare, power cycles/hours and error counters. USB bridges and other unsupported devices show unavailable health data. SMART reads are cached for one minute.
- **Battery:** charge history, time remaining, health, cycles, temperature, raw capacities, voltage, current, calculated battery power, charging-paused state and connected adapter limits. Busy apps show macOS's relative energy impact, not watts.
- **Sensors & Status:** individual temperature readings grouped by CPU/chip, GPU, memory, Drive, battery and other sensors, with session peaks and Reset Peaks. Availability depends on the Mac.
- **Status checks:** macOS thermal pressure, memory pressure and swap, available Drive space, fan readings, network activity and battery capacity health. These checks do not run hardware self-tests. Read-only SMART details live on the Drive page when supported.
- **Auto Boost:** saved temperature rules boost all fans when thresholds are reached. The strongest matching rule wins; a 3°C release margin prevents rapid switching. Speeds stay within reported fan limits, and heat protection returns control to macOS.
- **Record / Export CSV:** optionally capture up to 1,800 recent numeric readings across CPU, memory, Drive I/O, network, temperatures, fans and battery. Process names and file paths are excluded; recording stays in memory until exported.

### Interface

- **Neutral navigation:** selected sidebar rows use a background highlight without a leading vertical line. Settings uses compact groups, and the downloads threshold dropdown keeps its native blue appearance.
- **Category colors:** cleanup and disk summaries favor blue, red, orange, green and gray, with purple reserved for additional cleanup categories. Cleanup's bar and legend put the extra purple category last. Solid color shows selected cleanup space; muted color shows the rest.
- **Monitor colors:** efficiency cores use turquoise and performance cores use violet-blue. GPU charts use violet-blue; memory and fans use turquoise; temperature and power charts use orange. Status colors identify normal readings, warnings and low battery charge inside popups.
- **Disk Usage:** the capacity summary distinguishes Applications, Home folder, macOS & other, and Free. Size bars beneath individual folders stay blue.
- **Progress and labels:** Photos, Applications and Login Items share circular loading indicators. The photo source label remains fully visible beside or below **Check Photos**.

## How a clean works

```mermaid
flowchart LR
    A[Scan] --> B[Review<br/>tick what to clean]
    B --> C[Confirm<br/>grouped by what comes back]
    C --> D[Safety check<br/>every path, right before]
    D --> E[Clean<br/>skip anything in use]
    E --> F[Measure<br/>real space freed]
    F --> G[History]
```

1. **Scan.** All scanners run at the same time and each group appears as soon as it's ready.
2. **Review.** Developer caches, browser history and cookies always start unticked. Other safe items may start ticked; anything permanent, like erasing a simulator or emptying the Trash, starts unticked.
3. **Confirm.** A sheet lists exactly what will happen, grouped by whether it comes back.
4. **Clean.** Every path is checked again by `PathSafety`, and booted simulators, running builds and open apps are skipped.
5. **Measure.** CachePop reads the free space on the disk before and after, and saves the result in **History** (⌘Y).

### Safety rules

- Files are only ever removed from a short list of known cache locations in your home folder.
- Protected places (Documents, Mail, Photos, keychains…) are never touched, and symlinks or `..` can't sneak a path out of a cache folder.
- Folders on your **Never Clean** list are skipped both when scanning and again during the clean.
- Leftovers, installers, backups and large files go to the **Trash**, so you can put them back.

---

## Getting started

### Requirements

- macOS 26.4 or later
- Xcode 26.4 or later to build

### Build and run

```bash
git clone https://github.com/Vasanthadabala/CachePop.git
cd CachePop
open CachePop.xcodeproj
```

Then pick the **CachePop** scheme and press **⌘R**.

### Permissions

| Permission | Why | Where to turn it on |
|---|---|---|
| **Full Disk Access** (optional) | Lets CachePop see inside the Trash, Safari's cache and history, Mail attachments, device backups and other caches macOS keeps private | System Settings › Privacy & Security › Full Disk Access |
| **Photos** (optional) | Lets the Photos section check your Photos library. Removed photos go to Recently Deleted in Photos for 30 days | Asked the first time you check photos, or System Settings › Privacy & Security › Photos |
| **Fan control helper** (optional, Macs with fans) | Lets you set fan speeds. Fans go back to macOS automatically above 95 °C or when CachePop quits | Settings › General › Fan control, then allow it in System Settings › Login Items |

> [!NOTE]
> CachePop isn't sandboxed, so it can run `simctl` and `brew` and reach developer folders. The fan helper only accepts connections from CachePop signed by the same team. If you build with your own team, update `teamID` in `CachePopShared/FanHelperProtocol.swift`.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 – ⌘7 | Go to Clean Up, Large Files, Photos, System Monitor, Disk Usage, Applications, Login Items |
| ⌘, | Settings |
| ⌘R | Scan again |
| ⇧⌘⌫ | Clean selected |
| ⌘Y | History |
| ⌘Q | Switch to menu-bar-only mode when a menu bar item is enabled; otherwise quit |
| ⌥⌘Q | Quit completely, including menu bar readings (while a menu bar item is enabled) |

---

## Project structure

CachePop uses feature-based MVVM with Clean Architecture boundaries. Feature domain models,
policies and service contracts depend on Foundation; data adapters implement those contracts;
presentation owns SwiftUI views and observable view models. Live adapters are assembled in
`App/Composition/FeatureComposition.swift` and `AppModel`.

```
CachePop/
├── App/                         Entry, navigation, lifecycle and dependency composition
├── Core/
│   ├── Domain/                  Shared values, cleanup models and external-service contracts
│   └── Data/                    Filesystem, command, disk, notification and permission adapters
├── Features/
│   ├── CleanUp/
│   ├── LargeFiles/
│   ├── Photos/
│   ├── SystemMonitor/
│   ├── DiskUsage/
│   ├── Apps/
│   ├── LoginItems/
│   ├── History/
│   ├── Settings/
│   │   └── Each feature uses Domain/, Data/ and Presentation/ as needed
│   └── MenuBar/Presentation/    Native status items and popup presentation
├── Shared/                      Theme, reusable presentation and native UI collaborators
└── Debug/                       Fixture data, demo tour and diagnostics
CachePopFanHelper/               Separate privileged XPC executable
CachePopShared/                  App/helper protocol, portable fan values and SMC adapter
CachePopTests/                   Unit and service-contract tests (Swift Testing)
CachePopUITests/                 Native UI tests
LaunchDaemons/                  Embedded helper launchd configuration
```

Run `python3 scripts/check-architecture.py --typecheck` to check dependency boundaries and
compile the complete domain without any app, UI or data-adapter sources. See
[Architecture](docs/architecture.md) for dependency rules and testing guidance.

---

## Development

### Run the tests

```bash
xcodebuild test -project CachePop.xcodeproj -scheme CachePop -destination 'platform=macOS' -parallel-testing-enabled NO
```

### Try it without touching your Mac

Debug builds have a **demo mode** that builds a miniature developer Mac (derived data, simulators, package caches, logs, Trash) in a temporary folder and runs the whole app against it. Cleaning really deletes those fixture files, so you can test the full flow safely.

Add `-CachePopDemo` under **Product › Scheme › Edit Scheme › Run › Arguments**, then run.

### Make a release DMG

Public builds contain a universal app for Apple silicon and Intel, signed with Developer ID and notarized by Apple. The installer uses a branded drag-to-install window with an Applications shortcut. Generated installers live in `build/`, which is excluded from Git; the current local public installer is `build/CachePop-1.0-public.dmg`.

Run the commands below from the repository root. Install the Finder layout tool once:

```bash
python3 -m venv build/dmg-tools
build/dmg-tools/bin/python -m pip install -r scripts/dmg-requirements.txt
```

**With a local Developer ID certificate**

`scripts/make-dmg.sh` archives the app, exports it with Developer ID, packages and signs the DMG, submits it to Apple, and staples its notarization ticket. Set up:

1. A **Developer ID Application** certificate. Create it in **Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application**.
2. Notary credentials saved in your keychain. The command asks for an app-specific password, which you can create at account.apple.com under **Sign-In and Security**:

   ```bash
   xcrun notarytool store-credentials CachePop --apple-id 'you@example.com' --team-id 4R2U97FG78
   ```

Then build the release:

```bash
scripts/make-dmg.sh
```

The signed, notarized DMG lands at `build/CachePop-1.0.dmg`. `scripts/make-dmg.sh --dev` creates `build/CachePop-1.0-dev.dmg` for local testing with a development certificate. `--help` lists the other options.

After changing only the installer artwork or layout, `scripts/make-dmg.sh --dev --repackage` rebuilds the development DMG using the existing exported app. Rebuild the archive after app code changes.

**With Xcode cloud-managed signing**

The public builds produced for this project use Xcode's cloud-managed Developer ID certificate and the signed-in Xcode account. This route submits the app and its embedded fan helper to Apple through Xcode, exports the notarized app with its ticket stapled, and packages that app into a DMG. The ticket belongs to the app; the DMG is its installation container.

<details>
<summary>Cloud signing, notarization and packaging commands</summary>

Use a fresh `build/public-release` output directory and an Xcode account authorized for the project's team. Forks must configure their own signing team and the matching fan-helper team ID.

```bash
mkdir -p build/public-release

python3 - <<'PY'
import plistlib
from pathlib import Path

options = {
    "method": "developer-id",
    "teamID": "4R2U97FG78",
    "signingStyle": "automatic",
    "destination": "upload",
}
Path("build/public-release/ExportOptions.plist").write_bytes(plistlib.dumps(options))
PY

xcodebuild archive -project CachePop.xcodeproj -scheme CachePop \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/public-release/CachePop.xcarchive \
  -derivedDataPath build/public-release/DerivedData

xcodebuild -exportArchive \
  -archivePath build/public-release/CachePop.xcarchive \
  -exportOptionsPlist build/public-release/ExportOptions.plist \
  -exportPath build/public-release/submission -allowProvisioningUpdates

xcodebuild -exportNotarizedApp \
  -archivePath build/public-release/CachePop.xcarchive \
  -exportPath build/public-release/notarized -allowProvisioningUpdates
```

If Apple is still processing the submission, repeat `-exportNotarizedApp` after processing finishes. Verify the exported app, then build the installer:

```bash
codesign --verify --deep --strict --all-architectures \
  build/public-release/notarized/CachePop.app
xcrun stapler validate -q build/public-release/notarized/CachePop.app
spctl --assess --type execute --verbose=4 \
  build/public-release/notarized/CachePop.app

xcrun swift -module-cache-path build/public-release/SwiftModuleCache \
  scripts/dmg-background.swift build/public-release/installer-background.tiff \
  CachePop/Assets.xcassets/BrandGlyph.imageset/BrandGlyph.png

build/dmg-tools/bin/python -m dmgbuild -s scripts/dmg-settings.py \
  -D app=build/public-release/notarized/CachePop.app \
  -D background=build/public-release/installer-background.tiff \
  'Install CachePop' build/public-release/CachePop-1.0-public.dmg

hdiutil verify -quiet build/public-release/CachePop-1.0-public.dmg
```

Before sharing, mount the finished DMG read-only and repeat the signature, ticket and Gatekeeper checks against the enclosed `CachePop.app`. Preserve the archive and its debug symbols for crash reports. Copy the verified installer to `build/CachePop-1.0-public.dmg` when ready.

</details>

---

<div align="center">

Made for Macs that are always running out of space.

</div>
