# memmap native app: design

## Intent

memmap shows what is using memory right now as a treemap, with related processes grouped together. The Python version needs a terminal to start a local server and a browser tab to view it. The native app makes it something you launch from the Dock or Spotlight.

## Goals

- Match the Python version's features (listed under "Behavior").
- Launch like any Mac app: a `memmap.app` bundle you can put in `/Applications`.
- Read memory without `sudo` for every process the user owns.

## Non-goals for version 1

- Menu-bar icon, global hotkey, killing processes, notifications.
- Distribution to other people: no Developer ID signing, notarization, or auto-update.
- A privileged helper. Root-owned processes fall back to `ps`/`top` figures, as the Python version does without `sudo`.

## Anti-goals

- No HTTP server or open local port.
- No dependency on Python.
- No employer- or user-specific names, paths, or data anywhere in the repo, including test fixtures.

## Constraints

- macOS 14 or later, Apple silicon and Intel.
- Swift Package Manager only. A script assembles the `.app` bundle and signs it ad hoc. No Xcode project.
- No third-party packages. The squarified layout is written here. YMTreeMap was considered and rejected because it has been unmaintained since 2018.

## Architecture

| Target | Contents |
|-|-|
| `MemmapCore` (library) | Process collection, memory accounting, grouping, squarified layout. No UI imports. |
| `Memmap` (executable) | SwiftUI app: window, toolbar, treemap view, details panel. |
| `MemmapCoreTests` | Unit tests for layout, grouping, and size parsing, using synthetic fixtures. |

Collection runs on a background actor. The UI always renders the latest completed snapshot and never blocks on collection.

## Data sources

| Figure | Source for processes the user owns | Fallback for other processes |
|-|-|-|
| Process list, parent PID, uid | `proc_listallpids`, `proc_pidinfo(PROC_PIDTBSDINFO)` | `ps -axo pid,ppid,uid,rss,comm` |
| RSS | `proc_pidinfo(PROC_PIDTASKINFO)` resident size | `ps` RSS |
| Footprint | `proc_pid_rusage(RUSAGE_INFO_V4).ri_phys_footprint` | `top -l 1 -stats pid,mem,cmprs` MEM |
| Compressed | `top` CMPRS for all processes | same |
| Command line and environment | `sysctl(KERN_PROCARGS2)` | `ps -axww -o pid,args` (command line only) |
| Executable path | `proc_pidpath` | `ps` comm |
| Per-region data for shared split | `proc_pidinfo(PROC_PIDREGIONINFO)` walk | unavailable: RSS with a dashed outline |
| System totals | `top`'s PhysMem line (used, compressor), `sysctl hw.memsize`, `sysctl vm.swapusage` | none |

The app never runs as root, so the Python version's `task_read_for_pid` walker is not ported. That walker also descends into the shared system library cache, which this walk reports as a single region.

The status bar uses `top`'s "used" figure, so it agrees with the Python version.

`ps` and `top` are setuid, so they cover root-owned processes without `sudo`. The app runs them only for processes the direct calls could not read.

From the environment the app reads `CLAUDE_CODE_SESSION_ID`, `PWD`, and `XPC_SERVICE_NAME`, and nothing else. It never displays or stores other environment variables.

Command lines are cut to 4,000 characters.

## Memory accounting

The shared-split classification must match `collector.py`'s `_Regions.add`:

- Private: share mode `SM_PRIVATE`, `SM_PRIVATE_ALIASED` or `SM_LARGE_PAGE`; `SM_COW` with a reference count of 1; or an object ID of 0.
- `SM_COW` with more references: `pages_shared_now_private` counts as private, the remaining resident pages as shared.
- `SM_SHARED`, `SM_TRUESHARED`, `SM_SHARED_ALIASED`: shared.
- `SM_EMPTY`: ignored.
- Each shared object's resident and compressed pages are divided evenly among the processes that map it in the same snapshot.
- "Largest shared region also in N other processes" uses the shared object with the most resident bytes for that process.

