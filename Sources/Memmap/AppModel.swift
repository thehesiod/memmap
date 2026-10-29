import Foundation
import MemmapCore
import Observation

@MainActor @Observable
final class AppModel {
  var mode: Mode {
    didSet {
      guard mode != oldValue else { return }
      defaults.set(mode.rawValue, forKey: "mode")
      settingsChanged()
      if (mode == .sharedSplit) != (oldValue == .sharedSplit) { wake() }
    }
  }
  var includeCompressed: Bool {
    didSet {
      guard includeCompressed != oldValue else { return }
      defaults.set(includeCompressed, forKey: "includeCompressed")
      settingsChanged()
    }
  }
  var grouping: Grouping {
    didSet {
      guard grouping != oldValue else { return }
      defaults.set(grouping.rawValue, forKey: "grouping")
      settingsChanged()
    }
  }
  var interval: Double {
    didSet {
      guard interval != oldValue else { return }
      guard interval >= 0.5 else {
        interval = oldValue
        return
      }
      defaults.set(interval, forKey: "interval")
      sleepTask?.cancel()
    }
  }
  var paused = false {
    didSet {
      guard paused != oldValue else { return }
      if paused { sleepTask?.cancel() } else { wake() }
    }
  }

  private(set) var snapshot: Snapshot?
  private(set) var tree: TreeNode?
  private(set) var previousTotals: [String: Int64] = [:]
  private(set) var lastError: String?
  var navigation = Navigation()

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let collector = Collector()
  @ObservationIgnored private let demo = ProcessInfo.processInfo.environment["MEMMAP_DEMO"] == "1"
  @ObservationIgnored private var loop: Task<Void, Never>?
  @ObservationIgnored private var sleepTask: Task<Bool, Never>?
  @ObservationIgnored private var wakeRequested = false
  @ObservationIgnored private var baselineStale = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    mode = defaults.string(forKey: "mode").flatMap(Mode.init(rawValue:)) ?? .rss
    includeCompressed = defaults.object(forKey: "includeCompressed") as? Bool ?? true
    grouping = defaults.string(forKey: "grouping").flatMap(Grouping.init(rawValue:)) ?? .app
    let stored = defaults.double(forKey: "interval")
    interval = stored >= 0.5 ? stored : 2.0
  }

  func start() {
    guard loop == nil else { return }
    loop = Task { [weak self] in
      while !Task.isCancelled, let self {
        await self.refreshOnce()
        await self.idle()
      }
    }
  }

  func refreshNow() {
    wake()
  }

  private func wake() {
    wakeRequested = true
    sleepTask?.cancel()
  }

  private func refreshOnce() async {
    wakeRequested = false
    do {
      let next = demo ? Demo.snapshot() : try await collector.collect(split: mode == .sharedSplit)
      snapshot = next
      lastError = nil
      rebuild(resetBaseline: false)
    } catch {
      lastError = String(describing: error)
    }
  }

  private func idle() async {
    while !Task.isCancelled {
      if wakeRequested { return }
      let duration: Duration = paused ? .seconds(31_536_000) : .seconds(interval)
      let task = Task { (try? await Task.sleep(for: duration)) != nil }
      sleepTask = task
      let elapsed = await task.value
      sleepTask = nil
      if elapsed && !paused { return }
    }
  }

  private func settingsChanged() {
    rebuild(resetBaseline: true)
  }

  private func rebuild(resetBaseline: Bool) {
    if resetBaseline {
      previousTotals = [:]
      baselineStale = true
    } else {
      previousTotals = baselineStale ? [:] : tree.map(Self.totals(of:)) ?? [:]
      baselineStale = false
    }
    guard let snapshot else { return }
    let next = buildTree(snapshot.processes, grouping: grouping, mode: mode, includeCompressed: includeCompressed)
    tree = next
    navigation.reconcile(with: next)
  }

  private static func totals(of root: TreeNode) -> [String: Int64] {
    var result: [String: Int64] = [:]
    func walk(_ node: TreeNode) {
      result[node.id] = node.total
      node.children.forEach(walk)
    }
    walk(root)
    return result
  }
}
