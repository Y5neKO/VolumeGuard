// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VolumeGuard",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // 核心逻辑：占用扫描、杀进程、弹出。不依赖 UI
        .target(name: "Core"),
        // CLI 入口：开发期验证核心逻辑
        .executableTarget(
            name: "volumeguard",
            dependencies: ["Core"]
        ),
        // GUI 主程序：SwiftUI
        .executableTarget(
            name: "VolumeGuardApp",
            dependencies: ["Core"]
        ),
    ]
)
