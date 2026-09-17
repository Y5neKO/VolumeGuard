import SwiftUI

@main
struct VolumeGuardApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        WindowGroup("VolumeGuard", id: "main") {
            ContentView()
                .environmentObject(vm)
        }
        .windowResizability(.contentMinSize)
        .commands {
            VolumeGuardCommands(vm: vm)
        }

        // 菜单栏常驻：窗口风格面板，每卷可就地解除/弹出
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(vm)
        } label: {
            Image(systemName: vm.traySymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 顶部菜单栏精简：去掉无用默认项，补上高频操作
struct VolumeGuardCommands: Commands {
    let vm: AppViewModel

    var body: some Commands {
        // 去掉 File > New Window
        CommandGroup(replacing: .newItem) {}
        // 去掉 View 里的 Show Toolbar
        CommandGroup(replacing: .toolbar) {}
        // 去掉无用 Help
        CommandGroup(replacing: .help) {}

        // 高频操作菜单
        CommandMenu("操作") {
            Button("刷新占用") {
                vm.refreshVolumes(manual: true)
            }
            .keyboardShortcut("r")

            Button("一键解除当前卷占用…") {
                vm.showKillAllConfirm = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(vm.processes.isEmpty)

            Button("空间分析…") {
                vm.showSpaceAnalysis = true
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(vm.selectedVolume == nil)

            Divider()

            Button("弹出当前卷") {
                vm.ejectSelected()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(vm.selectedVolume == nil)
        }
    }
}
