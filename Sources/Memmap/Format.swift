import Foundation
import MemmapCore

private let gigabyte = Double(1 << 30)
private let megabyte = Double(1 << 20)

func formatBytes(_ bytes: Int64) -> String {
  let b = Double(bytes)
  if b >= gigabyte { return String(format: "%.2f GB", b / gigabyte) }
  if b >= megabyte { return String(format: "%.0f MB", b / megabyte) }
  return String(format: "%.0f KB", b / 1024)
}

func findNode(_ key: String, in node: TreeNode) -> TreeNode? {
  if node.id == key { return node }
  for child in node.children {
    if let found = findNode(key, in: child) { return found }
  }
  return nil
}

func leafCount(_ node: TreeNode) -> Int {
  node.children.isEmpty ? 1 : node.children.reduce(0) { $0 + leafCount($1) }
}
