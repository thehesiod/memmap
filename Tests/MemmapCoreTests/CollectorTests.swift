import Foundation
import Testing

@testable import MemmapCore

@Test func collectsLiveSnapshot() async throws {
  let snap = try await Collector().collect(split: true)
  let me = try #require(snap.processes.first { $0.pid == getpid() })
  #expect(me.rss > 0 && me.footprint > 0 && !me.args.isEmpty && me.split != nil)
  #expect(snap.processes.contains { $0.pid == 1 && $0.split == nil && $0.rss > 0 })
  #expect(snap.system.physical > 0 && snap.system.used > 0)
  #expect(snap.inspected > 0 && snap.inspected < snap.processes.count)
}

@Test func collectsWithoutSplit() async throws {
  let snap = try await Collector().collect(split: false)
  #expect(snap.inspected == 0)
  #expect(snap.processes.allSatisfy { $0.split == nil })
}
