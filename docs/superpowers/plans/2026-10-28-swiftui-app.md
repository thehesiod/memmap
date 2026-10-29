# memmap SwiftUI App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `memmap.app`, a native SwiftUI port of the Python memmap treemap, launchable from the Dock or Spotlight.

**Architecture:** A `MemmapCore` library holds collection, memory accounting, grouping, layout, and navigation state, with no UI imports, so it is unit-testable. A `Memmap` executable target holds the SwiftUI views and a `@MainActor` model that runs collection on a background actor. A shell script assembles and ad-hoc signs the `.app` bundle.

**Tech Stack:** Swift 6 language mode, SwiftUI, Swift Testing (`import Testing`), Darwin libproc/sysctl, `Foundation.Process` for `ps`/`top`/`sysctl`. No third-party packages.

**Spec:** `docs/swiftui-design.md`

## Global Constraints

- macOS 14 minimum: `platforms: [.macOS(.v14)]`. Builds on Apple silicon and Intel.
- `swift-tools-version:6.0`. Swift Package Manager only, no Xcode project.
- No third-party dependencies.
- No HTTP server, no open port, no Python dependency.
- Never runs as root. No `task_for_pid`/`task_read_for_pid`.
- Environment variables read: `CLAUDE_CODE_SESSION_ID`, `PWD`, `XPC_SERVICE_NAME` only. Never display or store others.
- Command lines truncated to 4,000 characters.
- Bundle ID `io.github.thehesiod.memmap`; app name `memmap`.
- No employer- or user-specific names, paths, or data anywhere, including fixtures. Fixtures use names like `Example.app`, `/Users/example/project`.
- Test command for every task: `swift test` from the repository root. Expected tail: `Test run with N tests … passed`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A process exits between listing and reading it: every reader returns `nil`, and collection skips it without throwing. Test in Task 4.
2. Parent cycles and self-parents (pid 0, `ppid == pid`): tree building and app inheritance terminate. Test in Task 3.
3. Zero-value and empty nodes in layout: no NaN or negative rects, and zero-value boxes are omitted. Test in Task 2.
4. A collection slower than the refresh interval (shared split takes about 7 s): collections never overlap, and the next one starts after the previous finishes. Test in Task 7.
5. Non-UTF-8 or huge command lines: lossy decoding, truncated to 4,000 characters, no crash. Test in Task 4.

## File Structure

| File | Responsibility |
|-|-|
| `Package.swift` | Targets `MemmapCore`, `Memmap`, `MemmapCoreTests` |
| `Sources/MemmapCore/Model.swift` | `ProcessRecord`, `SplitFigures`, `SystemTotals`, `Snapshot` |
| `Sources/MemmapCore/ToolParsers.swift` | Parse `ps`, `top`, `sysctl vm.swapusage` text; `parseSize`; `outermostApp` |
| `Sources/MemmapCore/Squarify.swift` | Squarified layout and nested treemap placement |
| `Sources/MemmapCore/Grouping.swift` | `Mode`, `Grouping`, per-mode values, `TreeNode` building |
| `Sources/MemmapCore/ProcArgs.swift` | `KERN_PROCARGS2` buffer parsing |
| `Sources/MemmapCore/LibProc.swift` | Direct libproc/sysctl readers |
| `Sources/MemmapCore/Regions.swift` | `RegionTally` classification, region walk, split computation |
| `Sources/MemmapCore/Collector.swift` | `Collector` actor that merges every source into a `Snapshot` |
| `Sources/MemmapCore/Navigation.swift` | Zoom path, pin, hover, select-parent logic |
| `Sources/Memmap/MemmapApp.swift` | `@main` app and window |
| `Sources/Memmap/AppModel.swift` | Settings, refresh loop, snapshot, previous values |
| `Sources/Memmap/TreemapView.swift` | `Canvas` drawing, hit-testing, gestures |
| `Sources/Memmap/ToolbarView.swift` | Mode, compressed, grouping, interval, pause, status |
| `Sources/Memmap/DetailsPanel.swift` | Details panel and breadcrumb |
| `Resources/Info.plist` | Bundle metadata |
| `scripts/bundle.sh` | Build, assemble, sign, and optionally install |
| `Tests/MemmapCoreTests/*.swift` | One test file per core source file |

---

### Task 1: Package scaffold, model, and tool parsers

