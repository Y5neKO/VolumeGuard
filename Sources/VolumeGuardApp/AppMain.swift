import Core
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
            VolumeGuardCommands()
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

/// 顶部菜单栏精简：去掉无用默认项，补上高频操作。
/// disabled 状态经 @FocusedObject 跟随聚焦窗口的实时数据，
/// 否则 Commands 只拿到结构体创建时刻的快照，菜单会永远保持初始灰态。
struct VolumeGuardCommands: Commands {
    @FocusedObject private var vm: AppViewModel?

    var body: some Commands {
        // 去掉 File > New Window
        CommandGroup(replacing: .newItem) {}
        // 去掉 View 里的 Show Toolbar
        CommandGroup(replacing: .toolbar) {}
        // 去掉无用 Help
        CommandGroup(replacing: .help) {}

        // 高频操作菜单
        CommandMenu(L("Actions")) {
            Button(L("Refresh")) {
                vm?.refreshVolumes(manual: true)
            }
            .keyboardShortcut("r")

            Button(L("Release All…")) {
                vm?.showKillAllConfirm = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(vm == nil || vm!.processes.isEmpty)

            Button(L("Space Analysis…")) {
                vm?.showSpaceAnalysis = true
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(vm == nil || vm!.selectedVolume == nil)

            Divider()

            Button(L("Eject")) {
                vm?.ejectSelected()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(vm == nil || vm!.selectedVolume == nil)
        }
    }
}
