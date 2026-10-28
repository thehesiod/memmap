import Darwin
import Testing

@testable import MemmapCore

@Test func classifiesRegions() {
  var t = RegionTally()
  t.add(shareMode: 2, refCount: 1, objectID: 7, residentPages: 10, nowPrivatePages: 0, compressedPages: 2, pageSize: 1)
  t.add(shareMode: 1, refCount: 1, objectID: 8, residentPages: 4, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  t.add(shareMode: 1, refCount: 3, objectID: 9, residentPages: 6, nowPrivatePages: 2, compressedPages: 1, pageSize: 1)
  t.add(shareMode: 4, refCount: 2, objectID: 0, residentPages: 5, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  t.add(shareMode: 5, refCount: 2, objectID: 10, residentPages: 8, nowPrivatePages: 0, compressedPages: 3, pageSize: 1)
  t.add(shareMode: 3, refCount: 0, objectID: 11, residentPages: 99, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  #expect(t.privateResident == 10 + 4 + 2 + 5 && t.privateCompressed == 2)
  #expect(t.shared[9]! == (4, 1) && t.shared[10]! == (8, 3) && t.shared[11] == nil)
}

@Test func scalesPagesByPageSizeWithoutOverflow() {
  var t = RegionTally()
  t.add(shareMode: 2, refCount: 1, objectID: 1, residentPages: UInt32.max, nowPrivatePages: 0, compressedPages: UInt32.max, pageSize: 16384)
  #expect(t.privateResident == Int64(UInt32.max) * 16384)
}

@Test func splitsSharedObjectsEvenly() {
  var a = RegionTally()
  var b = RegionTally()
  a.add(shareMode: 4, refCount: 2, objectID: 1, residentPages: 100, nowPrivatePages: 0, compressedPages: 10, pageSize: 1)
  a.add(shareMode: 4, refCount: 1, objectID: 2, residentPages: 30, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  b.add(shareMode: 4, refCount: 2, objectID: 1, residentPages: 100, nowPrivatePages: 0, compressedPages: 10, pageSize: 1)
  let f = splitFigures([1: a, 2: b])
  #expect(f[1]!.sharedSplit == 50 + 30 && f[1]!.sharedCompressedSplit == 5 && f[1]!.sharedResident == 130)
  #expect(f[1]!.largestSharedAlsoIn == 1 && f[2]!.sharedSplit == 50)
}

@Test func largestSharedTieBreaksOnLowestObjectID() {
  var a = RegionTally()
  var b = RegionTally()
  a.add(shareMode: 4, refCount: 2, objectID: 5, residentPages: 10, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  a.add(shareMode: 4, refCount: 2, objectID: 3, residentPages: 10, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  b.add(shareMode: 4, refCount: 2, objectID: 5, residentPages: 10, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  b.add(shareMode: 4, refCount: 2, objectID: 7, residentPages: 10, nowPrivatePages: 0, compressedPages: 0, pageSize: 1)
  #expect(splitFigures([1: a, 2: b])[1]!.largestSharedAlsoIn == 0)
}

@Test func noSharedObjectsMeansNoSharing() {
  let f = splitFigures([1: RegionTally()])[1]!
  #expect(f.sharedSplit == 0 && f.largestSharedAlsoIn == 0)
}

@Test func walksOwnProcess() {
  let t = walkRegions(pid: getpid())!
  #expect(t.privateResident > 0)
  #expect(walkRegions(pid: 1) == nil)
}