**Files:**
- Create: `Package.swift`, `Sources/MemmapCore/Model.swift`, `Sources/MemmapCore/ToolParsers.swift`, `Sources/Memmap/MemmapApp.swift` (placeholder window showing "memmap"), `Tests/MemmapCoreTests/ToolParsersTests.swift`
- Modify: `.gitignore` (already ignores `.build/` and `*.app/`; verify)

**Interfaces:**
- Produces:
  - `public struct ProcessRecord: Sendable, Hashable { pid: Int32; ppid: Int32; uid: UInt32; name: String; path: String; args: String; app: String?; session: String?; cwd: String?; xpcService: String?; rss: Int64; footprint: Int64; compressed: Int64; split: SplitFigures? }`
  - `public struct SplitFigures: Sendable, Hashable { privateResident, privateCompressed, sharedResident, sharedSplit, sharedCompressedSplit: Int64; largestSharedAlsoIn: Int }`
  - `public struct SystemTotals: Sendable, Hashable { used, compressor, physical, swapUsed, swapTotal: Int64 }`
  - `public struct Snapshot: Sendable { processes: [ProcessRecord]; system: SystemTotals; inspected: Int; collectedIn: Duration }`
  - `public struct PSRow: Sendable, Hashable { ppid: Int32; uid: UInt32; rss: Int64; comm: String }`
  - `public func parseSize(_ text: String) -> Int64`
  - `public func parsePS(_ output: String) -> [Int32: PSRow]` for `ps -axo pid=,ppid=,uid=,rss=,comm=` (rss in KiB → bytes)
  - `public func parsePSArgs(_ output: String) -> [Int32: String]` for `ps -axww -o pid=,args=`, truncated to 4,000 characters
  - `public func parseTop(_ output: String) -> (perPID: [Int32: (footprint: Int64, compressed: Int64)], used: Int64, compressor: Int64)` for `top -l 1 -stats pid,mem,cmprs`
  - `public func parseSwapUsage(_ line: String) -> (used: Int64, total: Int64)`
  - `public func outermostApp(path: String) -> String?`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import MemmapCore

@Test func parsesTopSizes() {
  #expect(parseSize("88M") == 88 << 20)
  #expect(parseSize("7873K") == 7873 << 10)
  #expect(parseSize("23G") == 23 << 30)
  #expect(parseSize("0B") == 0)
  #expect(parseSize("1472M+") == 1472 << 20)
  #expect(parseSize("-") == 0)
}

@Test func parsesPSWithSpacesInCommand() {
  let rows = parsePS("    1     0     0  15056 /sbin/launchd\n  612     1   501  117760 /Applications/Example App.app/Contents/MacOS/Example App\n")
  #expect(rows[612] == PSRow(ppid: 1, uid: 501, rss: 117760 * 1024, comm: "/Applications/Example App.app/Contents/MacOS/Example App"))
}

@Test func parsesTopTableAndPhysMem() {
  let out = """
  PhysMem: 47G used (5480M wired, 23G compressor), 154M unused.
  PID    MEM   CMPRS
  5230   23G   14G
  35000  1472M 672M
  """
  let top = parseTop(out)
  #expect(top.used == 47 << 30 && top.compressor == 23 << 30)
  #expect(top.perPID[35000]?.footprint == 1472 << 20 && top.perPID[35000]?.compressed == 672 << 20)
}

@Test func parsesSwap() {
  let swap = parseSwapUsage("total = 6144.00M  used = 4885.00M  free = 1259.00M  (encrypted)")
  #expect(swap.total == 6144 << 20 && swap.used == 4885 << 20)
}

@Test func findsOutermostApp() {
  #expect(outermostApp(path: "/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper") == "Example")
  #expect(outermostApp(path: "/usr/libexec/logd") == nil)
}

