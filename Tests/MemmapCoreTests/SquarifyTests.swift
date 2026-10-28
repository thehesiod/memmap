import CoreGraphics
import Testing
@testable import MemmapCore

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
  #expect(rects[1] == .zero)
}

@Test func squarifyDegenerateRectYieldsZeroRects() {
  let rects = squarify([3, 2, 1], in: CGRect(x: 0, y: 0, width: 0, height: 10))
  #expect(rects == [.zero, .zero, .zero])
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
  #expect(g.isGroup && g.total == 100 && g.depth == 1 && g.ancestorKeys.isEmpty)
}

@Test func layoutOmitsTinyRects() {
  let leaf = { (k: String, v: Int64) in TreeNode(id: k, name: k, record: nil, value: v, compressed: 0, children: []) }
  let root = TreeNode(id: "root", name: "All", record: nil, value: 0, compressed: 0, children: [leaf("big", 1_000_000), leaf("tiny", 1)])
  let placed = layoutTreemap(root, in: CGRect(x: 0, y: 0, width: 200, height: 200))
  #expect(placed.map(\.key) == ["big"])
}
