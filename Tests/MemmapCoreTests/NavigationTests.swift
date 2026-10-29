import Testing

@testable import MemmapCore

private func placed(_ key: String, isGroup: Bool, ancestors: [String]) -> PlacedNode {
  PlacedNode(
    key: key, name: key, rect: .zero, depth: ancestors.count + 1, isGroup: isGroup, total: 1,
    compressed: 0, record: nil, ancestorKeys: ancestors)
}

@Test func pinToggles() {
  var n = Navigation(zoomPath: [], pinnedKey: nil, hoverKey: "pid:2")
  n.togglePin("pid:1"); #expect(n.detailsKey == "pid:1")
  n.togglePin("pid:3"); #expect(n.pinnedKey == "pid:3")
  n.togglePin("pid:3"); #expect(n.pinnedKey == nil && n.detailsKey == "pid:2")
}

@Test func selectParentOutsideZoomZoomsOut() {
  let tree = buildTree(
    [rec(pid: 1, ppid: 0, rss: 1), rec(pid: 5, ppid: 1, rss: 1), rec(pid: 6, ppid: 5, rss: 1)],
    grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:1", "pid:5"], pinnedKey: nil, hoverKey: nil)
  n.select(pid: 5, in: tree)
  #expect(n.pinnedKey == "pid:5" && n.zoomPath == ["pid:1"])
}

@Test func selectBelowZoomKeepsZoom() {
  let tree = buildTree(
    [rec(pid: 1, ppid: 0, rss: 1), rec(pid: 5, ppid: 1, rss: 1), rec(pid: 6, ppid: 5, rss: 1)],
    grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:1"], pinnedKey: nil, hoverKey: nil)
  n.select(pid: 5, in: tree)
  #expect(n.pinnedKey == "pid:5" && n.zoomPath == ["pid:1"])
}

@Test func selectMissingPidDoesNothing() {
  let tree = buildTree([rec(pid: 1, ppid: 0, rss: 1)], grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:1"], pinnedKey: "pid:1", hoverKey: nil)
  n.select(pid: 99, in: tree)
  #expect(n == Navigation(zoomPath: ["pid:1"], pinnedKey: "pid:1", hoverKey: nil))
}

@Test func reconcileDropsVanishedKeys() {
  let tree = buildTree([rec(pid: 1, ppid: 0, rss: 1)], grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:9", "pid:10"], pinnedKey: "pid:10", hoverKey: nil)
  n.reconcile(with: tree)
  #expect(n.zoomPath.isEmpty && n.pinnedKey == nil)
}

@Test func reconcileTruncatesAtFirstMissingKeyAndKeepsPin() {
  let tree = buildTree(
    [rec(pid: 1, ppid: 0, rss: 1), rec(pid: 5, ppid: 1, rss: 1), rec(pid: 6, ppid: 5, rss: 1)],
    grouping: .processTree, mode: .rss, includeCompressed: false)
  var n = Navigation(zoomPath: ["pid:1", "pid:5", "pid:77", "pid:6"], pinnedKey: "pid:6", hoverKey: nil)
  n.reconcile(with: tree)
  #expect(n.zoomPath == ["pid:1", "pid:5"] && n.pinnedKey == "pid:6")
}

@Test func zoomIntoGroupAppendsAncestorsAndSelf() {
  var n = Navigation(zoomPath: ["pid:1"], pinnedKey: nil, hoverKey: nil)
  n.zoom(into: placed("pid:5", isGroup: true, ancestors: ["pid:2"]))
  #expect(n.zoomPath == ["pid:1", "pid:2", "pid:5"])
}

@Test func zoomIntoLeafGoesToParent() {
  var n = Navigation(zoomPath: ["pid:1"], pinnedKey: nil, hoverKey: nil)
  n.zoom(into: placed("pid:6", isGroup: false, ancestors: ["pid:5"]))
  #expect(n.zoomPath == ["pid:1", "pid:5"])
}

@Test func zoomIntoDepthOneLeafDoesNothing() {
  var n = Navigation(zoomPath: ["pid:1"], pinnedKey: nil, hoverKey: nil)
  n.zoom(into: placed("pid:6", isGroup: false, ancestors: []))
  #expect(n.zoomPath == ["pid:1"])
}

@Test func focusNodeFollowsPathAndStopsAtMissingKey() {
  let tree = buildTree(
    [rec(pid: 1, ppid: 0, rss: 1), rec(pid: 5, ppid: 1, rss: 1)],
    grouping: .processTree, mode: .rss, includeCompressed: false)
  #expect(focusNode(of: tree, path: ["pid:1"]).id == "pid:1")
  #expect(focusNode(of: tree, path: ["pid:1", "nope"]).id == "pid:1")
  #expect(focusNode(of: tree, path: []).id == "root")
}