@Test func truncatesArgs() {
  let long = String(repeating: "x", count: 5000)
  #expect(parsePSArgs("  42 \(long)\n")[42]?.count == 4000)
}
```

- [ ] **Step 2: Run `swift test` and verify it fails** — Expected: compile errors for the missing symbols.

- [ ] **Step 3: Implement the model and parsers** with the signatures above. `parseSize` accepts a decimal number, then an optional `B/K/M/G/T` unit, ignoring a trailing `+` or `-`. Anything unparsable is 0. `parsePS` splits each line into at most five fields, so `comm` keeps its spaces.

- [ ] **Step 4: Run `swift test`** — Expected: all tests pass. Also run `swift build` and check that the `Memmap` target compiles.

- [ ] **Step 5: Commit** — `git add Package.swift Sources Tests .gitignore && git commit -m "Add Swift package with model and tool output parsers"`

---

### Task 2: Squarified treemap layout

**Files:**
- Create: `Sources/MemmapCore/Squarify.swift`, `Tests/MemmapCoreTests/SquarifyTests.swift`

**Interfaces:**
- Consumes: `TreeNode` from Task 3. Define `TreeNode` here, since Task 3 builds instances of it:
  - `public struct TreeNode: Sendable, Identifiable { public let id: String /* key */; name: String; record: ProcessRecord?; value: Int64; compressed: Int64; children: [TreeNode] }`, with a stored property `total: Int64` set in `init(id:name:record:value:compressed:children:)` (the value for leaves, the sum of the children's totals for groups) and a computed `isGroup: Bool { !children.isEmpty }`
- Produces:
  - `public func squarify(_ values: [Double], in rect: CGRect, ratio: Double = (1 + 5.squareRoot()) / 2) -> [CGRect]`: same order as `values`; values must be sorted descending by the caller.
  - `public struct PlacedNode: Sendable { key: String; name: String; rect: CGRect; depth: Int; isGroup: Bool; total: Int64; compressed: Int64; record: ProcessRecord?; ancestorKeys: [String] /* from below the layout root down to the parent */ }`
  - `public func layoutTreemap(_ root: TreeNode, in rect: CGRect, headerHeight: CGFloat = 15, outerPadding: CGFloat = 2, innerPadding: CGFloat = 1) -> [PlacedNode]`: excludes the root itself, omits children with `total <= 0` and rects under 2 × 2 points, and sorts siblings by `total` descending.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func squarifyTilesWithoutOverlap() {
  let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
  let values: [Double] = [500, 300, 120, 50, 20, 10]
  let rects = squarify(values, in: rect)
  #expect(rects.count == values.count)
  let area = rects.reduce(0) { $0 + $1.width * $1.height }
  #expect(abs(area - 400 * 300) < 1)
  for (i, a) in rects.enumerated() { for b in rects[(i + 1)...] { #expect(a.intersection(b).width * a.intersection(b).height < 0.5) } }
  for (r, v) in zip(rects, values) { #expect(abs(r.width * r.height / (400 * 300) - v / 1000) < 0.001) }
  for r in rects { #expect(max(r.width / r.height, r.height / r.width) < 6) }
}

@Test func squarifyHandlesZeroAndEmpty() {
  #expect(squarify([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
  let rects = squarify([5, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10))
  #expect(rects.allSatisfy { !$0.width.isNaN && !$0.height.isNaN && $0.width >= 0 && $0.height >= 0 })
}

@Test func nestedLayoutReservesHeaderAndOmitsZero() {
  let leaf = { (k: String, v: Int64) in TreeNode(id: k, name: k, record: nil, value: v, compressed: 0, children: []) }
  let group = TreeNode(id: "app:A", name: "A", record: nil, value: 0, compressed: 0, children: [leaf("pid:1", 60), leaf("pid:2", 40), leaf("pid:3", 0)])
  let root = TreeNode(id: "root", name: "All", record: nil, value: 0, compressed: 0, children: [group, leaf("pid:4", 100)])
  let placed = layoutTreemap(root, in: CGRect(x: 0, y: 0, width: 400, height: 200))
  #expect(placed.map(\.key).sorted() == ["app:A", "pid:1", "pid:2", "pid:4"])
  let g = placed.first { $0.key == "app:A" }!, p1 = placed.first { $0.key == "pid:1" }!
  #expect(p1.rect.minY >= g.rect.minY + 15 && g.rect.contains(p1.rect))
  #expect(p1.ancestorKeys == ["app:A"] && p1.depth == 2)
}
```

- [ ] **Step 2: Run `swift test`** — Expected: FAIL, undefined `squarify`.

- [ ] **Step 3: Implement.** Use the Bruls/Huizing/van Wijk squarify. Lay rows along the shorter side, and add items to a row while the worst aspect ratio, weighted by `ratio` as in D3's `squarifyRatio`, does not get worse. Skip zero values in the row algorithm and return `.zero` rects for them. `layoutTreemap` recurses: a group's content rect is its rect inset by `outerPadding`, with `headerHeight` taken from the top for depth ≥ 1. Siblings are separated by `innerPadding`: inset each child rect by `innerPadding / 2`.

