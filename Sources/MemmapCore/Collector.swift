import Foundation

public struct ToolFailure: Error, Sendable {
  public let tool: String
  public let detail: String
}

private func runTool(_ path: String, _ arguments: [String]) async throws -> String {
  try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.global().async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        continuation.resume(throwing: ToolFailure(tool: path, detail: "\(error)"))
        return
      }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        continuation.resume(
          throwing: ToolFailure(tool: path, detail: "exit status \(process.terminationStatus)"))
        return
      }
      continuation.resume(returning: String(decoding: data, as: UTF8.self))
    }
  }
}

private func inBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
  await withCheckedContinuation { continuation in
    DispatchQueue.global().async { continuation.resume(returning: work()) }
  }
}

private final class Slots<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [T?]
  init(count: Int) { values = Array(repeating: nil, count: count) }
  func set(_ index: Int, _ value: T?) {
    lock.lock()
    values[index] = value
    lock.unlock()
  }
  func all() -> [T?] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}

private func buildRecords(
  pids: [Int32], ps: [Int32: PSRow], psArgs: [Int32: String],
  top: [Int32: (footprint: Int64, compressed: Int64)]
) -> [ProcessRecord] {
  pids.compactMap { pid in
    let row = ps[pid]
    guard let (ppid, uid) = LibProc.bsdInfo(pid).map({ ($0.ppid, $0.uid) })
      ?? row.map({ ($0.ppid, $0.uid) })
    else { return nil }
    let path = LibProc.executablePath(pid) ?? row?.comm ?? ""
    let name = path.split(separator: "/").last.map(String.init) ?? path
    let procArgs = LibProc.procArgs(pid)
    let args = procArgs?.args ?? psArgs[pid] ?? path
    return ProcessRecord(
      pid: pid, ppid: ppid, uid: uid, name: name, path: path, args: args,
      app: outermostApp(path: path),
      session: procArgs?.env["CLAUDE_CODE_SESSION_ID"],
      cwd: procArgs?.env["PWD"],
      xpcService: procArgs?.env["XPC_SERVICE_NAME"],
      rss: LibProc.residentSize(pid) ?? row?.rss ?? 0,
      footprint: LibProc.physFootprint(pid) ?? top[pid]?.footprint ?? 0,
      compressed: top[pid]?.compressed ?? 0,
      split: nil)
  }
}

private func walkAll(_ pids: [Int32]) -> [Int32: RegionTally] {
  let slots = Slots<RegionTally>(count: pids.count)
  DispatchQueue.concurrentPerform(iterations: pids.count) { index in
    slots.set(index, walkRegions(pid: pids[index]))
  }
  var tallies: [Int32: RegionTally] = [:]
  for (pid, tally) in zip(pids, slots.all()) {
    if let tally { tallies[pid] = tally }
  }
  return tallies
}

public actor Collector {
  public init() {}

  public func collect(split: Bool) async throws -> Snapshot {
    let clock = ContinuousClock()
    let start = clock.now

    async let psOut = runTool("/bin/ps", ["-axo", "pid=,ppid=,uid=,rss=,comm="])
    async let psArgsOut = runTool("/bin/ps", ["-axww", "-o", "pid=,args="])
    async let topOut = runTool("/usr/bin/top", ["-l", "1", "-stats", "pid,mem,cmprs"])
    async let memsizeOut = runTool("/usr/sbin/sysctl", ["-n", "hw.memsize"])
    async let swapOut = runTool("/usr/sbin/sysctl", ["-n", "vm.swapusage"])
    let (psText, psArgsText, topText, memsizeText, swapText) =
      try await (psOut, psArgsOut, topOut, memsizeOut, swapOut)

    let ps = parsePS(psText)
    let psArgs = parsePSArgs(psArgsText)
    let top = parseTop(topText)
    let swap = parseSwapUsage(swapText)

    let pids = Array(Set(ps.keys).union(await inBackground { LibProc.listPIDs() })).sorted()
    var records = await inBackground {
      buildRecords(pids: pids, ps: ps, psArgs: psArgs, top: top.perPID)
    }

    var inspected = 0
    if split {
      let recordPIDs = records.map(\.pid)
      let tallies = await inBackground { walkAll(recordPIDs) }
      let figures = splitFigures(tallies)
      inspected = tallies.count
      for index in records.indices { records[index].split = figures[records[index].pid] }
    }

    return Snapshot(
      processes: records,
      system: SystemTotals(
        used: top.used, compressor: top.compressor,
        physical: Int64(memsizeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
        swapUsed: swap.used, swapTotal: swap.total),
      inspected: inspected,
      collectedIn: clock.now - start)
  }
}
