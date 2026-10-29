import Darwin

enum LibProc {
  static func listPIDs() -> [Int32] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [Int32](repeating: 0, count: Int(count) * 2)
    let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
    guard filled > 0 else { return [] }
    return pids.prefix(Int(filled)).filter { $0 > 0 }
  }

  static func bsdInfo(_ pid: Int32) -> (ppid: Int32, uid: UInt32)? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return (Int32(info.pbi_ppid), info.pbi_uid)
  }

  static func residentSize(_ pid: Int32) -> Int64? {
    var info = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
    return Int64(clamping: info.pti_resident_size)
  }

  static func physFootprint(_ pid: Int32) -> Int64? {
    var info = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
      }
    }
    guard status == 0 else { return nil }
    return Int64(clamping: info.ri_phys_footprint)
  }

  static func executablePath(_ pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
  }

  static func procArgs(_ pid: Int32) -> ProcArgs? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
    return parseProcArgs2(Array(buffer.prefix(size)))
  }
}