- [ ] **Step 4: Run `swift test`** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "Add squarified treemap layout"`

---

### Task 3: Per-mode values and grouping

**Files:**
- Create: `Sources/MemmapCore/Grouping.swift`, `Tests/MemmapCoreTests/GroupingTests.swift`, `Tests/MemmapCoreTests/Fixtures.swift` (the `rec` helper, shared with Task 7's tests)

**Interfaces:**
- Consumes: `ProcessRecord`, `SplitFigures` (Task 1); `TreeNode` (Task 2).
- Produces:
  - `public enum Mode: String, CaseIterable, Sendable { case rss, sharedSplit, footprint }`
  - `public enum Grouping: String, CaseIterable, Sendable { case processTree, app, claudeSession }`
  - `public func measure(_ p: ProcessRecord, mode: Mode, includeCompressed: Bool) -> (value: Int64, compressed: Int64)`, per the spec's "Value of a process" table
  - `public func buildTree(_ records: [ProcessRecord], grouping: Grouping, mode: Mode, includeCompressed: Bool) -> TreeNode`. The root key is `"root"`, named "All processes". Other keys: `"pid:<n>"`, `"self:<n>"`, `"app:<name>"`, `"session:<id>"`.

- [ ] **Step 1: Write the failing tests.** The fixture helper `rec(pid:ppid:uid:path:rss:session:xpc:cwd:)` builds records with `footprint = rss`, `compressed = 10`, and `split = nil` unless given.

```swift
@Test func measuresEachMode() {
  var p = rec(pid: 1, ppid: 0, rss: 100); p.footprint = 150; p.compressed = 30
  #expect(measure(p, mode: .rss, includeCompressed: true) == (130, 30))
  #expect(measure(p, mode: .rss, includeCompressed: false) == (100, 0))
  #expect(measure(p, mode: .footprint, includeCompressed: false) == (150, 30))
  p.split = SplitFigures(privateResident: 50, privateCompressed: 5, sharedResident: 400, sharedSplit: 20, sharedCompressedSplit: 2, largestSharedAlsoIn: 3)
  #expect(measure(p, mode: .sharedSplit, includeCompressed: true) == (77, 7))
  p.split = nil
  #expect(measure(p, mode: .sharedSplit, includeCompressed: false) == (100, 0))
}

@Test func processTreeAddsItselfChildAndSurvivesCycles() {
  let tree = buildTree([rec(pid: 1, ppid: 0, rss: 10), rec(pid: 2, ppid: 1, rss: 20), rec(pid: 3, ppid: 3, rss: 5), rec(pid: 0, ppid: 0, rss: 1)], grouping: .processTree, mode: .rss, includeCompressed: false)
  let p1 = tree.children.first { $0.id == "pid:1" }!
  #expect(p1.children.map(\.id) == ["self:1", "pid:2"] && p1.children[0].name.hasSuffix("(itself)"))
  #expect(tree.children.contains { $0.id == "pid:3" } && tree.children.contains { $0.id == "pid:0" })
}

@Test func appGroupingInheritsFromAncestorsAndFallsBack() {
  let recs = [
    rec(pid: 10, ppid: 1, uid: 501, path: "/Applications/Example.app/Contents/MacOS/Example", rss: 50),
    rec(pid: 11, ppid: 10, uid: 501, path: "/usr/bin/helper", rss: 5),
    rec(pid: 20, ppid: 1, uid: 0, path: "/usr/libexec/daemon", rss: 5),
    rec(pid: 21, ppid: 1, uid: 200, path: "/usr/libexec/svc", rss: 5),
    rec(pid: 22, ppid: 1, uid: 501, path: "/usr/bin/tool", rss: 5),
    rec(pid: 22_000, ppid: 22_000, uid: 501, path: "/x", rss: 1),
  ]
  let names = Set(buildTree(recs, grouping: .app, mode: .rss, includeCompressed: false).children.map(\.name))
  #expect(names.isSuperset(of: ["Example", "System (root)", "System services"]))
  let example = buildTree(recs, grouping: .app, mode: .rss, includeCompressed: false).children.first { $0.name == "Example" }!
  #expect(Set(example.children.map(\.id)) == ["pid:10", "pid:11"])
}

