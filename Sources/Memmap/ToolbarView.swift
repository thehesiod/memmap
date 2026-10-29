import AppKit
import MemmapCore
import SwiftUI

private let intervalRange = 0.5...3600.0

struct ToolbarView: View {
  @Bindable var model: AppModel

  var body: some View {
    ToolbarFlow(spacing: 14, rowSpacing: 6) {
      Picker("Mode", selection: $model.mode) {
        Text("RSS").tag(Mode.rss)
        Text("Shared split").tag(Mode.sharedSplit)
          .help("Private memory plus an even share of each shared region. Processes you don't own (dashed outline) show RSS.")
        Text("Footprint").tag(Mode.footprint)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()

      Toggle("Include compressed", isOn: compressedBinding)
        .toggleStyle(.checkbox)
        .disabled(model.mode == .footprint)
        .help(model.mode == .footprint ? "Footprint already includes compressed memory" : "")
        .fixedSize()

      HStack(spacing: 6) {
        Text("Group by")
        Picker("Group by", selection: $model.grouping) {
          Text("Process tree").tag(Grouping.processTree)
          Text("App").tag(Grouping.app)
          Text("Claude session").tag(Grouping.claudeSession)
            .help("Processes started from each Claude Code session, including ones whose parent has exited")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      .fixedSize()

      HStack(spacing: 4) {
        Text("Refresh every")
        IntervalField(value: $model.interval)
          .frame(width: 56)
        Stepper("Interval", value: $model.interval, in: intervalRange, step: 0.5)
          .labelsHidden()
        Text("s")
      }
      .fixedSize()

      Button(model.paused ? "Resume" : "Pause") { model.paused.toggle() }
        .fixedSize()

      status
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }

  private var compressedBinding: Binding<Bool> {
    Binding(
      get: { model.mode == .footprint || model.includeCompressed },
      set: { model.includeCompressed = $0 }
    )
  }

  @ViewBuilder private var status: some View {
    if let error = model.lastError {
      Text("Refresh failed: \(error)").foregroundStyle(.red)
    } else if let snapshot = model.snapshot {
      Text(statusText(snapshot))
    } else {
      Text("Loading…")
    }
  }

  private func statusText(_ snapshot: Snapshot) -> String {
    let sys = snapshot.system
    var parts = [
      "Used \(formatBytes(sys.used)) of \(formatBytes(sys.physical))",
      "compressor \(formatBytes(sys.compressor))",
      "swap \(formatBytes(sys.swapUsed)) of \(formatBytes(sys.swapTotal))",
      "\(snapshot.processes.count) procs",
    ]
    if model.mode == .sharedSplit { parts.append("\(snapshot.inspected) inspected") }
    parts.append("\(Int(snapshot.collectedIn / .milliseconds(1))) ms")
    if model.paused { parts.append("paused") }
    return parts.joined(separator: " · ")
  }
}

private struct IntervalField: NSViewRepresentable {
  @Binding var value: Double

  func makeNSView(context: Context) -> NSTextField {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimum = NSNumber(value: intervalRange.lowerBound)
    formatter.maximum = NSNumber(value: intervalRange.upperBound)
    formatter.maximumFractionDigits = 3
    let field = NSTextField()
    field.formatter = formatter
    field.alignment = .right
    field.bezelStyle = .roundedBezel
    field.target = context.coordinator
    field.action = #selector(Coordinator.commit(_:))
    field.toolTip = "Seconds between refreshes, 0.5 to 3600"
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.value = $value
    if field.currentEditor() == nil { field.doubleValue = value }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 56, height: field.intrinsicContentSize.height)
  }

  func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

  @MainActor final class Coordinator: NSObject {
    var value: Binding<Double>

    init(value: Binding<Double>) { self.value = value }

    @objc func commit(_ sender: NSTextField) {
      let v = sender.doubleValue
      if intervalRange.contains(v) { value.wrappedValue = v } else { sender.doubleValue = value.wrappedValue }
    }
  }
}

// Wraps like the web toolbar's flex-wrap; the last item (status) sits at the right edge of its row.
private struct ToolbarFlow: Layout {
  var spacing: CGFloat
  var rowSpacing: CGFloat

  private struct Row {
    var items: [(index: Int, size: CGSize)] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
    var rows = [Row()]
    for (index, subview) in subviews.enumerated() {
      var size = subview.sizeThatFits(.unspecified)
      if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
      let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
      if needed > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
      var row = rows.removeLast()
      row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.items.append((index, size))
      rows.append(row)
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let rows = rows(subviews, width: width)
    let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(subviews, width: bounds.width) {
      var x = bounds.minX
      for (index, size) in row.items {
        if index == subviews.count - 1 { x = max(x, bounds.maxX - size.width) }
        subviews[index].place(
          at: CGPoint(x: x, y: y + row.height / 2), anchor: .leading,
          proposal: ProposedViewSize(width: size.width, height: size.height))
        x += size.width + spacing
      }
      y += row.height + rowSpacing
    }
  }
}
