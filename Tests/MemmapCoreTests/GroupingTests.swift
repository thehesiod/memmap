import Testing

@testable import MemmapCore

func leafPids(_ node: TreeNode) -> [Int32] {
  guard node.children.isEmpty else { return node.children.flatMap(leafPids) }
  guard let pid = node.id.split(separator: ":").last.flatMap({ Int32($0) }) else { return [] }
  return [pid]
}

func expectEachPidOnce(_ tree: TreeNode, _ recs: [ProcessRecord]) {
  #expect(leafPids(tree).sorted() == recs.map(\.pid).sorted())
}

@Test func measuresEachMode() {
  var p = rec(pid: 1, ppid: 0, rss: 100)
  p.footprint = 150
  p.compressed = 30
  #expect(measure(p, mode: .rss, includeCompressed: true) == (130, 30))
  #expect(measure(p, mode: .rss, includeCompressed: false) == (100, 0))
  #expect(measure(p, mode: .footprint, includeCompressed: false) == (150, 30))
  p.split = SplitFigures(
    privateResident: 50, privateCompressed: 5, sharedResident: 400, sharedSplit: 20,
    sharedCompressedSplit: 2, largestSharedAlsoIn: 3)
  #expect(measure(p, mode: .sharedSplit, includeCompressed: true) == (77, 7))
  p.split = nil
  #expect(measure(p, mode: .sharedSplit, includeCompressed: false) == (100, 0))
}

@Test func processTreeAddsItselfChildAndSurvivesCycles() {
  let recs = [
    rec(pid: 1, ppid: 0, rss: 10), rec(pid: 2, ppid: 1, rss: 20),
    rec(pid: 3, ppid: 3, rss: 5), rec(pid: 0, ppid: 0, rss: 1),
    rec(pid: 7, ppid: 8, rss: 2), rec(pid: 8, ppid: 7, rss: 3),
  ]
  let tree = buildTree(recs, grouping: .processTree, mode: .rss, includeCompressed: false)
  expectEachPidOnce(tree, recs)
  let p1 = tree.children.first { $0.id == "pid:0" }!.children.first { $0.id == "pid:1" }!
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
    rec(pid: 23, ppid: 1, uid: 0, path: "/usr/libexec/daemon2", rss: 5),
    rec(pid: 24, ppid: 1, uid: 200, path: "/usr/libexec/svc2", rss: 5),
    rec(pid: 22_000, ppid: 22_000, uid: 501, path: "/x", rss: 1),
  ]
  let tree = buildTree(recs, grouping: .app, mode: .rss, includeCompressed: false)
  let names = Set(tree.children.map(\.name))
  #expect(names.isSuperset(of: ["Example", "System (root)", "System services"]))
  let example = tree.children.first { $0.name == "Example" }!
  #expect(Set(example.children.map(\.id)) == ["pid:10", "pid:11"])
}

@Test func claudeSessionReattachesOrphansAndExcludesRelaunchedApps() {
  let s = "0123abcd-0000-0000-0000-000000000000"
  let recs = [
    rec(pid: 100, ppid: 1, path: "/usr/local/bin/claude", rss: 300, xpc: "0"),
    rec(pid: 101, ppid: 100, path: "/bin/zsh", rss: 5, session: s, xpc: "0", cwd: "/Users/example/project"),
    rec(pid: 102, ppid: 1, path: "/bin/bash", rss: 7, session: s, xpc: "0"),
    rec(
      pid: 103, ppid: 1, path: "/Applications/Example.app/Contents/MacOS/Example", rss: 900,
      session: s, xpc: "application.com.example.app.1.2"),
  ]
  let tree = buildTree(recs, grouping: .claudeSession, mode: .rss, includeCompressed: false)
  let session = tree.children.first { $0.id == "session:\(s)" }!
  #expect(session.name == "Claude session 0123abcd · example/project")
  let root = session.children.first { $0.id == "pid:100" }!
  #expect(Set(root.children.map(\.id)) == ["self:100", "pid:101", "pid:102"])
  #expect(tree.children.contains { $0.id == "pid:103" })
  #expect(!tree.children.contains { $0.id == "app:Example" })
  expectEachPidOnce(tree, recs)
  #expect(!session.children.contains { $0.id == "pid:103" })
}

@Test func claudeSessionWithoutRootIsMarkedEnded() {
  let s = "feedbeef-0000"
  let tree = buildTree(
    [rec(pid: 5, ppid: 1, rss: 1, session: s, cwd: "/a/b/c")], grouping: .claudeSession, mode: .rss,
    includeCompressed: false)
  #expect(tree.children.first { $0.id == "session:\(s)" }?.name == "Claude session feedbeef · b/c (ended)")
}
