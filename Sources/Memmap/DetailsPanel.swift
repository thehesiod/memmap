import MemmapCore
import SwiftUI

private let changeThreshold: Int64 = 1_048_576

struct DetailsPanel: View {
  let model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if let tree = model.tree, let key = model.navigation.detailsKey, let node = findNode(key, in: tree) {
          details(node, in: tree)
        } else {
          Text("Hover a box for details. Click to pin it. Double-click a group to zoom in.")
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
    .frame(width: 250)
    .background(.background)
  }

  @ViewBuilder private func details(_ node: TreeNode, in tree: TreeNode) -> some View {
    Text(node.name)
      .font(.headline)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)

    if let p = node.record {
      HStack(spacing: 0) {
        Text("PID \(String(p.pid)) · parent ")
        if p.ppid != p.pid, findNode("pid:\(p.ppid)", in: tree) != nil {
          Button(String(p.ppid)) { model.navigation.select(pid: p.ppid, in: tree) }
            .buttonStyle(.link)
            .help("Select the parent process")
        } else {
          Text(String(p.ppid))
        }
        Text(" · uid \(String(p.uid))")
      }
      .foregroundStyle(.secondary)

      if !p.args.isEmpty {
        ScrollView {
          Text(p.args)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
      }
    }

    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
      ForEach(rows(for: node), id: \.label) { row in
        GridRow {
          Text(row.label)
          row.value
            .gridColumnAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
    .monospacedDigit()

    Label(
      model.navigation.pinnedKey == node.id ? "Pinned. Click the box again to unpin." : "Click to pin. Double-click a group to zoom in.",
      systemImage: model.navigation.pinnedKey == node.id ? "pin.fill" : "cursorarrow.click"
    )
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.top, 4)
  }

  private struct Row {
    let label: String
    let value: Text
  }

  private func rows(for node: TreeNode) -> [Row] {
    var rows = [Row(label: node.isGroup && node.record != nil ? "Counted here, with children" : "Counted here", value: Text(formatBytes(node.total)))]
    if let previous = model.previousTotals[node.id] {
      let delta = node.total - previous
      if abs(delta) >= changeThreshold {
        let text = (delta > 0 ? "+" : "−") + formatBytes(abs(delta))
        rows.append(Row(label: "Change since last refresh", value: Text(text).foregroundStyle(delta > 0 ? .red : .green)))
      }
    }
    if node.isGroup { rows.append(Row(label: "Processes", value: Text(String(leafCount(node))))) }
    guard let p = node.record else { return rows }
    if let session = p.session { rows.append(Row(label: "Claude session", value: Text(String(session.prefix(8))))) }
    rows += [
      Row(label: "RSS", value: Text(formatBytes(p.rss))),
      Row(label: "Compressed", value: Text(formatBytes(p.compressed))),
      Row(label: "Footprint", value: Text(formatBytes(p.footprint))),
    ]
    if model.mode == .sharedSplit, let s = p.split {
      rows += [
        Row(label: "Private resident", value: Text(formatBytes(s.privateResident))),
        Row(label: "Shared resident", value: Text(formatBytes(s.sharedResident))),
        Row(label: "Shared, its split", value: Text(formatBytes(s.sharedSplit))),
        Row(label: "Largest shared region also in", value: Text("\(s.largestSharedAlsoIn) other processes")),
      ]
    }
    return rows
  }
}
