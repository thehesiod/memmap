import Testing

@testable import MemmapCore

@Test func demoSnapshotIsDeterministic() {
  let a = Demo.snapshot()
  let b = Demo.snapshot()
  #expect(a.processes == b.processes)
  #expect(a.system == b.system)
  #expect(a.inspected == b.inspected && a.collectedIn == b.collectedIn)
  #expect(a.inspected == a.processes.count { $0.split != nil })
}

@Test(arguments: Grouping.allCases)
func demoTreePlacesEachPidOnce(grouping: Grouping) {
  let recs = Demo.snapshot().processes
  expectEachPidOnce(buildTree(recs, grouping: grouping, mode: .rss, includeCompressed: true), recs)
}

@Test func demoShowsTwoClaudeSessions() {
  let tree = buildTree(Demo.snapshot().processes, grouping: .claudeSession, mode: .rss, includeCompressed: true)
  #expect(tree.children.count { $0.id.hasPrefix("session:") } == 2)
}

// "claude" alone is allowed: it is the generic name of the Claude Code CLI that session grouping looks for.
@Test func demoUsesNoRealBrandNames() {
  let blocked = ["chrome", "slack", "docker", "claude.app", "1password", "jetbrains"]
  for p in Demo.snapshot().processes {
    let text = [p.name, p.path, p.args, p.app ?? "", p.cwd ?? ""].joined(separator: "\n").lowercased()
    for word in blocked { #expect(!text.contains(word), "pid \(p.pid) mentions \(word)") }
  }
}
