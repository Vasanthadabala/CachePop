# Stats comparison and compact monitor redesign

Scope: CPU, GPU, Drive, Memory, Sensors and Battery. Stats' installed CPU, GPU, RAM and Disk screens and its Sensors/Battery settings were reviewed. Windowless status items were not exposed by the automation interface, so the corresponding popup capabilities were also checked against [Stats' official source](https://github.com/exelban/stats/tree/master/Modules). No Stats preferences were changed.

| Module | Added or aligned in CachePop |
| --- | --- |
| CPU | Compact summary, user/system/idle breakdown, history, per-core bars with group-local efficiency/performance labels, load averages, all/E/P frequency, temperature and PID process table. |
| GPU | Utilisation/renderer/tiler histories, GPU memory and temperature, available energy counters, display activity, per-client GPU process deltas, optional menu item and popup. |
| Memory | Usage breakdown, free memory, pressure percentage/history where available, swap history, top processes and PIDs. |
| Drive | Volume selector, per-device activity/history, volume properties and Finder access, hardware connection/model, read-only NVMe SMART health and lifetime counters, process I/O rates. |
| Sensors | CPU average/hottest, GPU/memory/SSD/battery temperatures, searchable sensor list, electrical readings, power history and existing fan controls. Unknown power-management sensors remain separate from CPU temperature. |
| Battery | Charge history, time, capacities, health, cycles, temperature, electrical data, charging-paused state, connected adapter ratings, relative energy-impact processes, optional menu item and popup. |

The shared appearance now uses compact typography, monochrome navigation and category icons, neutral surfaces, a single blue accent and status colours only when meaningful. The monitor uses six focused pages instead of one long dashboard. Menu capsules retain their constant widths, independent of percentage length.

## Sampling and resource use

- Live readings use the existing one-second loop. IOReport does not create an extra timer or subprocess.
- Enabled CPU/Memory menu items keep a bounded top-process cache ready before opening. GPU, Drive and Battery process work runs only for the corresponding page or enabled menu item.
- Energy-process collection is detached, bounded, non-overlapping and cancellable, so its measured interval does not delay sensors.
- Histories retain at most 120 points. Disconnected GPU/drive histories and SMART cache entries are pruned. IORegistry iterators, services, SMART interfaces and IOReport objects are explicitly released.
- Slow hardware metadata stays off the live sampling path; SMART is read at most once per minute per drive. Drive capacity retains its slower refresh.

## Accuracy and availability

Frequency, GPU clients, electrical sensors and SMART depend on the Mac and macOS exposing the required channels. Unavailable values are shown as unavailable. Frozen Energy Model counters are not presented as measured zero. Neural Engine utilisation is not estimated from watts. Display activity is aggregated compositor swaps, not game FPS. Battery process energy is a relative macOS score, not power in watts.

The existing CPU-specific SMC/HID temperature selection and hottest-sensor fan safety remain in place. CPU power-management die sensors are not substituted for CPU core temperatures. This comparison checks sensor identities and units; it does not claim laboratory temperature calibration.

On the test Mac, live read-only probes confirmed cluster frequencies, GPU process counter parsing, per-volume device mapping and internal SSD SMART data. Its USB storage bridge did not expose NVMe health. CPU/Neural Engine energy counters were unavailable on the installed macOS and remain labelled accordingly.

Network, Bluetooth, remote monitoring, clocks, custom widget editors and extensive colour settings were intentionally excluded to keep the requested six-module scope simple. Existing recording/export and fan controls are retained.

## Validation

Native UI checks cover all six monitor pages in light and dark appearances, GPU/Battery popup navigation, and preloaded CPU/Memory processes with the main window closed. A menu manager repeatedly hid physical status icons; the popup checks use the app's normal Control–Command panel shortcuts, which invoke the same controller action. These shortcuts work while CachePop is active and do not install global event hooks.

Primary references: [CPU readers](https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift), [GPU reader](https://github.com/exelban/stats/blob/master/Modules/GPU/reader.swift), [Drive readers](https://github.com/exelban/stats/blob/master/Modules/Disk/readers.swift), [Battery popup](https://github.com/exelban/stats/blob/master/Modules/Battery/popup.swift), and Apple's [PowerManagement IOReport usage](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m).
