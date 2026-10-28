import Foundation

public struct PSRow: Sendable, Hashable {
  public var ppid: Int32
  public var uid: UInt32
  public var rss: Int64
  public var comm: String

  public init(ppid: Int32, uid: UInt32, rss: Int64, comm: String) {
    self.ppid = ppid
    self.uid = uid
    self.rss = rss
    self.comm = comm
  }
}

private let maxArgsChars = 4000

public func parseSize(_ text: String) -> Int64 {
  let digits = text.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
  guard let value = Double(digits) else { return 0 }
  let multiplier: Int64 =
    switch text.dropFirst(digits.count).first {
    case "K": 1 << 10
    case "M": 1 << 20
    case "G": 1 << 30
    case "T": 1 << 40
    default: 1
    }
  return Int64(value * Double(multiplier))
}

private func splitFields(_ line: Substring, maxFields: Int) -> [Substring] {
  line.split(separator: " ", maxSplits: maxFields - 1, omittingEmptySubsequences: true)
}

public func parsePS(_ output: String) -> [Int32: PSRow] {
  var rows: [Int32: PSRow] = [:]
  for line in output.split(whereSeparator: \.isNewline) {
    let fields = splitFields(line, maxFields: 5)
    guard fields.count == 5, let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
      let uid = UInt32(fields[2]), let rssKiB = Int64(fields[3])
    else { continue }
    rows[pid] = PSRow(ppid: ppid, uid: uid, rss: rssKiB * 1024, comm: String(fields[4]))
  }
  return rows
}

public func parsePSArgs(_ output: String) -> [Int32: String] {
  var rows: [Int32: String] = [:]
  for line in output.split(whereSeparator: \.isNewline) {
    let fields = splitFields(line, maxFields: 2)
    guard let first = fields.first, let pid = Int32(first) else { continue }
    rows[pid] = fields.count == 2 ? String(fields[1].prefix(maxArgsChars)) : ""
  }
  return rows
}

private func sizeBefore(_ keyword: String, in line: String) -> Int64? {
  guard let match = line.firstMatch(of: try! Regex("([\\d.]+[BKMGT]) \(keyword)")),
    let size = match.output[1].substring
  else { return nil }
  return parseSize(String(size))
}

public func parseTop(_ output: String) -> (
  perPID: [Int32: (footprint: Int64, compressed: Int64)], used: Int64, compressor: Int64
) {
  var perPID: [Int32: (footprint: Int64, compressed: Int64)] = [:]
  var used: Int64 = 0
  var compressor: Int64 = 0
  var inTable = false
  for line in output.split(whereSeparator: \.isNewline).map(String.init) {
    if line.hasPrefix("PhysMem:") {
      used = sizeBefore("used", in: line) ?? 0
      compressor = sizeBefore("compressor", in: line) ?? 0
    } else if line.hasPrefix("PID") {
      inTable = true
    } else if inTable {
      let fields = line.split(separator: " ")
      guard fields.count >= 3, let pid = Int32(fields[0]) else { continue }
      perPID[pid] = (parseSize(String(fields[1])), parseSize(String(fields[2])))
    }
  }
  return (perPID, used, compressor)
}

public func parseSwapUsage(_ line: String) -> (used: Int64, total: Int64) {
  func value(_ key: String) -> Int64 {
    guard let match = line.firstMatch(of: try! Regex("\(key) = ([\\d.]+[BKMGT])")),
      let size = match.output[1].substring
    else { return 0 }
    return parseSize(String(size))
  }
  return (value("used"), value("total"))
}

public func outermostApp(path: String) -> String? {
  for component in path.split(separator: "/") where component.hasSuffix(".app") {
    return String(component.dropLast(4))
  }
  return nil
}
