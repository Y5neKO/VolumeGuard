import Foundation

/// 常见磁盘占用者的可读说明，帮助用户理解"这是什么在占我的盘"
public enum ProcessKnowledge {

    /// 返回进程名对应的人类可读说明，未知进程返回 nil
    public static func describe(name: String) -> String? {
        switch name {
        case "mdworker_shared", "mdworker", "mdworker2":
            return "Spotlight 正在建立索引"
        case "mds", "mds_stores":
            return "Spotlight 元数据存储"
        case "quicklookd", "quicklookUIService", "com.apple.quicklook.ThumbnailsAgent":
            return "访达预览/缩略图生成"
        case "Finder":
            return "访达窗口或桌面位于卷上"
        case "backupd", "backupd-helper":
            return "Time Machine 备份"
        case "bird", "cloudd", "fileproviderd", "fileprovider_aux":
            return "iCloud/文件提供程序同步"
        case "photoanalysisd", "mediaanalysisd":
            return "照片/媒体库分析"
        case "fseventsd":
            return "文件系统事件日志"
        case "caffeinate":
            return "电源管理保持唤醒"
        default:
            return nil
        }
    }
}
