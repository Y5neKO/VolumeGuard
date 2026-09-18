import Darwin
import Foundation

// MARK: - 数据模型

/// 进程占用卷内路径的一条记录
public struct OccupiedFile: Sendable, Hashable {
    public enum Source: String, Sendable {
        /// 打开的文件描述符
        case fd
        /// 进程工作目录
        case cwd
        /// 进程根目录（chroot，少见）
        case rdir
    }

    /// 被占用的文件/目录完整路径
    public let path: String
    /// 占用来源
    public let source: Source
}

/// 占用某个卷的进程
public struct OccupyingProcess: Sendable, Hashable, Identifiable {
    /// Table 等列表控件的行标识
    public var id: pid_t { pid }

    public let pid: pid_t
    /// 进程显示名（取可执行文件名，拿不到时回退内核 comm）
    public let name: String
    /// 可执行文件完整路径（当前用户权限拿不到时为 nil）
    public let executablePath: String?
    public let uid: uid_t
    /// 是否为扫描进程自身
    public let isSelf: Bool
    /// 该进程占用此卷的所有路径记录
    public let occupied: [OccupiedFile]
}

// MARK: - 扫描器

/// 卷占用扫描器：基于 libproc 枚举所有进程的打开文件与工作目录，
/// 找出引用目标卷内路径的进程。纯同步实现，调用方自行决定线程模型。
public enum VolumeScanner {

    /// 扫描指定挂载点，返回占用它的进程列表（按 PID 升序）
    /// - Note: 无 root 权限时只能看到当前用户进程的 fd 详情，root 占用会漏报
    public static func scan(mountPoint: String) -> [OccupyingProcess] {
        let prefix = normalize(mountPoint)
        var byPID: [pid_t: (name: String, execPath: String?, uid: uid_t, files: [OccupiedFile])] = [:]

        for pid in allPIDs() {
            var files: [OccupiedFile] = []

            // 1) 打开的文件描述符
            for path in openFilePaths(of: pid) where isOn(path, prefix) {
                files.append(OccupiedFile(path: path, source: .fd))
            }

            // 2) 工作目录 / 根目录——终端 cd 进卷里就是这类占用
            for (path, source) in vnodePaths(of: pid) where isOn(path, prefix) {
                files.append(OccupiedFile(path: path, source: source))
            }

            guard !files.isEmpty,
                  let info = procInfo(of: pid)
            else { continue }

            byPID[pid] = (
                info.execPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? info.comm,
                info.execPath,
                info.uid,
                // 同一进程同一 (路径, 来源) 去重
                Array(Set(files)).sorted {
                    ($0.source.rawValue, $0.path) < ($1.source.rawValue, $1.path)
                }
            )
        }

        return byPID.map { pid, v in
            OccupyingProcess(
                pid: pid,
                name: v.name,
                executablePath: v.execPath,
                uid: v.uid,
                isSelf: pid == getpid(),
                occupied: v.files
            )
        }
        .sorted { $0.pid < $1.pid }
    }

    /// 枚举本地卷挂载点（排除根卷与系统虚拟卷，即 /Volumes 下用户可见的盘）
    public static func localVolumeMountPoints() -> [String] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys) ?? []
        return urls.compactMap { url -> String? in
            guard let vals = try? url.resourceValues(forKeys: Set(keys)), vals.volumeIsLocal == true else {
                return nil
            }
            let mp = url.path
            guard mp != "/" else { return nil }
            guard !mp.hasPrefix("/System/"), !mp.hasPrefix("/private/") else { return nil }
            return mp
        }
        .sorted()
    }

    /// 按 PID 查询单个进程的基础信息（用于弹出失败时回查 dissent 进程）
    /// - Returns: 进程名、可执行路径、uid；进程已退出或不可见时为 nil
    public static func processSummary(pid: pid_t) -> (name: String, execPath: String?, uid: uid_t)? {
        guard let info = procInfo(of: pid) else { return nil }
        let name = info.execPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? info.comm
        return (name, info.execPath, info.uid)
    }

    // MARK: libproc 封装

    /// 全部存活进程 PID
    private static func allPIDs() -> [pid_t] {
        // 第一次传 NULL：返回当前 PID 个数
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n))
        // 第二次传字节大小：返回实际写入的 PID 个数
        let real = proc_listallpids(&pids, n * Int32(MemoryLayout<pid_t>.stride))
        guard real > 0 else { return [] }
        return Array(pids.prefix(Int(real)))
    }

    /// 进程以 vnode 方式打开的所有文件路径
    private static func openFilePaths(of pid: pid_t) -> [String] {
        // PROC_PIDLISTFDS 需要的字节数
        let need = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard need > 0 else { return [] } // 权限不足或进程已退出

        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(need) / MemoryLayout<proc_fdinfo>.stride)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, need)
        guard got > 0 else { return [] }

        // proc_info.h: PROX_FDTYPE_VNODE == 1（C 宏未导出到 Swift，字面量代替）
        let fdTypeVNode: UInt32 = 1

        var paths: [String] = []
        let fdCount = Int(got) / MemoryLayout<proc_fdinfo>.stride
        for i in 0..<fdCount {
            guard fds[i].proc_fdtype == fdTypeVNode else { continue }
            var info = vnode_fdinfowithpath()
            // fd 级 flavor 必须用 proc_pidfdinfo（proc_pidinfo 会把 flavor=2 当成
            // pid 级 PROC_PIDTASKALLINFO，返回 232 字节 taskallinfo）
            let r = proc_pidfdinfo(
                pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO,
                &info, Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
            )
            guard r > 0 else { continue }
            paths.append(cString(of: info.pvip.vip_path))
        }
        return paths
    }

    /// 进程工作目录与根目录
    private static func vnodePaths(of pid: pid_t) -> [(String, OccupiedFile.Source)] {
        var info = proc_vnodepathinfo()
        let r = proc_pidinfo(
            pid, PROC_PIDVNODEPATHINFO, 0,
            &info, Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        )
        guard r > 0 else { return [] }

        var out: [(String, OccupiedFile.Source)] = []
        let cwd = cString(of: info.pvi_cdir.vip_path)
        if !cwd.isEmpty { out.append((cwd, .cwd)) }
        let rdir = cString(of: info.pvi_rdir.vip_path)
        if !rdir.isEmpty { out.append((rdir, .rdir)) }
        return out
    }

    /// 进程基础信息
    private static func procInfo(of pid: pid_t) -> (comm: String, execPath: String?, uid: uid_t)? {
        var bsd = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.stride)) > 0 else {
            return nil
        }
        // sys/proc.h: SZOMB == 5，僵尸进程不持有 fd，不构成占用
        let szomb: UInt32 = 5
        guard bsd.pbi_status != szomb else { return nil }

        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let execPath: String? = proc_pidpath(pid, &buf, UInt32(MAXPATHLEN)) > 0
            ? String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : nil
        return (comm: cString(of: bsd.pbi_comm), execPath: execPath, uid: uid_t(bsd.pbi_uid))
    }

    // MARK: 工具

    /// 去掉末尾多余斜杠（保留根路径 "/"）
    private static func normalize(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// path 是否位于 prefix 卷内
    private static func isOn(_ path: String, _ prefix: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }

    /// C 定长字符数组（CChar 元组）转 Swift String
    private static func cString<T>(of value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
}
