import Core
import Foundation

// volumeguard CLI
// 用法:
//   volumeguard                     扫描所有本地卷
//   volumeguard <挂载点>             扫描指定卷，如 volumeguard /Volumes/Y5Sec
//   volumeguard --eject <挂载点>     弹出指定卷

let args = CommandLine.arguments

if args.count > 2, args[1] == "--eject" {
    if let err = EjectService.eject(mountPoint: args[2]) {
        print("弹出失败: \(err)")
        exit(1)
    }
    print("已弹出 \(args[2])")
    exit(0)
}

let mountPoints = args.count > 1 ? [args[1]] : VolumeScanner.localVolumeMountPoints()

guard !mountPoints.isEmpty else {
    print("没有发现可扫描的本地卷")
    exit(0)
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

for mp in mountPoints {
    let processes = VolumeScanner.scan(mountPoint: mp)

    print("== \(mp) ==")
    if processes.isEmpty {
        print("  无占用")
        print()
        continue
    }

    print("\(pad("PID", 8))\(pad("进程", 22))\(pad("UID", 8))占用")
    for p in processes {
        let name = p.isSelf ? "\(p.name) (self)" : p.name
        for (i, f) in p.occupied.enumerated() {
            if i == 0 {
                print("\(pad(String(p.pid), 8))\(pad(name, 22))\(pad(String(p.uid), 8))[\(f.source.rawValue)] \(f.path)")
            } else {
                print("\(pad("", 38))[\(f.source.rawValue)] \(f.path)")
            }
        }
    }
    print("共 \(processes.count) 个进程占用")
    print()
}
