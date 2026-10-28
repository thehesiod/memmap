public struct Navigation: Sendable, Equatable {
  public var zoomPath: [String]
  public var pinnedKey: String?
  public var hoverKey: String?

  public init(zoomPath: [String] = [], pinnedKey: String? = nil, hoverKey: String? = nil) {
    self.zoomPath = zoomPath
    self.pinnedKey = pinnedKey
    self.hoverKey = hoverKey
  }

  public var detailsKey: String? { pinnedKey ?? hoverKey }

  public mutating func togglePin(_ key: String) {
    pinnedKey = pinnedKey == key ? nil : key
  }

  public mutating func zoom(into placed: PlacedNode) {
    if placed.isGroup {
      zoomPath += placed.ancestorKeys + [placed.key]
    } else {
      zoomPath += placed.ancestorKeys
    }
  }

  public mutating func select(pid: Int32, in tree: TreeNode) {
    let key = "pid:\(pid)"
    guard let ancestors = ancestorKeys(of: key, in: tree) else { return }
    pinnedKey = key
    if !ancestors.starts(with: zoomPath) { zoomPath = ancestors }
  }

  public mutating func reconcile(with tree: TreeNode) {
    var node = tree
    var kept = 0
    for key in zoomPath {
      guard let child = node.children.first(where: { $0.id == key }) else { break }
      node = child
      kept += 1
    }
    zoomPath.removeLast(zoomPath.count - kept)
    if let pinnedKey, ancestorKeys(of: pinnedKey, in: tree) == nil { self.pinnedKey = nil }
  }
}

public func focusNode(of tree: TreeNode, path: [String]) -> TreeNode {
  var node = tree
  for key in path {
    guard let child = node.children.first(where: { $0.id == key }) else { break }
    node = child
  }
  return node
}

private func ancestorKeys(of key: String, in tree: TreeNode) -> [String]? {
  func search(_ node: TreeNode, _ trail: [String]) -> [String]? {
    for child in node.children {
      if child.id == key { return trail }
      if let found = search(child, trail + [child.id]) { return found }
    }
    return nil
  }
  return search(tree, [])
}
