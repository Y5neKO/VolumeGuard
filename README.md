# VolumeGuard

<p align="center">
  <img src="docs/screenshots/icon.png" width="128" alt="VolumeGuard icon">
</p>

**macOS 移动硬盘/外置卷占用检测与弹出工具** —— 每次弹出移动硬盘都被"占用"却不知道是谁？VolumeGuard 一眼看穿所有占用进程，一键解除并弹出。

原生 Swift + SwiftUI，无第三方依赖，安装包不到 1 MB。

![screenshot](docs/screenshots/main.png)

## 功能

- **占用检测**：基于 `libproc` 枚举所有进程的打开文件描述符与工作目录，毫秒级定位占用者（实测 ~30ms，比 `lsof` 快 4 倍）
- **实时刷新**：1 秒轮询无感知刷新，检测与渲染分离，数据无变化时零重绘
- **一键解除**：两阶段策略——先全员 `SIGTERM`，800ms 后对仍在占用的自动补 `SIGKILL`；root 进程明确提示无权限
- **解除并弹出**：解除完成后自动弹出，插盘用完一键走人
- **常见占用者识别**：`mdworker`（Spotlight 索引）、`quicklookd`（缩略图）、`backupd`（Time Machine）、`bird`（iCloud 同步）等 10+ 类自动标注原因
- **菜单栏常驻**：托盘图标实时反映占用状态（有占用变感叹号），面板内就地解除/弹出
- **空间分析**：一级子目录大小并行统计、增量显示
- **详情弹窗**：双击/右键进程行，完整查看 PID、UID、可执行路径与全部占用路径（可复制）
- **CLI 附带**：`volumeguard [--eject <挂载点>]`，脚本化使用

## 构建

需要 macOS 13+ 与 Xcode Command Line Tools（无需完整 Xcode）：

```bash
./scripts/make_app.sh
open build/VolumeGuard.app
```

脚本自动完成：release 构建 → 组装 `.app` bundle → 生成应用图标 → ad-hoc 签名。

CLI 构建：

```bash
swift build
.build/debug/volumeguard /Volumes/YourDisk     # 扫描
.build/debug/volumeguard --eject /Volumes/YourDisk  # 弹出
```

## 常见问题

**弹出的原理？** 调用系统 `diskutil eject`（Finder 同款底层）。占用中被拒时错误信息自带占用进程 PID。

**root 进程占用怎么办？** 无 root 权限时无法终止它们（如 Spotlight 的 `mds_stores`），工具会明确列出这些进程。多数情况杀掉用户态的 `mdworker_shared` 等即可解除弹出阻塞。

**首次打开提示无法验证？** 右键 App → 打开，或执行：

```bash
xattr -cr /Applications/VolumeGuard.app
```

## 实现要点（踩坑记录）

- **fd 级 flavor 必须用 `proc_pidfdinfo`**：用 `proc_pidinfo` 传 fd 当 arg，内核会把 `PROC_PIDFDVNODEPATHINFO=2` 当成 pid 级的 `PROC_PIDTASKALLINFO` 返回 232 字节垃圾
- **`DASessionSetDispatchQueue` 不能漏**：`DASessionCreate` 后不挂 queue，diskarbitrationd 的应答送不回来，`DADiskEject` 回调永不触发、信号量死等——表现为"点击弹出毫无反应"
- **Swift 6 编译器崩溃**：C 回调闭包捕获外部变量再转 C 函数指针，会触发 `SendNonSendable` pass 的 signal 6，上下文须经 `Unmanaged` 指针传递
- **CLT 26.x SDK 可构建 SwiftUI app**，无需完整 Xcode

## License

[MIT](LICENSE)
