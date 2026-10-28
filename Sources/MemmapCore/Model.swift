public struct SplitFigures: Sendable, Hashable {
  public var privateResident: Int64
  public var privateCompressed: Int64
  public var sharedResident: Int64
  public var sharedSplit: Int64
  public var sharedCompressedSplit: Int64
  public var largestSharedAlsoIn: Int

  public init(
    privateResident: Int64, privateCompressed: Int64, sharedResident: Int64,
    sharedSplit: Int64, sharedCompressedSplit: Int64, largestSharedAlsoIn: Int
  ) {
    self.privateResident = privateResident
    self.privateCompressed = privateCompressed
    self.sharedResident = sharedResident
    self.sharedSplit = sharedSplit
    self.sharedCompressedSplit = sharedCompressedSplit
    self.largestSharedAlsoIn = largestSharedAlsoIn
  }
}

public struct ProcessRecord: Sendable, Hashable {
  public var pid: Int32
  public var ppid: Int32
  public var uid: UInt32
  public var name: String
  public var path: String
  public var args: String
  public var app: String?
  public var session: String?
  public var cwd: String?
  public var xpcService: String?
  public var rss: Int64
  public var footprint: Int64
  public var compressed: Int64
  public var split: SplitFigures?

  public init(
    pid: Int32, ppid: Int32, uid: UInt32, name: String, path: String, args: String,
    app: String?, session: String?, cwd: String?, xpcService: String?,
    rss: Int64, footprint: Int64, compressed: Int64, split: SplitFigures?
  ) {
    self.pid = pid
    self.ppid = ppid
    self.uid = uid
    self.name = name
    self.path = path
    self.args = args
    self.app = app
    self.session = session
    self.cwd = cwd
    self.xpcService = xpcService
    self.rss = rss
    self.footprint = footprint
    self.compressed = compressed
    self.split = split
  }
}

public struct SystemTotals: Sendable, Hashable {
  public var used: Int64
  public var compressor: Int64
  public var physical: Int64
  public var swapUsed: Int64
  public var swapTotal: Int64

  public init(used: Int64, compressor: Int64, physical: Int64, swapUsed: Int64, swapTotal: Int64) {
    self.used = used
    self.compressor = compressor
    self.physical = physical
    self.swapUsed = swapUsed
    self.swapTotal = swapTotal
  }
}

public struct Snapshot: Sendable {
  public var processes: [ProcessRecord]
  public var system: SystemTotals
  public var inspected: Int
  public var collectedIn: Duration

  public init(processes: [ProcessRecord], system: SystemTotals, inspected: Int, collectedIn: Duration) {
    self.processes = processes
    self.system = system
    self.inspected = inspected
    self.collectedIn = collectedIn
  }
}
