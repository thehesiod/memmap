@testable import MemmapCore

func rec(
  pid: Int32, ppid: Int32, uid: UInt32 = 501, path: String = "/usr/bin/example", rss: Int64,
  session: String? = nil, xpc: String? = nil, cwd: String? = nil
) -> ProcessRecord {
  ProcessRecord(
    pid: pid, ppid: ppid, uid: uid,
    name: String(path.split(separator: "/").last ?? ""), path: path, args: path,
    app: outermostApp(path: path), session: session, cwd: cwd, xpcService: xpc,
    rss: rss, footprint: rss, compressed: 10, split: nil)
}
