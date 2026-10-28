import ctypes
import os
import re
import subprocess
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import PurePosixPath

PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
MAX_ARGS_CHARS = 4000

_libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
_libc = ctypes.CDLL(None)

SM_COW, SM_PRIVATE, SM_EMPTY, SM_SHARED, SM_TRUESHARED, SM_PRIVATE_ALIASED, SM_SHARED_ALIASED, SM_LARGE_PAGE = range(1, 9)
SHARED_MODES = {SM_SHARED, SM_TRUESHARED, SM_SHARED_ALIASED}
PRIVATE_MODES = {SM_PRIVATE, SM_PRIVATE_ALIASED, SM_LARGE_PAGE}


class _RusageInfoV0(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "user_time system_time pkg_idle_wkups interrupt_wkups pageins wired_size "
            "resident_size phys_footprint proc_start_abstime proc_exit_abstime"
        ).split()
    ]


class _SubmapInfo64(ctypes.Structure):
    _pack_ = 4
    _fields_ = [
        ("protection", ctypes.c_int),
        ("max_protection", ctypes.c_int),
        ("inheritance", ctypes.c_uint),
        ("offset", ctypes.c_uint64),
        ("user_tag", ctypes.c_uint),
        ("pages_resident", ctypes.c_uint),
        ("pages_shared_now_private", ctypes.c_uint),
        ("pages_swapped_out", ctypes.c_uint),
        ("pages_dirtied", ctypes.c_uint),
        ("ref_count", ctypes.c_uint),
        ("shadow_depth", ctypes.c_ushort),
        ("external_pager", ctypes.c_ubyte),
        ("share_mode", ctypes.c_ubyte),
        ("is_submap", ctypes.c_int),
        ("behavior", ctypes.c_int),
        ("object_id", ctypes.c_uint),
        ("user_wired_count", ctypes.c_ushort),
        ("pages_reusable", ctypes.c_uint),
        ("object_id_full", ctypes.c_uint64),
    ]


_SUBMAP_INFO_COUNT = ctypes.sizeof(_SubmapInfo64) // 4
_mach_task_self = ctypes.c_uint.in_dll(_libc, "mach_task_self_").value
_libc.mach_vm_region_recurse.argtypes = [
    ctypes.c_uint,
    ctypes.POINTER(ctypes.c_uint64),
    ctypes.POINTER(ctypes.c_uint64),
    ctypes.POINTER(ctypes.c_uint),
    ctypes.POINTER(_SubmapInfo64),
    ctypes.POINTER(ctypes.c_uint),
]


@dataclass
class Proc:
    pid: int
    ppid: int
    uid: int
    name: str
    path: str
    args: str
    app: str | None
    session: str | None
    cwd: str | None
    xpc_service: str | None
    rss: int
    footprint: int
    compressed: int
    private_resident: int | None = None
    private_compressed: int | None = None
    shared_resident: int | None = None
    shared_split: int | None = None
    shared_compressed_split: int | None = None
    shared_with: int | None = None


@dataclass
class Snapshot:
    procs: list[Proc]
    is_root: bool
    split_available: bool
    inspected: int
    system: dict[str, int] = field(default_factory=dict)

    def to_json(self) -> dict:
        return {
            "procs": [asdict(p) for p in self.procs],
            "is_root": self.is_root,
            "split_available": self.split_available,
            "inspected": self.inspected,
            "system": self.system,
        }


_SIZE_RE = re.compile(r"^([\d.]+)([BKMGT]?)")
_UNITS = {"": 1, "B": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30, "T": 1 << 40}


def _parse_size(text: str) -> int:
    if not (m := _SIZE_RE.match(text)):
        return 0
    return int(float(m[1]) * _UNITS[m[2]])


def _outermost_app(path: str) -> str | None:
    for part in PurePosixPath(path).parts:
        if part.endswith(".app"):
            return part.removesuffix(".app")
    return None


def _read_ps() -> dict[int, tuple[int, int, int, str]]:
    out = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,uid=,rss=,comm="], capture_output=True, text=True, check=True
    ).stdout
    rows = {}
    for line in out.splitlines():
        pid, ppid, uid, rss, comm = line.split(None, 4)
        rows[int(pid)] = (int(ppid), int(uid), int(rss) * 1024, comm)
    return rows


