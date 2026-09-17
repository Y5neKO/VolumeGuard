# VolumeGuard

弹出移动硬盘的时候总提示"无法退出，因为被占用"？VolumeGuard 告诉你是谁占的，杀掉，然后弹出。

![screenshot](docs/screenshots/main.png)

## 能干什么

- 列出占用某个卷的所有进程，以及各自占在哪（打开的文件、工作目录）
- 一键杀掉全部占用进程，然后弹出
- 菜单栏常驻，随时看盘的状态，随时解
- 双击进程可以看它在这个盘上到底抓着哪些文件
- 顺便能看看盘上各目录占了多少空间

Spotlight 索引、缩略图、Time Machine 这类常见占用会直接标出来是什么。

## 下载

去 [Releases](https://github.com/Y5neKO/VolumeGuard/releases) 下载 zip，解压拖进应用程序文件夹。

首次打开会被拦，右键 App 选"打开"，或者：

```bash
xattr -cr /Applications/VolumeGuard.app
```

系统进程（root 跑的）杀不掉，工具会明确列出来。

## 自己编译

装好 Xcode Command Line Tools 后：

```bash
./scripts/make_app.sh
```

产物在 `build/VolumeGuard.app`。也有个命令行版：

```bash
.build/debug/volumeguard /Volumes/YourDisk
.build/debug/volumeguard --eject /Volumes/YourDisk
```

## License

[MIT](LICENSE)
