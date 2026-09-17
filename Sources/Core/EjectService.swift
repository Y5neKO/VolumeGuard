import Foundation

/// 磁盘弹出服务：调用系统 /usr/sbin/diskutil（Finder 同款底层）。
/// 相比 DADiskEject：对 dmg/物理盘行为一致，busy 被拒时错误输出
/// 自带占用进程 PID 与路径，信息量远超 DiskArbitration 的 dissent 码。
public enum EjectService {

    /// 弹出指定挂载点（阻塞至完成，调用方自行放后台线程）
    /// - Returns: nil 表示成功；否则为错误描述
    public static func eject(mountPoint: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", mountPoint]
        process.environment = ["PATH": "/usr/sbin:/usr/bin:/sbin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return "无法启动 diskutil：\(error.localizedDescription)"
        }
        process.waitUntilExit()

        if process.terminationStatus == 0 { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty
            ? "弹出失败（diskutil 退出码 \(process.terminationStatus)）"
            : output
    }
}
