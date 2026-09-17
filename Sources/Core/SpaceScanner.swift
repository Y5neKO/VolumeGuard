import Darwin
import Foundation

/// 目录大小排行条目
public struct DirectorySizeEntry: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let size: Int64
}

/// 磁盘空间分析：卷容量概况（statfs，秒出）+ 一级子目录大小并行统计
public enum SpaceScanner {

    /// 卷容量概况。free 为当前普通用户实际可用空间
    public static func volumeUsage(mountPoint: String) -> (total: Int64, free: Int64)? {
        var st = statfs()
        guard statfs(mountPoint, &st) == 0 else { return nil }
        let bsize = Int64(st.f_bsize)
        return (total: bsize * Int64(st.f_blocks), free: bsize * Int64(st.f_bavail))
    }

    /// 并行统计 root 下各一级子目录大小，每完成一个回调当前快照（按大小降序）。
    /// 取消通过 Task cancellation 传播，遍历循环内响应。
    public static func childDirectorySizes(
        at root: String,
        onUpdate: @escaping @Sendable ([DirectorySizeEntry]) -> Void
    ) async {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        let dirs = names
            .map { root + "/" + $0 }
            .filter { path in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }

        var results: [DirectorySizeEntry] = []
        results.reserveCapacity(dirs.count)

        await withTaskGroup(of: (String, Int64).self) { group in
            for dir in dirs {
                group.addTask { (dir, recursiveSize(dir)) }
            }
            for await (path, size) in group {
                results.append(DirectorySizeEntry(
                    path: path,
                    name: (path as NSString).lastPathComponent,
                    size: size
                ))
                onUpdate(results.sorted { $0.size > $1.size })
            }
        }
    }

    /// 递归统计目录磁盘占用（allocated size），不跟随符号链接
    private static func recursiveSize(_ path: String) -> Int64 {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)),
                  vals.isRegularFile == true
            else { continue }
            total += Int64(vals.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