def _read_args() -> dict[int, str]:
    out = subprocess.run(["ps", "-axww", "-o", "pid=,args="], capture_output=True, text=True, check=True).stdout
    rows = {}
    for line in out.splitlines():
        pid, _, args = line.strip().partition(" ")
        rows[int(pid)] = args.strip()[:MAX_ARGS_CHARS]
    return rows


_SESSION_RE = re.compile(r"\bCLAUDE_CODE_SESSION_ID=([0-9a-f-]{36})")
_PWD_RE = re.compile(r"\bPWD=(\S+)")
_XPC_RE = re.compile(r"\bXPC_SERVICE_NAME=(\S+)")


def _env_value(pattern: re.Pattern[str], text: str) -> str | None:
    return m[1] if (m := pattern.search(text)) else None


def _read_env() -> dict[int, tuple[str | None, str | None, str | None]]:
    out = subprocess.run(["ps", "-axwwE", "-o", "pid=,command="], capture_output=True, text=True, check=True).stdout
    rows = {}
    for line in out.splitlines():
        pid, _, rest = line.strip().partition(" ")
        rows[int(pid)] = (_env_value(_SESSION_RE, rest), _env_value(_PWD_RE, rest), _env_value(_XPC_RE, rest))
    return rows


def _read_top() -> tuple[dict[int, tuple[int, int]], dict[str, int]]:
    out = subprocess.run(
        ["top", "-l", "1", "-stats", "pid,mem,cmprs"], capture_output=True, text=True, check=True
    ).stdout
    per_pid: dict[int, tuple[int, int]] = {}
    system: dict[str, int] = {}
    in_table = False
    for line in out.splitlines():
        if line.startswith("PhysMem:"):
            if m := re.search(r"([\d.]+[BKMGT]) used", line):
                system["used"] = _parse_size(m[1])
            if m := re.search(r"([\d.]+[BKMGT]) compressor", line):
                system["compressor"] = _parse_size(m[1])
            if m := re.search(r"([\d.]+[BKMGT]) unused", line):
                system["unused"] = _parse_size(m[1])
        elif line.startswith("PID"):
            in_table = True
        elif in_table and (fields := line.split()) and fields[0].isdigit():
            per_pid[int(fields[0])] = (_parse_size(fields[1]), _parse_size(fields[2]))
    return per_pid, system


def _read_swap() -> dict[str, int]:
    out = subprocess.run(["sysctl", "-n", "vm.swapusage", "hw.memsize"], capture_output=True, text=True, check=True).stdout
    swap_line, memsize = out.splitlines()
    swap = {}
    for key in ("total", "used"):
        if m := re.search(rf"{key} = ([\d.]+[BKMGT])", swap_line):
            swap[f"swap_{key}"] = _parse_size(m[1])
    swap["physical"] = int(memsize)
    return swap


def _footprint(pid: int) -> int | None:
    info = _RusageInfoV0()
    if _libproc.proc_pid_rusage(pid, 0, ctypes.byref(info)) != 0:
        return None
    return info.phys_footprint


@dataclass
class _Regions:
    private_resident: int = 0
    private_compressed: int = 0
    shared: dict[int, list[int]] = field(default_factory=lambda: defaultdict(lambda: [0, 0]))

    def add(self, mode: int, ref_count: int, object_id: int, resident_pages: int, now_private_pages: int, compressed_pages: int) -> None:
        resident = resident_pages * PAGE_SIZE
        compressed = compressed_pages * PAGE_SIZE
        if mode in PRIVATE_MODES or (mode == SM_COW and ref_count == 1) or not object_id:
            self.private_resident += resident
            self.private_compressed += compressed
        elif mode == SM_COW:
            now_private = now_private_pages * PAGE_SIZE
            self.private_resident += now_private
            bucket = self.shared[object_id]
            bucket[0] += resident - now_private
            bucket[1] += compressed
        elif mode in SHARED_MODES:
            bucket = self.shared[object_id]
            bucket[0] += resident
            bucket[1] += compressed


