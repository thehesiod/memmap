public enum Mode: String, CaseIterable, Sendable {
  case rss, sharedSplit, footprint
}

public enum Grouping: String, CaseIterable, Sendable {
  case processTree, app, claudeSession
}

public func measure(_ p: ProcessRecord, mode: Mode, includeCompressed: Bool) -> (value: Int64, compressed: Int64) {
  switch mode {
  case .footprint:
    return (p.footprint, min(p.compressed, p.footprint))
  case .sharedSplit:
    if let s = p.split {
      let compressed = includeCompressed ? s.privateCompressed + s.sharedCompressedSplit : 0
      return (s.privateResident + s.sharedSplit + compressed, compressed)
    }
    fallthrough
  case .rss:
    let compressed = includeCompressed ? p.compressed : 0
    return (p.rss + compressed, compressed)
  }
}

private let maxAncestorHops = 64

public func buildTree(
  _ records: [ProcessRecord], grouping: Grouping, mode: Mode, includeCompressed: Bool
) -> TreeNode {
  let leaf = { (p: ProcessRecord, id: String, name: String?) -> TreeNode in
    let m = measure(p, mode: mode, includeCompressed: includeCompressed)
    return TreeNode(id: id, name: name ?? p.name, record: p, value: m.value, compressed: m.compressed, children: [])
  }
  let children: [TreeNode]
  switch grouping {
  case .processTree: children = forest(records, attachTo: nil, leaf: leaf)
  case .app: children = appNodes(records, leaf: leaf)
  case .claudeSession: children = sessionNodes(records, leaf: leaf)
  }
  return TreeNode(id: "root", name: "All processes", record: nil, value: 0, compressed: 0, children: children)
}

private typealias LeafMaker = (ProcessRecord, String, String?) -> TreeNode

private func forest(_ procs: [ProcessRecord], attachTo: Int32?, leaf: LeafMaker) -> [TreeNode] {
  let pids = Set(procs.map(\.pid))
  var kids: [Int32: [ProcessRecord]] = [:]
  var tops: [ProcessRecord] = []
  for p in procs {
    let parent: Int32? =
      if p.ppid != p.pid && pids.contains(p.ppid) {
        p.ppid
      } else if let attachTo, p.pid != attachTo {
        attachTo
      } else {
        nil
      }
    if let parent { kids[parent, default: []].append(p) } else { tops.append(p) }
  }
  func make(_ p: ProcessRecord, _ visited: Set<Int32>) -> TreeNode {
    guard let children = kids[p.pid] else { return leaf(p, "pid:\(p.pid)", nil) }
    let visited = visited.union([p.pid])
    let nested = children.filter { !visited.contains($0.pid) }.map { make($0, visited) }
    return TreeNode(
      id: "pid:\(p.pid)", name: p.name, record: p, value: 0, compressed: 0,
      children: [leaf(p, "self:\(p.pid)", "\(p.name) (itself)")] + nested)
  }
  return tops.map { make($0, []) }
}

private func appOf(_ p: ProcessRecord, _ byPid: [Int32: ProcessRecord]) -> String? {
  var cur: ProcessRecord? = p
  var hops = 0
  while let c = cur, hops < maxAncestorHops {
    if let app = c.app { return app }
    if c.ppid == c.pid { break }
    cur = byPid[c.ppid]
    hops += 1
  }
  return nil
}

private func appNodes(_ procs: [ProcessRecord], leaf: LeafMaker) -> [TreeNode] {
  let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
  var order: [String] = []
  var groups: [String: [ProcessRecord]] = [:]
  for p in procs {
    let name =
      appOf(p, byPid) ?? (p.uid == 0 ? "System (root)" : p.uid < 500 ? "System services" : "Other user processes")
    if groups[name] == nil { order.append(name) }
    groups[name, default: []].append(p)
  }
  return order.map { name in
    let ps = groups[name]!
    if ps.count == 1 { return leaf(ps[0], "pid:\(ps[0].pid)", nil) }
    return TreeNode(
      id: "app:\(name)", name: name, record: nil, value: 0, compressed: 0,
      children: ps.map { leaf($0, "pid:\($0.pid)", nil) })
  }
}

private func shortPath(_ path: String) -> String {
  path.split(separator: "/").suffix(2).joined(separator: "/")
}

private func sessionNodes(_ procs: [ProcessRecord], leaf: LeafMaker) -> [TreeNode] {
  let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
  var sessionOrder: [String] = []
  var carriers: [String: [ProcessRecord]] = [:]
  for p in procs {
    guard let s = p.session, !s.isEmpty else { continue }
    if carriers[s] == nil { sessionOrder.append(s) }
    carriers[s, default: []].append(p)
  }

  var rootOf: [String: Int32] = [:]
  for s in sessionOrder {
    var voteOrder: [Int32] = []
    var votes: [Int32: Int] = [:]
    for p in carriers[s]! where p.ppid != 1 && byPid[p.ppid]?.session != s {
      if votes[p.ppid] == nil { voteOrder.append(p.ppid) }
      votes[p.ppid, default: 0] += 1
    }
    var best: Int32?
    for pid in voteOrder where best == nil || votes[pid]! > votes[best!]! { best = pid }
    if let best, byPid[best] != nil { rootOf[s] = best }
  }
  var claimedRoots: [Int32: String] = [:]
  for s in sessionOrder { if let pid = rootOf[s] { claimedRoots[pid] = s } }

  func relaunchedAsApp(_ p: ProcessRecord) -> Bool {
    guard let xpc = p.xpcService, xpc.hasPrefix("application.") else { return false }
    let rootXpc = p.session.flatMap { rootOf[$0] }.flatMap { byPid[$0]?.xpcService }
    return xpc != rootXpc
  }

  var members: [String: [ProcessRecord]] = [:]
  var assigned = Set<Int32>()
  for p in procs {
    let session: String? =
      if let claimed = claimedRoots[p.pid] {
        claimed
      } else if let s = p.session, !s.isEmpty, !relaunchedAsApp(p) {
        s
      } else {
        nil
      }
    guard let session else { continue }
    members[session, default: []].append(p)
    assigned.insert(p.pid)
  }

  var nodes: [TreeNode] = []
  for s in sessionOrder {
    guard let ps = members[s], !ps.isEmpty else { continue }
    let rootPid = rootOf[s]
    let withCwd = ps.filter { $0.cwd.map { !$0.isEmpty } ?? false }
    let top = withCwd.first { $0.ppid == rootPid } ?? withCwd.first
    var label = "Claude session \(s.prefix(8))"
    if let cwd = top?.cwd { label += " · \(shortPath(cwd))" }
    if rootPid == nil { label += " (ended)" }
    nodes.append(
      TreeNode(
        id: "session:\(s)", name: label, record: nil, value: 0, compressed: 0,
        children: forest(ps, attachTo: rootPid, leaf: leaf)))
  }
  return nodes + appNodes(procs.filter { !assigned.contains($0.pid) }, leaf: leaf)
}