@Test func claudeSessionReattachesOrphansAndExcludesRelaunchedApps() {
  let s = "0123abcd-0000-0000-0000-000000000000"
  let recs = [
    rec(pid: 100, ppid: 1, path: "/usr/local/bin/claude", rss: 300, xpc: "0"),
    rec(pid: 101, ppid: 100, path: "/bin/zsh", rss: 5, session: s, xpc: "0", cwd: "/Users/example/project"),
    rec(pid: 102, ppid: 1, path: "/bin/bash", rss: 7, session: s, xpc: "0"),
    rec(pid: 103, ppid: 1, path: "/Applications/Example.app/Contents/MacOS/Example", rss: 900, session: s, xpc: "application.com.example.app.1.2"),
  ]
  let tree = buildTree(recs, grouping: .claudeSession, mode: .rss, includeCompressed: false)
  let session = tree.children.first { $0.id == "session:\(s)" }!
  #expect(session.name == "Claude session 0123abcd · example/project")
  let root = session.children.first { $0.id == "pid:100" }!
  #expect(Set(root.children.map(\.id)) == ["self:100", "pid:101", "pid:102"])
  #expect(tree.children.contains { $0.id == "pid:103" || $0.name == "Example" })
}
```

- [ ] **Step 2: Run `swift test`** — Expected: FAIL, undefined `buildTree`.

- [ ] **Step 3: Implement** using the rules in the spec's "Grouping" section. Port `buildTree`, `buildApps`, `appOf` (hop limit 64), `forest` and `buildSessions` from `index.html`. Children are not sorted here; layout sorts them.

- [ ] **Step 4: Run `swift test`** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "Add per-mode values and process grouping"`

---

### Task 4: Direct process readers

**Files:**
- Create: `Sources/MemmapCore/ProcArgs.swift`, `Sources/MemmapCore/LibProc.swift`, `Tests/MemmapCoreTests/LibProcTests.swift`

**Interfaces:**
- Produces:
  - `public struct ProcArgs: Sendable { args: String; env: [String: String] }` holding only the three allowed variables
  - `public func parseProcArgs2(_ buffer: [UInt8]) -> ProcArgs?`
  - `enum LibProc` with static functions, each returning `nil` when the process is gone or unreadable:
    - `listPIDs() -> [Int32]`
    - `bsdInfo(_ pid: Int32) -> (ppid: Int32, uid: UInt32)?`
    - `residentSize(_ pid: Int32) -> Int64?`
    - `physFootprint(_ pid: Int32) -> Int64?`
    - `executablePath(_ pid: Int32) -> String?`
    - `procArgs(_ pid: Int32) -> ProcArgs?`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func parsesProcArgs2Layout() {
  var buf: [UInt8] = withUnsafeBytes(of: Int32(2).littleEndian, Array.init)
  for s in ["/bin/tool", "", "", "/bin/tool", "--flag", "PWD=/Users/example/project", "SECRET=x", "CLAUDE_CODE_SESSION_ID=abc", "XPC_SERVICE_NAME=0", ""] { buf += Array(s.utf8) + [0] }
  let parsed = parseProcArgs2(buf)!
  #expect(parsed.args == "/bin/tool --flag")
  #expect(parsed.env == ["PWD": "/Users/example/project", "CLAUDE_CODE_SESSION_ID": "abc", "XPC_SERVICE_NAME": "0"])
}

@Test func procArgs2SurvivesGarbageAndHugeArgs() {
  #expect(parseProcArgs2([1, 2]) == nil)
  var buf: [UInt8] = withUnsafeBytes(of: Int32(1).littleEndian, Array.init) + Array("/x".utf8) + [0, 0xff, 0xfe] + Array(repeating: UInt8(ascii: "a"), count: 6000) + [0]
  buf += [0]
  #expect((parseProcArgs2(buf)?.args.count ?? 0) <= 4000)
}

@Test func readsOwnProcess() {
  let me = getpid()
  #expect(LibProc.listPIDs().contains(me))
  #expect(LibProc.bsdInfo(me)?.uid == getuid())
  #expect((LibProc.residentSize(me) ?? 0) > 0 && (LibProc.physFootprint(me) ?? 0) > 0)
  #expect(LibProc.executablePath(me)?.isEmpty == false)
  #expect(LibProc.procArgs(me)?.args.isEmpty == false)
}

