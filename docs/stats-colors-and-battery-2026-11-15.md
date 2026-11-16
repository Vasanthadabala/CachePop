# Stats palette, neutral navigation and battery icon — build 16

Compared the installed Stats 3.1.0 CPU, GPU, RAM and Disk screens, including their lower details/process sections, plus Sensors settings and Battery widget settings. Compared CachePop's six corresponding monitor pages. Other CachePop sections were reviewed through the existing demo scan/review/navigation UI flow. No Stats preference values were changed.

## Color assignments

The monitor now uses the same native AppKit color families confirmed in [Stats' color definitions](https://github.com/exelban/stats/blob/master/Kit/types.swift) and its [CPU](https://github.com/exelban/stats/blob/master/Modules/CPU/popup.swift), [RAM](https://github.com/exelban/stats/blob/master/Modules/RAM/popup.swift), and [Disk](https://github.com/exelban/stats/blob/master/Modules/Disk/popup.swift) popups:

| Data | Color |
| --- | --- |
| History charts and primary usage | System blue |
| CPU apps / system / idle | Blue / red / light gray |
| Efficiency / performance cores and frequency markers | System teal (cyan) / indigo |
| Memory app / wired / compressed / cached | Blue / orange / pink / light gray |
| Drive read / write | Blue / red |
| Battery charge | Green |

Colors adapt through native system colors in both appearances. Sidebar symbols, badges, Settings and ordinary disk usage are neutral; meaningful low-space warnings retain their warning color. Clean Up's category legends, selected bar portions, scan indicators and category tiles retain distinct colors. Unselected bar portions stay gray. Text and surfaces remain neutral, and sensor popup icons remain monochrome.

## Menu controls

- The Monitor options control uses a three-dot circle with a 28-point label and hides the redundant menu indicator. This removes the overlapping ellipsis/chevron shown in the report. Its actions and tooltip remain available.
- The Battery menu item is a fixed 32-point native status item with a template battery icon. Fill follows the percentage, and a bolt indicates charging. It has no visible label or number. Percentage and power source remain available through its tooltip, accessibility and popup.
- Battery rendering is cached by charge and power state, including charging transitions where the percentage stays the same. CPU/GPU/Memory/Drive capsule sizing and the one-second sampling loop are unchanged.

Battery icon previews were rendered at unknown, 0%, 1%, 25%, 50%, 80%, 100% and charging states. Native UI checks cover all six monitor pages in light/dark mode, the main app flows, and Battery popup navigation. Detailed test outcomes and any automation limitations are recorded in `build/stats-colors-battery-2026-11-15/verification.txt`.

The DMG is a signed local development build, without notarization or upload. The installed application was not replaced.
