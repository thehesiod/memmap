import CoreGraphics

public struct TreeNode: Sendable, Identifiable {
  public let id: String
  public var name: String
  public var record: ProcessRecord?
  public var value: Int64
  public var compressed: Int64
  public var children: [TreeNode]
  public let total: Int64

  public var isGroup: Bool { !children.isEmpty }

  public init(id: String, name: String, record: ProcessRecord?, value: Int64, compressed: Int64, children: [TreeNode]) {
    self.id = id
    self.name = name
    self.record = record
    self.value = value
    self.compressed = compressed
    self.children = children
    self.total = children.isEmpty ? value : children.reduce(0) { $0 + $1.total }
  }
}

public struct PlacedNode: Sendable {
  public var key: String
  public var name: String
  public var rect: CGRect
  public var depth: Int
  public var isGroup: Bool
  public var total: Int64
  public var compressed: Int64
  public var record: ProcessRecord?
  public var ancestorKeys: [String]
}

// Squarified treemap (Bruls, Huizing, van Wijk) with D3's ratio weighting.
public func squarify(_ values: [Double], in rect: CGRect, ratio: Double = (1 + 5.squareRoot()) / 2) -> [CGRect] {
  var result = [CGRect](repeating: .zero, count: values.count)
  let positive = values.indices.filter { values[$0] > 0 && values[$0].isFinite }
  let sum = positive.reduce(0.0) { $0 + values[$1] }
  guard !positive.isEmpty, sum > 0, rect.width > 0, rect.height > 0 else { return result }

  var x0 = Double(rect.minX), y0 = Double(rect.minY)
  let x1 = Double(rect.maxX), y1 = Double(rect.maxY)
  var remaining = sum
  var i0 = 0

  while i0 < positive.count {
    let dx = x1 - x0, dy = y1 - y0
    if dx <= 0 || dy <= 0 { break }

    var rowSum = values[positive[i0]]
    var minValue = rowSum, maxValue = rowSum
    let alpha = max(dy / dx, dx / dy) / (remaining * ratio)
    var beta = rowSum * rowSum * alpha
    var minRatio = max(maxValue / beta, beta / minValue)
    var i1 = i0 + 1
    while i1 < positive.count {
      let v = values[positive[i1]]
      let nextSum = rowSum + v
      let nextMin = min(minValue, v), nextMax = max(maxValue, v)
      beta = nextSum * nextSum * alpha
      let newRatio = max(nextMax / beta, beta / nextMin)
      if newRatio > minRatio { break }
      rowSum = nextSum
      minValue = nextMin
      maxValue = nextMax
      minRatio = newRatio
      i1 += 1
    }

    let fraction = rowSum / remaining
    let isLast = i1 == positive.count
    if dx < dy {
      let h = isLast ? dy : dy * fraction
      var x = x0
      for k in i0..<i1 {
        let w = k == i1 - 1 ? x1 - x : dx * values[positive[k]] / rowSum
        result[positive[k]] = CGRect(x: x, y: y0, width: max(0, w), height: max(0, h))
        x += w
      }
      y0 += h
    } else {
      let w = isLast ? dx : dx * fraction
      var y = y0
      for k in i0..<i1 {
        let h = k == i1 - 1 ? y1 - y : dy * values[positive[k]] / rowSum
        result[positive[k]] = CGRect(x: x0, y: y, width: max(0, w), height: max(0, h))
        y += h
      }
      x0 += w
    }
    remaining -= rowSum
    i0 = i1
  }
  return result
}

public func layoutTreemap(
  _ root: TreeNode, in rect: CGRect,
  headerHeight: CGFloat = 15, outerPadding: CGFloat = 2, innerPadding: CGFloat = 1
) -> [PlacedNode] {
  var placed: [PlacedNode] = []

  func place(_ node: TreeNode, rect: CGRect, depth: Int, ancestors: [String]) {
    var content = rect.insetBy(dx: outerPadding, dy: outerPadding)
    if depth >= 1 {
      content.origin.y += headerHeight
      content.size.height -= headerHeight
    }
    guard content.width > 0, content.height > 0 else { return }

    let kids = node.children.filter { $0.total > 0 }.sorted { $0.total > $1.total }
    let slots = squarify(kids.map { Double($0.total) }, in: content)
    for (kid, slot) in zip(kids, slots) {
      let r = slot.insetBy(dx: innerPadding / 2, dy: innerPadding / 2)
      guard r.width >= 2, r.height >= 2 else { continue }
      placed.append(PlacedNode(
        key: kid.id, name: kid.name, rect: r, depth: depth + 1, isGroup: kid.isGroup,
        total: kid.total, compressed: kid.compressed, record: kid.record, ancestorKeys: ancestors
      ))
      if kid.isGroup { place(kid, rect: r, depth: depth + 1, ancestors: ancestors + [kid.id]) }
    }
  }

  place(root, rect: rect, depth: 0, ancestors: [])
  return placed
}