@Test func vanishedProcessReturnsNil() {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try! p.run(); p.waitUntilExit()
  #expect(LibProc.bsdInfo(p.processIdentifier) == nil && LibProc.procArgs(p.processIdentifier) == nil)
}
```

- [ ] **Step 2: Run `swift test`** — Expected: FAIL.

- [ ] **Step 3: Implement.**
  - `KERN_PROCARGS2` layout: an `Int32` argc, then the NUL-terminated exec path, then NUL padding, then argc NUL-terminated args, then env strings until an empty string or the end of the buffer.
  - Decode lossily with `String(decoding:as: UTF8.self)`. Join args with spaces and truncate to 4,000 characters.
  - `bsdInfo` uses `PROC_PIDTBSDINFO`. `residentSize` uses `PROC_PIDTASKINFO`'s `pti_resident_size`. `physFootprint` uses `proc_pid_rusage(RUSAGE_INFO_V4)`'s `ri_phys_footprint`.
  - `listPIDs` calls `proc_listallpids` twice: first for the count, then with 2× headroom.

- [ ] **Step 4: Run `swift test`** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "Add direct libproc and procargs readers"`

---

### Task 5: Region walk and shared split

**Files:**
- Create: `Sources/MemmapCore/Regions.swift`, `Tests/MemmapCoreTests/RegionsTests.swift`

**Interfaces:**
- Consumes: `SplitFigures` (Task 1).
- Produces:
  - `public struct RegionTally: Sendable { privateResident: Int64; privateCompressed: Int64; shared: [UInt64: (resident: Int64, compressed: Int64)]; mutating func add(shareMode: UInt32, refCount: UInt32, objectID: UInt64, residentPages: UInt32, nowPrivatePages: UInt32, compressedPages: UInt32, pageSize: Int64) }`
  - `public func walkRegions(pid: Int32) -> RegionTally?` using `proc_pidinfo(PROC_PIDREGIONINFO)`
  - `public func splitFigures(_ tallies: [Int32: RegionTally]) -> [Int32: SplitFigures]`

- [ ] **Step 1: Write the failing tests.** The share-mode constants are `SM_COW=1, SM_PRIVATE=2, SM_EMPTY=3, SM_SHARED=4, SM_TRUESHARED=5, SM_PRIVATE_ALIASED=6, SM_SHARED_ALIASED=7, SM_LARGE_PAGE=8`.

```swift
@Test func classifiesRegions() {
  var t = RegionTally()
  t.add(shareMode: 2, refCount: 1, objectID: 7, residentPages: 10, nowPrivatePages: 0, compressedPages: 2, pageSize: 1)
  t.add(shareMode: 1, refCount: 1, objectID: 8, residentPages: 4, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  t.add(shareMode: 1, refCount: 3, objectID: 9, residentPages: 6, nowPrivatePages: 2, compressedPages: 1, pageSize: 1)
  t.add(shareMode: 4, refCount: 2, objectID: 0, residentPages: 5, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  t.add(shareMode: 5, refCount: 2, objectID: 10, residentPages: 8, nowPrivatePages: 0, compressedPages: 3, pageSize: 1)
  t.add(shareMode: 3, refCount: 0, objectID: 11, residentPages: 99, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  #expect(t.privateResident == 10 + 4 + 2 + 5 && t.privateCompressed == 2)
  #expect(t.shared[9]! == (4, 1) && t.shared[10]! == (8, 3) && t.shared[11] == nil)
}

@Test func splitsSharedObjectsEvenly() {
  var a = RegionTally(), b = RegionTally()
  a.add(shareMode: 4, refCount: 2, objectID: 1, residentPages: 100, nowPrivatePages: 0, compressedPages: 10, pageSize: 1)
  a.add(shareMode: 4, refCount: 1, objectID: 2, residentPages: 30, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  b.add(shareMode: 4, refCount: 2, objectID: 1, residentPages: 100, nowPrivatePages: 0, compressedPages: 10, pageSize: 1)
  let f = splitFigures([1: a, 2: b])
  #expect(f[1]!.sharedSplit == 50 + 30 && f[1]!.sharedCompressedSplit == 5 && f[1]!.sharedResident == 130)
  #expect(f[1]!.largestSharedAlsoIn == 1 && f[2]!.sharedSplit == 50)
}

@Test func walksOwnProcess() {
  let t = walkRegions(pid: getpid())!
  #expect(t.privateResident > 0)
  #expect(walkRegions(pid: 1) == nil)
}
```

- [ ] **Step 2: Run `swift test`** — Expected: FAIL.

- [ ] **Step 3: Implement.** Port the classification from `collector.py` `_Regions.add`, and define `proc_regioninfo`'s layout from the Python struct `_ProcRegionInfo`. Walk from address 0, advance to `pri_address + pri_size`, and stop when `proc_pidinfo` returns ≤ 0 or the address does not advance. Return `nil` when the first call fails. Use `vm_page_size` for `pageSize`.

