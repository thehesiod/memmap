import Testing
@testable import MemmapCore

@Test func parsesTopSizes() {
  #expect(parseSize("88M") == 88 << 20)
  #expect(parseSize("7873K") == 7873 << 10)
  #expect(parseSize("23G") == 23 << 30)
  #expect(parseSize("0B") == 0)
  #expect(parseSize("1472M+") == 1472 << 20)
  #expect(parseSize("-") == 0)
}

@Test func parsesPSWithSpacesInCommand() {
  let rows = parsePS("    1     0     0  15056 /sbin/launchd\n  612     1   501  117760 /Applications/Example App.app/Contents/MacOS/Example App\n")
  #expect(rows[612] == PSRow(ppid: 1, uid: 501, rss: 117760 * 1024, comm: "/Applications/Example App.app/Contents/MacOS/Example App"))
}

@Test func parsesTopTableAndPhysMem() {
  let out = """
  PhysMem: 47G used (5480M wired, 23G compressor), 154M unused.
  PID    MEM   CMPRS
  5230   23G   14G
  35000  1472M 672M
  """
  let top = parseTop(out)
  #expect(top.used == 47 << 30 && top.compressor == 23 << 30)
  #expect(top.perPID[35000]?.footprint == 1472 << 20 && top.perPID[35000]?.compressed == 672 << 20)
}

@Test func parsesSwap() {
  let swap = parseSwapUsage("total = 6144.00M  used = 4885.00M  free = 1259.00M  (encrypted)")
  #expect(swap.total == 6144 << 20 && swap.used == 4885 << 20)
}

@Test func findsOutermostApp() {
  #expect(outermostApp(path: "/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper") == "Example")
  #expect(outermostApp(path: "/usr/libexec/logd") == nil)
}

@Test func truncatesArgs() {
  let long = String(repeating: "x", count: 5000)
  #expect(parsePSArgs("  42 \(long)\n")[42]?.count == 4000)
}
