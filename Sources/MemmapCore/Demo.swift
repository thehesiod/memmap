public enum Demo {
  private static let kb: Int64 = 1024
  private static let mb: Int64 = 1024 * kb
  private static let gb: Int64 = 1024 * mb

  private static let sessionA = "11111111-2222-4333-8444-555555555555"
  private static let sessionB = "66666666-7777-4888-9999-aaaaaaaaaaaa"
  private static let projectA = "/Users/example/project-a"
  private static let projectB = "/Users/example/project-b"

  private static let browser = "/Applications/Browser.app/Contents"
  private static let editor = "/Applications/Editor.app/Contents"
  private static let chat = "/Applications/Chat.app/Contents"

  private static func helper(_ base: String, _ app: String, _ kind: String) -> String {
    "\(base)/Frameworks/\(app) Helper (\(kind)).app/Contents/MacOS/\(app) Helper (\(kind))"
  }

  private static func proc(
    _ pid: Int32, _ ppid: Int32, _ uid: UInt32, _ path: String, _ args: String? = nil,
    rss: Int64, compressed: Int64 = 0, session: String? = nil, cwd: String? = nil
  ) -> ProcessRecord {
    let split: SplitFigures? =
      uid == 501
      ? SplitFigures(
        privateResident: rss * 3 / 5, privateCompressed: compressed * 4 / 5,
        sharedResident: rss * 2 / 5, sharedSplit: rss / 10, sharedCompressedSplit: compressed / 20,
        largestSharedAlsoIn: Int(pid % 7) + 2)
      : nil
    return ProcessRecord(
      pid: pid, ppid: ppid, uid: uid, name: String(path.split(separator: "/").last ?? ""), path: path,
      args: args ?? path, app: outermostApp(path: path), session: session, cwd: cwd, xpcService: nil,
      rss: rss, footprint: rss * 9 / 10 + compressed, compressed: compressed, split: split)
  }

  private static let processes: [ProcessRecord] = [
    proc(1, 0, 0, "/sbin/launchd", rss: 24 * mb),
    proc(88, 1, 0, "/usr/libexec/logd", rss: 41 * mb, compressed: 9 * mb),
    proc(95, 1, 0, "/System/Library/CoreServices/windowd", "windowd -daemon", rss: 1_210 * mb, compressed: 310 * mb),
    proc(102, 1, 0, "/usr/libexec/configd", rss: 12 * mb),
    proc(110, 1, 0, "/System/Library/CoreServices/indexd", rss: 385 * mb, compressed: 140 * mb),
    proc(120, 1, 0, "/System/Library/CoreServices/powerd", rss: 6 * mb),
    proc(131, 1, 0, "/usr/sbin/securityd", rss: 18 * mb, compressed: 2 * mb),
    proc(145, 1, 0, "/usr/libexec/netd", rss: 22 * mb),
    proc(160, 1, 0, "/usr/libexec/diskd", rss: 9 * mb),
    proc(170, 1, 0, "/System/Library/CoreServices/backupd", rss: 142 * mb, compressed: 64 * mb),
    proc(210, 1, 205, "/usr/libexec/locationd", rss: 28 * mb, compressed: 4 * mb),
    proc(220, 1, 202, "/usr/sbin/audiod", rss: 64 * mb, compressed: 11 * mb),
    proc(230, 1, 260, "/usr/sbin/spoold", rss: 7 * mb),
    proc(240, 1, 266, "/usr/libexec/timed", rss: 5_120 * kb),
    proc(250, 1, 265, "/usr/sbin/mdnsd", rss: 11 * mb, compressed: 1 * mb),
    proc(400, 1, 501, "/System/Library/CoreServices/Desktop.app/Contents/MacOS/Desktop", rss: 182 * mb, compressed: 30 * mb),
    proc(410, 1, 501, "/System/Library/CoreServices/Files.app/Contents/MacOS/Files", rss: 224 * mb, compressed: 48 * mb),
    proc(500, 1, 501, "\(browser)/MacOS/Browser", rss: 655 * mb, compressed: 120 * mb),
    proc(501, 500, 501, helper(browser, "Browser", "GPU"), "Browser Helper (GPU) --type=gpu", rss: 420 * mb, compressed: 35 * mb),
    proc(502, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 1_940 * mb, compressed: 380 * mb),
    proc(503, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 820 * mb, compressed: 150 * mb),
    proc(504, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 512 * mb, compressed: 96 * mb),
    proc(505, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 260 * mb, compressed: 70 * mb),
    proc(506, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 141 * mb),
    proc(507, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 92 * mb, compressed: 22 * mb),
    proc(508, 500, 501, helper(browser, "Browser", "Renderer"), "Browser Helper (Renderer) --type=renderer", rss: 46 * mb),
    proc(509, 500, 501, helper(browser, "Browser", "Network"), "Browser Helper (Network) --type=utility", rss: 61 * mb, compressed: 8 * mb),
    proc(600, 1, 501, "\(editor)/MacOS/Editor", rss: 484 * mb, compressed: 62 * mb),
    proc(601, 600, 501, helper(editor, "Editor", "Plugin"), "Editor Helper (Plugin) --extensions", rss: 905 * mb, compressed: 140 * mb),
    proc(602, 600, 501, helper(editor, "Editor", "Renderer"), "Editor Helper (Renderer) --type=renderer", rss: 352 * mb, compressed: 44 * mb),
    proc(603, 601, 501, "\(editor)/Resources/bin/language-server", "language-server --stdio", rss: 1_130 * mb, compressed: 210 * mb),
    proc(700, 1, 501, "/Applications/Mail.app/Contents/MacOS/Mail", rss: 312 * mb, compressed: 92 * mb),
    proc(701, 700, 501, "/Applications/Mail.app/Contents/XPCServices/Mail Fetcher.xpc/Contents/MacOS/Mail Fetcher", rss: 41 * mb),
    proc(710, 1, 501, "/Applications/Music.app/Contents/MacOS/Music", rss: 262 * mb, compressed: 140 * mb),
    proc(711, 710, 501, "/Applications/Music.app/Contents/XPCServices/Music Decoder.xpc/Contents/MacOS/Music Decoder", rss: 35 * mb, compressed: 3 * mb),
    proc(720, 1, 501, "\(chat)/MacOS/Chat", rss: 418 * mb, compressed: 180 * mb),
    proc(721, 720, 501, helper(chat, "Chat", "Renderer"), "Chat Helper (Renderer) --type=renderer", rss: 612 * mb, compressed: 150 * mb),
    proc(722, 720, 501, helper(chat, "Chat", "GPU"), "Chat Helper (GPU) --type=gpu", rss: 181 * mb),
    proc(800, 1, 501, "/Applications/Containers.app/Contents/MacOS/Containers", rss: 221 * mb, compressed: 40 * mb),
    proc(801, 800, 501, "/Applications/Containers.app/Contents/Resources/bin/vm-runtime", "vm-runtime --cpus 4 --memory 6g", rss: 4_300 * mb, compressed: 620 * mb),
    proc(900, 1, 501, "/Applications/Term.app/Contents/MacOS/Term", rss: 148 * mb, compressed: 12 * mb),
    proc(910, 900, 501, "/bin/zsh", "-zsh", rss: 3_200 * kb),
    proc(911, 910, 501, "/usr/local/bin/claude", "claude", rss: 424 * mb, compressed: 38 * mb),
    proc(912, 911, 501, "/usr/local/bin/node", "node mcp-server.js", rss: 118 * mb, compressed: 6 * mb, session: sessionA, cwd: projectA),
    proc(913, 911, 501, "/bin/zsh", "/bin/zsh -c make test", rss: 4_100 * kb, session: sessionA, cwd: projectA),
    proc(914, 913, 501, "/usr/local/bin/buildtool", "buildtool test --jobs 8", rss: 1_420 * mb, compressed: 96 * mb, session: sessionA, cwd: projectA),
    proc(920, 900, 501, "/bin/zsh", "-zsh", rss: 3_100 * kb),
    proc(921, 920, 501, "/usr/local/bin/claude", "claude --continue", rss: 381 * mb, compressed: 27 * mb),
    proc(922, 921, 501, "/usr/local/bin/node", "node mcp-server.js", rss: 96 * mb, session: sessionB, cwd: projectB),
    proc(923, 921, 501, "/usr/bin/python3", "python3 -m pytest", rss: 212 * mb, compressed: 18 * mb, session: sessionB, cwd: projectB),
    proc(924, 1, 501, "/usr/local/bin/node", "node dev-server.js --port 3000", rss: 163 * mb, compressed: 14 * mb, session: sessionB, cwd: projectB),
    proc(930, 900, 501, "/bin/zsh", "-zsh", rss: 2_900 * kb),
    proc(940, 1, 501, "/usr/local/bin/dbserver", "dbserver -D /Users/example/data", rss: 905 * mb, compressed: 250 * mb),
    proc(941, 940, 501, "/usr/local/bin/dbserver", "dbserver: checkpointer", rss: 62 * mb),
    proc(942, 940, 501, "/usr/local/bin/dbserver", "dbserver: writer", rss: 58 * mb, compressed: 5 * mb),
    proc(943, 940, 501, "/usr/local/bin/dbserver", "dbserver: autovacuum", rss: 44 * mb),
    proc(950, 1, 501, "/usr/local/bin/sync-agent", "sync-agent --daemon", rss: 52 * mb, compressed: 7 * mb),
  ]

  public static func snapshot() -> Snapshot {
    Snapshot(
      processes: processes,
      system: SystemTotals(used: 24 * gb, compressor: 3 * gb, physical: 32 * gb, swapUsed: 1 * gb, swapTotal: 4 * gb),
      inspected: processes.count { $0.split != nil },
      collectedIn: .milliseconds(850))
  }
}