- [ ] **Step 4: Run `swift test`** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "Add region walk and shared-split accounting"`

---

### Task 6: Collector

**Files:**
- Create: `Sources/MemmapCore/Collector.swift`, `Tests/MemmapCoreTests/CollectorTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 4, 5.
- Produces: `public actor Collector { public init(); public func collect(split: Bool) async throws -> Snapshot }`

- [ ] **Step 1: Write the failing test**

```swift
@Test func collectsLiveSnapshot() async throws {
  let snap = try await Collector().collect(split: true)
  let me = try #require(snap.processes.first { $0.pid == getpid() })
  #expect(me.rss > 0 && me.footprint > 0 && !me.args.isEmpty && me.split != nil)
  #expect(snap.processes.contains { $0.pid == 1 && $0.split == nil && $0.rss > 0 })
  #expect(snap.system.physical > 0 && snap.system.used > 0)
  #expect(snap.inspected > 0 && snap.inspected < snap.processes.count)
}
```

- [ ] **Step 2: Run `swift test`** — Expected: FAIL.

- [ ] **Step 3: Implement.**
  - Run `ps -axo pid=,ppid=,uid=,rss=,comm=`, `ps -axww -o pid=,args=`, `top -l 1 -stats pid,mem,cmprs`, and `sysctl -n vm.swapusage hw.memsize` concurrently through `Foundation.Process`.
  - For each `ps` row, prefer the direct readers from Task 4 and fall back to the tool figures.
  - Take compressed from `top` for all processes.
  - When `split` is set, walk regions for every PID, compute `splitFigures`, and set `inspected` to the number of tallies.
  - Measure `collectedIn` with `ContinuousClock`.

- [ ] **Step 4: Run `swift test`** — Expected: PASS.

- [ ] **Step 5: Commit** — `git commit -m "Add collector merging direct reads and tool output"`

---

### Task 7: Navigation state and refresh loop

**Files:**
- Create: `Sources/MemmapCore/Navigation.swift`, `Sources/Memmap/AppModel.swift`, `Tests/MemmapCoreTests/NavigationTests.swift`

**Interfaces:**
- Consumes: `TreeNode` (Task 2), `buildTree` (Task 3), `Collector` (Task 6).
- Produces:
  - `public struct Navigation: Sendable, Equatable { public var zoomPath: [String]; public var pinnedKey: String?; public var hoverKey: String? }` with:
    - `mutating func togglePin(_ key: String)`
    - `mutating func zoom(into placed: PlacedNode)`: a group zooms into itself, a leaf into its parent, and nothing happens at the root
    - `mutating func select(pid: Int32, in tree: TreeNode)`: pins `pid:<n>`, and resets `zoomPath` to the target's ancestors when the target isn't strictly below the current zoom
    - `mutating func reconcile(with tree: TreeNode)`: truncates `zoomPath` at the first missing key and clears `pinnedKey` if it's gone
    - `var detailsKey: String? { pinnedKey ?? hoverKey }`
    - `public func focusNode(of tree: TreeNode, path: [String]) -> TreeNode`
  - `@MainActor @Observable final class AppModel`:
    - properties `mode`, `includeCompressed`, `grouping`, `interval: Double`, `paused`, persisted to `UserDefaults` keys `mode`, `includeCompressed`, `grouping`, `interval`
    - `snapshot: Snapshot?`, `tree: TreeNode?`, `previousTotals: [String: Int64]`, `navigation: Navigation`, `lastError: String?`
    - `func start()` and `func refreshNow()`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func pinToggles() {
  var n = Navigation(zoomPath: [], pinnedKey: nil, hoverKey: "pid:2")
  n.togglePin("pid:1"); #expect(n.detailsKey == "pid:1")
  n.togglePin("pid:3"); #expect(n.pinnedKey == "pid:3")
  n.togglePin("pid:3"); #expect(n.pinnedKey == nil && n.detailsKey == "pid:2")
}

