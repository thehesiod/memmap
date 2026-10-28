import Foundation
import Testing
@testable import MemmapCore

@Test func parsesProcArgs2Layout() {
  var buf: [UInt8] = withUnsafeBytes(of: Int32(2).littleEndian, Array.init)
  for s in ["/bin/tool", "", "", "/bin/tool", "--flag", "PWD=/Users/example/project", "SECRET=x", "CLAUDE_CODE_SESSION_ID=abc", "XPC_SERVICE_NAME=0", ""] { buf += Array(s.utf8) + [0] }
  let parsed = parseProcArgs2(buf)!
  #expect(parsed.args == "/bin/tool --flag")
  #expect(parsed.env == ["PWD": "/Users/example/project", "CLAUDE_CODE_SESSION_ID": "abc", "XPC_SERVICE_NAME": "0"])
}

@Test func procArgs2SurvivesGarbageAndHugeArgs() {
  #expect(parseProcArgs2([1, 2]) == nil)
  var buf: [UInt8] = withUnsafeBytes(of: Int32(1).littleEndian, Array.init) + Array("/x".utf8) + [0, 0xff, 0xfe] + Array(repeating: UInt8(ascii: "a"), count: 6000) + [0]
  buf += [0]
  #expect((parseProcArgs2(buf)?.args.count ?? 0) <= 4000)
}

@Test func readsOwnProcess() {
  let me = getpid()
  #expect(LibProc.listPIDs().contains(me))
  #expect(LibProc.bsdInfo(me)?.uid == getuid())
  #expect((LibProc.residentSize(me) ?? 0) > 0 && (LibProc.physFootprint(me) ?? 0) > 0)
  #expect(LibProc.executablePath(me)?.isEmpty == false)
  #expect(LibProc.procArgs(me)?.args.isEmpty == false)
}

@Test func vanishedProcessReturnsNil() {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try! p.run(); p.waitUntilExit()
  #expect(LibProc.bsdInfo(p.processIdentifier) == nil && LibProc.procArgs(p.processIdentifier) == nil)
}
