import Darwin
import Foundation

/// 进程终止工具：SIGTERM 优雅退出，SIGKILL 强制
public enum ProcessKiller {

    /// 优雅终止（SIGTERM）。返回 nil 表示信号已送达，否则返回错误文案
    public static func terminate(_ pid: pid_t) -> String? {
        send(pid, SIGTERM)
    }

    /// 强制终止（SIGKILL）。返回 nil 表示信号已送达，否则返回错误文案
    public static func forceKill(_ pid: pid_t) -> String? {
        send(pid, SIGKILL)
    }

    /// 进程是否存活
    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private static func send(_ pid: pid_t, _ sig: Int32) -> String? {
        if kill(pid, sig) == 0 { return nil }
        let e = errno
        if e == EPERM { return L("Permission denied (root process — sudo required)") }
        if e == ESRCH { return L("Process already exited") }
        return String(cString: strerror(e))
    }
}