@Test func selectParentOutsideZoomZoomsOut() {
  let tree = buildTree([rec(pid: 1, ppid: 0, rss: 1), rec(pid: 5, ppid: 1, rss: 1), rec(pid: 6, ppid: 5, rss: 1)], grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:1", "pid:5"], pinnedKey: nil, hoverKey: nil)
  n.select(pid: 5, in: tree)
  #expect(n.pinnedKey == "pid:5" && n.zoomPath == ["pid:1"])
}

@Test func reconcileDropsVanishedKeys() {
  let tree = buildTree([rec(pid: 1, ppid: 0, rss: 1)], grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:9", "pid:10"], pinnedKey: "pid:10", hoverKey: nil)
  n.reconcile(with: tree)
  #expect(n.zoomPath.isEmpty && n.pinnedKey == nil)
}
```

- [ ] **Step 2: Run `swift test`** — Expected: FAIL.

- [ ] **Step 3: Implement `Navigation`, then `AppModel`.**
  - The refresh loop is one `Task` that awaits `collect`, publishes the result, then sleeps for `interval`. A collection therefore never overlaps the previous one (Review Focus 4).
  - Changing `mode` into or out of `.sharedSplit` cancels the sleep and refreshes at once. Other setting changes only rebuild the tree.
  - `previousTotals` holds the prior tree's totals by key. It resets when the mode, the compressed setting, or the grouping changes.

- [ ] **Step 4: Run `swift test`** — Expected: PASS. Then run `swift build`.

- [ ] **Step 5: Commit** — `git commit -m "Add navigation state and refresh loop"`

---

### Task 8: SwiftUI views, bundle, and manual verification

**Files:**
- Create: `Sources/Memmap/TreemapView.swift`, `Sources/Memmap/ToolbarView.swift`, `Sources/Memmap/DetailsPanel.swift`, `Resources/Info.plist`, `scripts/bundle.sh`
- Modify: `Sources/Memmap/MemmapApp.swift`; `README.md` (create, covering what memmap is, `scripts/bundle.sh --install`, and the shared-split coverage note)

**Interfaces:**
- Consumes: `AppModel`, `Navigation`, `layoutTreemap`, `PlacedNode`.

- [ ] **Step 1: Build the views to the spec's "Behavior" section.**
  - `TreemapView`:
    - Draw `layoutTreemap(focusNode, in: size)` in a `Canvas`.
    - Hit-test by taking the deepest `PlacedNode` containing the pointer.
    - `.onContinuousHover` sets `hoverKey`. A single click calls `togglePin`. A double-click calls `zoom(into:)`.
    - Hatching covers `compressed / total` of each leaf's height, from the bottom. Uninspected leaves in Shared split get a dashed outline.
    - Colors: one hue per depth-1 group, and lightness `min(0.9, 0.62 + 0.07 × (depth − 1) + (leaf ? 0.06 : 0))`.
  - `ToolbarView`:
    - controls and status text as in the spec
    - the compressed checkbox is checked and disabled in Footprint
    - the interval field rejects values under 0.5
  - `DetailsPanel`:
    - rows as in the spec, with the change shown only when its magnitude is ≥ 1 MB
    - the parent PID is a `Button` calling `select(pid:in:)`
    - the command line in a `ScrollView` with `.textSelection(.enabled)` and a monospaced font
    - the breadcrumb above the map
  - The window opens at a default size of 1200 × 800.

- [ ] **Step 2: Write `scripts/bundle.sh`.**
  - It runs `swift build -c release`, creates `memmap.app/Contents/{MacOS,Resources}`, copies the binary and `Resources/Info.plist`, and runs `codesign --force --sign - memmap.app`.
  - `--install` also copies the bundle to `~/Applications`, replacing an existing copy.
  - `Info.plist` sets:
    - `CFBundleIdentifier` `io.github.thehesiod.memmap`
    - `CFBundleName` and `CFBundleExecutable` `memmap`
    - `LSMinimumSystemVersion` `14.0`
    - `NSHighResolutionCapable` true

- [ ] **Step 3: Verify.**
  - Run `scripts/bundle.sh --install`, then `open ~/Applications/memmap.app`. Expected: the window shows the treemap within about 2 s.
  - Check each item against the Python version running on the same machine:
    - All three modes and all three groupings render.
    - The status bar's used figure matches `top`'s.
    - The details panel stays on the pinned box while hovering others.
    - A double-click zooms in, and the breadcrumb zooms out.
    - The parent link selects the parent.
    - Shared split shows dashed outlines on root-owned processes and refreshes without freezing the UI.
    - Settings persist after quitting and relaunching.
  - Run `swift test`. Expected: all tests pass.

- [ ] **Step 4: Audit and commit.**
  - Review `git diff main --stat` and the full diff for employer- or user-specific names, paths, and data, per Global Constraints. Fix anything found before committing.
  - Then `git add Sources Resources scripts README.md && git commit -m "Add SwiftUI views and app bundle script"`.
