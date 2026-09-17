import AppKit
import Core
import SwiftUI

/// 菜单栏托盘面板（window 风格）：每卷占用状态 + 就地解除/弹出
struct MenuPanelView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            if vm.mountPoints.isEmpty {
                Text("没有外接卷")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(vm.mountPoints, id: \.self) { mp in
                    volumeRow(mp)
                }
            }

            Divider()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出 VolumeGuard", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(10)
        .frame(width: 300)
        .onAppear { vm.refreshMenuCounts() }
    }

    @ViewBuilder private func volumeRow(_ mp: String) -> some View {
        let count = vm.menuCounts[mp]
        let busy = (count ?? 0) > 0

        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .foregroundStyle(busy ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortName(mp))
                    .font(.system(.body, weight: .medium))
                Text(count == nil ? "扫描中…" : (busy ? "\(count!) 个进程占用" : "空闲"))
                    .font(.caption)
                    .foregroundStyle(busy ? Color.orange : Color.secondary)
            }
            Spacer()
            if busy {
                if vm.isReleasing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("解除") { confirmRelease(mp) }
                        .controlSize(.small)
                }
            }
            Button("弹出") { confirmEject(mp) }
                .controlSize(.small)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(busy ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.05))
        )
    }

    private func shortName(_ mp: String) -> String {
        mp.hasPrefix("/Volumes/") ? String(mp.dropFirst("/Volumes/".count)) : mp
    }

    /// 解除前确认，防止托盘误触直接开杀
    private func confirmRelease(_ mp: String) {
        let alert = NSAlert()
        alert.messageText = "解除「\(shortName(mp))」的全部占用？"
        alert.informativeText = "将先发送 SIGTERM，对未退出的进程自动补 SIGKILL。root 进程无法解除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "解除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            vm.releaseVolume(mp)
        }
    }

    /// 托盘弹出：有占用时引导先解除，否则直接弹
    private func confirmEject(_ mp: String) {
        let busy = (vm.menuCounts[mp] ?? 0) > 0
        guard busy else {
            vm.eject(mp)
            return
        }
        let alert = NSAlert()
        alert.messageText = "「\(shortName(mp))」仍有进程占用"
        alert.informativeText = "直接弹出会被系统拒绝。建议先解除占用，完成后再弹出。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "解除并弹出")
        alert.addButton(withTitle: "仍要直接弹出")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            vm.releaseVolume(mp, ejectAfter: true)
        case .alertSecondButtonReturn:
            vm.eject(mp)
        default:
            break
        }
    }
}
