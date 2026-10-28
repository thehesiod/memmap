import Darwin

private enum ShareMode {
  static let cow = UInt32(SM_COW)
  static let empty = UInt32(SM_EMPTY)
  static let `private` = UInt32(SM_PRIVATE)
  static let privateAliased = UInt32(SM_PRIVATE_ALIASED)
  static let largePage = UInt32(SM_LARGE_PAGE)
  static let shared = UInt32(SM_SHARED)
  static let trueshared = UInt32(SM_TRUESHARED)
  static let sharedAliased = UInt32(SM_SHARED_ALIASED)
}

public struct RegionTally: Sendable {
  public var privateResident: Int64 = 0
  public var privateCompressed: Int64 = 0
  public var shared: [UInt64: (resident: Int64, compressed: Int64)] = [:]

  public init() {}

  public mutating func add(
    shareMode: UInt32, refCount: UInt32, objectID: UInt64, residentPages: UInt32,
    nowPrivatePages: UInt32, compressedPages: UInt32, pageSize: Int64
  ) {
    let resident = Int64(residentPages) * pageSize
    let compressed = Int64(compressedPages) * pageSize
    switch shareMode {
    case ShareMode.empty where objectID != 0:
      return
    case ShareMode.private, ShareMode.privateAliased, ShareMode.largePage:
      privateResident += resident
      privateCompressed += compressed
    case _ where objectID == 0 || (shareMode == ShareMode.cow && refCount == 1):
      privateResident += resident
      privateCompressed += compressed
    case ShareMode.cow:
      let nowPrivate = Int64(nowPrivatePages) * pageSize
      privateResident += nowPrivate
      let bucket = shared[objectID] ?? (0, 0)
      shared[objectID] = (bucket.resident + resident - nowPrivate, bucket.compressed + compressed)
    case ShareMode.shared, ShareMode.trueshared, ShareMode.sharedAliased:
      let bucket = shared[objectID] ?? (0, 0)
      shared[objectID] = (bucket.resident + resident, bucket.compressed + compressed)
    default:
      return
    }
  }
}

public func walkRegions(pid: Int32) -> RegionTally? {
  var tally = RegionTally()
  var info = proc_regioninfo()
  let size = Int32(MemoryLayout<proc_regioninfo>.size)
  let pageSize = Int64(sysconf(_SC_PAGESIZE))
  var address: UInt64 = 0
  while proc_pidinfo(pid, PROC_PIDREGIONINFO, address, &info, size) > 0 {
    tally.add(
      shareMode: UInt32(info.pri_share_mode), refCount: info.pri_ref_count,
      objectID: UInt64(info.pri_obj_id), residentPages: info.pri_pages_resident,
      nowPrivatePages: info.pri_pages_shared_now_private,
      compressedPages: info.pri_pages_swapped_out, pageSize: pageSize)
    let (next, overflow) = info.pri_address.addingReportingOverflow(info.pri_size)
    if overflow || next <= address { break }
    address = next
  }
  return address == 0 ? nil : tally
}

public func splitFigures(_ tallies: [Int32: RegionTally]) -> [Int32: SplitFigures] {
  var mappers: [UInt64: Int] = [:]
  for tally in tallies.values {
    for object in tally.shared.keys { mappers[object, default: 0] += 1 }
  }
  return tallies.mapValues { tally in
    var resident: Int64 = 0
    var residentSplit = 0.0
    var compressedSplit = 0.0
    var largest: (object: UInt64, resident: Int64)?
    for object in tally.shared.keys.sorted() {
      let (r, c) = tally.shared[object]!
      let count = Double(mappers[object]!)
      resident += r
      residentSplit += Double(r) / count
      compressedSplit += Double(c) / count
      if largest.map({ r > $0.resident }) ?? true { largest = (object, r) }
    }
    return SplitFigures(
      privateResident: tally.privateResident, privateCompressed: tally.privateCompressed,
      sharedResident: resident, sharedSplit: Int64(residentSplit),
      sharedCompressedSplit: Int64(compressedSplit),
      largestSharedAlsoIn: largest.map { mappers[$0.object]! - 1 } ?? 0)
  }
}