class _ProcRegionInfo(ctypes.Structure):
    _fields_ = [
        *((name, ctypes.c_uint32) for name in ("protection", "max_protection", "inheritance", "flags")),
        ("offset", ctypes.c_uint64),
        *(
            (name, ctypes.c_uint32)
            for name in (
                "behavior user_wired_count user_tag pages_resident pages_shared_now_private pages_swapped_out "
                "pages_dirtied ref_count shadow_depth share_mode private_pages_resident shared_pages_resident obj_id depth"
            ).split()
        ),
        ("address", ctypes.c_uint64),
        ("size", ctypes.c_uint64),
    ]


PROC_PIDREGIONINFO = 7


def _walk_regions_libproc(pid: int) -> _Regions | None:
    """Needs only that the caller owns the process, unlike task_read_for_pid, but doesn't descend into submaps."""
    regions = _Regions()
    info = _ProcRegionInfo()
    address = 0
    while _libproc.proc_pidinfo(pid, PROC_PIDREGIONINFO, ctypes.c_uint64(address), ctypes.byref(info), ctypes.sizeof(info)) > 0:
        regions.add(
            info.share_mode, info.ref_count, info.obj_id, info.pages_resident, info.pages_shared_now_private, info.pages_swapped_out
        )
        if (next_address := info.address + info.size) <= address:
            break
        address = next_address
    return regions if address else None


def _walk_regions(pid: int) -> _Regions | None:
    task = ctypes.c_uint()
    if pid == os.getpid():
        task.value = _mach_task_self
    elif _libc.task_read_for_pid(_mach_task_self, pid, ctypes.byref(task)) != 0:
        return None
    regions = _Regions()
    address = ctypes.c_uint64(0)
    size = ctypes.c_uint64(0)
    depth = ctypes.c_uint(0)
    info = _SubmapInfo64()
    count = ctypes.c_uint()
    try:
        while True:
            count.value = _SUBMAP_INFO_COUNT
            if _libc.mach_vm_region_recurse(task, address, size, depth, info, count) != 0:
                break
            if info.is_submap:
                depth.value += 1
                continue
            regions.add(
                info.share_mode,
                info.ref_count,
                info.object_id_full,
                info.pages_resident,
                info.pages_shared_now_private,
                info.pages_swapped_out,
            )
            address.value += size.value
    finally:
        if task.value != _mach_task_self:
            _libc.mach_port_deallocate(_mach_task_self, task)
    return regions


def collect(split: bool) -> Snapshot:
    ps_rows = _read_ps()
    args_rows = _read_args()
    env_rows = _read_env()
    top_rows, system = _read_top()
    system |= _read_swap()
    is_root = os.geteuid() == 0

    procs: dict[int, Proc] = {}
    for pid, (ppid, uid, rss, comm) in ps_rows.items():
        top_mem, top_cmprs = top_rows.get(pid, (0, 0))
        session, cwd, xpc_service = env_rows.get(pid, (None, None, None))
        procs[pid] = Proc(
            pid=pid,
            ppid=ppid,
            uid=uid,
            name=PurePosixPath(comm).name or comm,
            path=comm,
            args=args_rows.get(pid, comm),
            app=_outermost_app(comm),
            session=session,
            cwd=cwd,
            xpc_service=xpc_service,
            rss=rss,
            footprint=_footprint(pid) or top_mem,
            compressed=top_cmprs,
        )

    inspected = 0
    if split:
        walk = _walk_regions if is_root else _walk_regions_libproc
        walked = {pid: r for pid in procs if (r := walk(pid)) is not None}
        inspected = len(walked)
        mappers: dict[int, int] = defaultdict(int)
        for regions in walked.values():
            for obj in regions.shared:
                mappers[obj] += 1
        for pid, regions in walked.items():
            proc = procs[pid]
            proc.private_resident = regions.private_resident
            proc.private_compressed = regions.private_compressed
            proc.shared_resident = sum(r for r, _ in regions.shared.values())
            proc.shared_split = int(sum(r / mappers[obj] for obj, (r, _) in regions.shared.items()))
            proc.shared_compressed_split = int(sum(c / mappers[obj] for obj, (_, c) in regions.shared.items()))
            largest = max(regions.shared, key=lambda obj: regions.shared[obj][0], default=None)
            proc.shared_with = mappers[largest] - 1 if largest is not None else 0

    return Snapshot(
        procs=list(procs.values()),
        is_root=is_root,
        split_available=True,
        inspected=inspected,
        system=system,
    )
