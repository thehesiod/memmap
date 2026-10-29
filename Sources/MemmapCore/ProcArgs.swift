import Foundation

public struct ProcArgs: Sendable, Equatable {
  public var args: String
  public var env: [String: String]

  public init(args: String, env: [String: String]) {
    self.args = args
    self.env = env
  }
}

private let allowedEnvKeys: Set<String> = ["CLAUDE_CODE_SESSION_ID", "PWD", "XPC_SERVICE_NAME"]

public func parseProcArgs2(_ buffer: [UInt8]) -> ProcArgs? {
  guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
  let argc = Int(buffer.prefix(4).enumerated().reduce(Int32(0)) { $0 | Int32($1.element) << (8 * Int32($1.offset)) })
  guard argc >= 0 else { return nil }

  var pos = MemoryLayout<Int32>.size
  func nextString() -> String? {
    guard pos < buffer.count else { return nil }
    let end = buffer[pos...].firstIndex(of: 0) ?? buffer.count
    defer { pos = min(end + 1, buffer.count) }
    return String(decoding: buffer[pos..<end], as: UTF8.self)
  }

  _ = nextString()
  // The kernel pads the exec path with NULs before argv begins.
  while pos < buffer.count, buffer[pos] == 0 { pos += 1 }

  var args: [String] = []
  for _ in 0..<argc {
    guard let arg = nextString() else { break }
    args.append(arg)
  }

  var env: [String: String] = [:]
  while let entry = nextString(), !entry.isEmpty {
    guard let eq = entry.firstIndex(of: "=") else { continue }
    let key = String(entry[..<eq])
    if allowedEnvKeys.contains(key) { env[key] = String(entry[entry.index(after: eq)...]) }
  }

  return ProcArgs(args: String(args.joined(separator: " ").prefix(maxArgsChars)), env: env)
}