Pages are counted in the host page size.

## Behavior

### Toolbar

- Mode: RSS, Shared split, Footprint.
- "Include compressed" checkbox. Footprint already includes compressed memory, so in that mode the box is checked and disabled.
- Group by: Process tree, App, Claude session.
- Refresh interval in seconds, minimum 0.5, plus Pause/Resume.
- Status: memory used of total, compressor size, swap used of total, process count, inspected count in Shared split, and the last collection time.

### Value of a process

| Mode | Value | Hatched part |
|-|-|-|
| RSS | RSS, plus compressed if checked | compressed, if checked |
| Shared split | private resident + shared split, plus private and split compressed if checked; RSS for uninspected processes | the compressed part, if checked |
| Footprint | footprint | min(compressed, footprint) |

Uninspected processes in Shared split get a dashed outline.

### Grouping

- **Process tree:** nest by parent PID. A process with children becomes a group whose first child is "<name> (itself)".
- **App:** the outermost `.app` in the executable path. Otherwise the nearest ancestor's app. Otherwise "System (root)" for uid 0, "System services" for uid below 500, or "Other user processes". A single-process app is a plain box, not a group.
- **Claude session:** processes carrying a `CLAUDE_CODE_SESSION_ID`.
  - The session's root is the parent PID that most of its carriers share, excluding launchd and carriers whose parent has the same session.
  - Carriers whose parent isn't in the group are reattached under the root.
  - A carrier whose `XPC_SERVICE_NAME` starts with `application.` and differs from the root's was relaunched as an app, and falls back to App grouping.
  - The label is "Claude session <first 8 characters> · <last two path components of PWD>", with "(ended)" when no root is found.
  - Everything else uses App grouping.

### Treemap

- Squarified layout: the same algorithm as D3's `treemapSquarify`, with ratio φ. It doesn't need to match D3 pixel for pixel. Tests check properties: boxes tile their parent, never overlap, keep the size order, and have bounded aspect ratios.
- Groups get a 15-point header with the label "<name> · <size> (<process count>)" and 2 points of outer padding. Siblings get 1 point of inner padding.
- Boxes smaller than 2 × 2 points are skipped. Labels appear only when a box is at least 36 × 12 points, and the size line only when it is at least 26 points tall.
- Color: one hue per top-level group under the current zoom. Lightness increases with depth.
- Siblings are sorted by size, descending.

### Interaction

- Hover: the details panel follows the pointer unless a box is pinned.
- Click: pin the box. Click the same box again to unpin it. Clicking another box moves the pin.
- Double-click a group, or a box inside one: zoom into that group. The breadcrumb zooms back out.
- The parent PID in the details panel is a link. It selects and pins the parent, zooming out until the parent is visible.
- The pin and zoom path survive refreshes. A pin on an exited process clears.

### Details panel

- Name, then "PID · parent (link) · uid".
- The command line in a selectable, scrolling monospace block.
- "Counted here", or "Counted here, with children" for a process group, plus the change since the last refresh, hidden under 1 MB.
- RSS, compressed, footprint, and Claude session.
- In Shared split: private resident, shared resident, its split, and "Largest shared region also in N other processes".

### Persistence

Mode, compressed checkbox, grouping, and interval persist in `UserDefaults`.

## Build and launch

- `swift build -c release`, then `scripts/bundle.sh` assembles `memmap.app` with an `Info.plist` (bundle ID `io.github.thehesiod.memmap`) and an ad-hoc signature.
- `scripts/bundle.sh --install` copies it to `~/Applications`.

## Left to the builder

- How SwiftUI draws roughly 700 boxes and keeps hover responsive at a 2 s refresh. `Canvas` with hit-testing is one option, nested views another.
- Concurrency inside collection, after measuring. Threads made the Python region walk slower.
- App icon.
- Whether the Python version stays in the repo after the app reaches parity.
