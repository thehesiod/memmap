import AppKit
import MemmapCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MemmapApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    Window("memmap", id: "main") {
      ContentView(model: delegate.model)
        .frame(minWidth: 600, minHeight: 400)
        .task { delegate.model.start() }
    }
    .defaultSize(width: 1200, height: 800)
    .commands {
      CommandGroup(after: .toolbar) {
        Button("Refresh Now") { delegate.model.refreshNow() }
          .keyboardShortcut("r")
      }
    }
  }
}

struct ContentView: View {
  let model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      ToolbarView(model: model)
        .background(.background)
      Divider()
      HStack(spacing: 0) {
        if let tree = model.tree {
          VStack(alignment: .leading, spacing: 0) {
            Breadcrumb(model: model, tree: tree)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
            TreemapView(model: model, focus: focusNode(of: tree, path: model.navigation.zoomPath))
              .padding(.leading, 8)
              .padding(.trailing, 4)
              .padding(.bottom, 4)
          }
        } else {
          ProgressView("Collecting…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        Divider()
        DetailsPanel(model: model)
      }
    }
  }
}

private struct Breadcrumb: View {
  let model: AppModel
  let tree: TreeNode

  var body: some View {
    let path = trail
    HStack(spacing: 4) {
      ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
        if index > 0 { Text("›").foregroundStyle(.secondary) }
        let title = "\(node.name) (\(formatBytes(node.total)))"
        if index < path.count - 1 {
          Button(title) { model.navigation.zoomPath = Array(model.navigation.zoomPath.prefix(index)) }
            .buttonStyle(.link)
        } else {
          Text(title).foregroundStyle(.secondary)
        }
      }
    }
    .lineLimit(1)
  }

  private var trail: [TreeNode] {
    var nodes = [tree]
    for key in model.navigation.zoomPath {
      guard let child = nodes[nodes.count - 1].children.first(where: { $0.id == key }) else { break }
      nodes.append(child)
    }
    return nodes
  }
}
