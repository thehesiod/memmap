import AppKit
import MemmapCore
import SwiftUI

private struct HSL {
  var h, s, l: Double

  init(hex: UInt32) {
    let r = Double((hex >> 16) & 0xff) / 255, g = Double((hex >> 8) & 0xff) / 255, b = Double(hex & 0xff) / 255
    let hi = max(r, g, b), lo = min(r, g, b)
    l = (hi + lo) / 2
    let d = hi - lo
    guard d > 0 else {
      h = 0
      s = 0
      return
    }
    s = l < 0.5 ? d / (hi + lo) : d / (2 - hi - lo)
    switch hi {
    case r: h = ((g - b) / d + (g < b ? 6 : 0)) * 60
    case g: h = ((b - r) / d + 2) * 60
    default: h = ((r - g) / d + 4) * 60
    }
  }

  func color(lightness: Double) -> Color {
    let sat = max(0.35, s * 0.75)
    let c = (1 - abs(2 * lightness - 1)) * sat
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = lightness - c / 2
    let (r, g, b): (Double, Double, Double) =
      switch h {
      case ..<60: (c, x, 0)
      case ..<120: (x, c, 0)
      case ..<180: (0, c, x)
      case ..<240: (0, x, c)
      case ..<300: (x, 0, c)
      default: (c, 0, x)
      }
    return Color(red: r + m, green: g + m, blue: b + m)
  }
}

private let palette: [HSL] = [
  0x4e79a7, 0xf28e2c, 0xe15759, 0x76b7b2, 0x59a14f, 0xedc949, 0xaf7aa1, 0xff9da7, 0x9c755f, 0xbab0ab,
].map(HSL.init(hex:))

private let boxText = Color(white: 0.067)
private let hatchColor = Color.black.opacity(0.28)

struct TreemapView: View {
  let model: AppModel
  let focus: TreeNode

  var body: some View {
    GeometryReader { geo in
      let placed = layoutTreemap(focus, in: CGRect(origin: .zero, size: geo.size))
      let style = BoxStyle(placed: placed, focus: focus, mode: model.mode)
      let hoverKey = model.navigation.hoverKey
      let pinnedKey = model.navigation.pinnedKey
      Canvas { context, _ in
        style.draw(in: &context, hoverKey: hoverKey, pinnedKey: pinnedKey)
      }
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        let key: String? =
          switch phase {
          case .active(let point): hit(point, in: placed)?.key
          case .ended: nil
          }
        if model.navigation.hoverKey != key { model.navigation.hoverKey = key }
      }
      .gesture(
        SpatialTapGesture().onEnded { value in
          guard let node = hit(value.location, in: placed) else { return }
          if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            model.navigation.togglePin(node.key)
            model.navigation.zoom(into: node)
          } else {
            model.navigation.togglePin(node.key)
          }
        }
      )
    }
  }

  private func hit(_ point: CGPoint, in placed: [PlacedNode]) -> PlacedNode? {
    placed.last { $0.rect.contains(point) }
  }
}

private struct BoxStyle {
  let placed: [PlacedNode]
  let fills: [Color]
  let counts: [String: Int]
  let mode: Mode

  init(placed: [PlacedNode], focus: TreeNode, mode: Mode) {
    self.placed = placed
    self.mode = mode
    var hues: [String: Int] = [:]
    for node in placed where node.depth == 1 { hues[node.key] = hues.count % palette.count }
    fills = placed.map { node in
      let top = node.depth == 1 ? node.key : node.ancestorKeys.first ?? node.key
      let lightness = min(0.9, 0.62 + 0.07 * Double(node.depth - 1) + (node.isGroup ? 0 : 0.06))
      return palette[hues[top] ?? 0].color(lightness: lightness)
    }
    var counts: [String: Int] = [:]
    func walk(_ node: TreeNode) -> Int {
      let n = node.children.isEmpty ? 1 : node.children.reduce(0) { $0 + walk($1) }
      if !node.children.isEmpty { counts[node.id] = n }
      return n
    }
    _ = walk(focus)
    self.counts = counts
  }

  func draw(in context: inout GraphicsContext, hoverKey: String?, pinnedKey: String?) {
    var hatchClip = Path()
    var hatchLines = Path()
    for (node, fill) in zip(placed, fills) {
      let r = node.rect
      let box = Path(roundedRect: r, cornerRadius: 2)
      context.fill(box, with: .color(fill))
      context.stroke(
        Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2),
        with: .color(.black.opacity(node.isGroup ? 0.35 : 0.15)), lineWidth: 1)

      if !node.isGroup, node.compressed > 0, node.total > 0 {
        let fraction = min(1, Double(node.compressed) / Double(node.total))
        let h = r.height * fraction
        let band = CGRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
        hatchClip.addRect(band)
        addHatch(to: &hatchLines, covering: band)
      }

      if mode == .sharedSplit, !node.isGroup, let record = node.record, record.split == nil {
        context.stroke(
          Path(r.insetBy(dx: 3.5, dy: 3.5)), with: .color(.black.opacity(0.5)),
          style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      }

      if r.width >= 36, r.height >= 12 {
        var label = context
        label.clip(to: Path(r.insetBy(dx: 1, dy: 1)))
        let title = node.isGroup ? "\(node.name) · \(formatBytes(node.total)) (\(counts[node.key] ?? 0))" : node.name
        label.draw(
          Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(boxText),
          at: CGPoint(x: r.minX + 3, y: r.minY + 1), anchor: .topLeading)
        if !node.isGroup, r.height >= 26 {
          label.draw(
            Text(formatBytes(node.total)).font(.system(size: 11)).foregroundStyle(boxText),
            at: CGPoint(x: r.minX + 3, y: r.minY + 14), anchor: .topLeading)
        }
      }
    }
    if !hatchLines.isEmpty {
      var hatch = context
      hatch.clip(to: hatchClip)
      hatch.stroke(hatchLines, with: .color(hatchColor), lineWidth: 3)
    }

    for node in placed {
      if node.key == pinnedKey {
        context.stroke(Path(node.rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(.accentColor), lineWidth: 3)
        context.stroke(
          Path(node.rect.insetBy(dx: 4, dy: 4)), with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 2)
      } else if node.key == hoverKey {
        context.stroke(Path(node.rect.insetBy(dx: 1, dy: 1)), with: .color(.accentColor), lineWidth: 2)
      }
    }
  }

  private func addHatch(to path: inout Path, covering band: CGRect) {
    let step = 7 * 2.0.squareRoot()
    var c = (band.minY - band.maxX).rounded(.down) - step
    let end = band.maxY - band.minX + step
    c = (c / step).rounded(.down) * step
    while c <= end {
      path.move(to: CGPoint(x: band.minY - c - step, y: band.minY - step))
      path.addLine(to: CGPoint(x: band.maxY - c + step, y: band.maxY + step))
      c += step
    }
  }
}
