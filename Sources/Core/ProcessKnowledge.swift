import Foundation

/// 常见磁盘占用者的可读说明，帮助用户理解"这是什么在占我的盘"
public enum ProcessKnowledge {

    /// 返回进程名对应的说明（已本地化），未知进程返回 nil
    public static func describe(name: String) -> String? {
        switch name {
        case "mdworker_shared", "mdworker", "mdworker2":
            return L("Spotlight is building its index")
        case "mds", "mds_stores":
            return L("Spotlight metadata store")
        case "quicklookd", "quicklookUIService", "com.apple.quicklook.ThumbnailsAgent":
            return L("Finder preview / thumbnail generation")
        case "Finder":
            return L("A Finder window or the Desktop is on this volume")
        case "backupd", "backupd-helper":
            return L("Time Machine backup")
        case "bird", "cloudd", "fileproviderd", "fileprovider_aux":
            return L("iCloud / file provider sync")
        case "photoanalysisd", "mediaanalysisd":
            return L("Photos / media analysis")
        case "fseventsd":
            return L("File system events log")
        case "caffeinate":
            return L("Power management keep-awake")
        case "login":
            return L("Terminal session wrapper — close that terminal tab, or cd out of the volume inside it")
        case "zsh", "bash", "fish", "-zsh", "-bash":
            return L("Terminal shell — its working directory is on this volume; cd out or close the tab")
        default:
            return nil
        }
    }
}
