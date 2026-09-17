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
                Text(L("No external volumes"))
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
                Label(L("Open Main Window"), systemImage: "macwindow")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L("Quit VolumeGuard"), systemImage: "power")
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
                Text(count == nil ? L("Scanning…") : (busy ? LF("%d processes", count!) : L("Idle")))
                    .font(.caption)
                    .foregroundStyle(busy ? Color.orange : Color.secondary)
            }
            Spacer()
            if busy {
                if vm.isReleasing {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Release")) { confirmRelease(mp) }
                        .controlSize(.small)
                }
            }
            Button(L("Eject")) { confirmEject(mp) }
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
        alert.messageText = LF("Release all occupancy on \"%@\"?", shortName(mp))
        alert.informativeText = L("SIGTERM first; SIGKILL is sent automatically to anything still holding on. Root processes cannot be released.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Release"))
        alert.addButton(withTitle: L("Cancel"))
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
        alert.messageText = LF("\"%@\" is still busy", shortName(mp))
        alert.informativeText = L("Ejecting now will be rejected by the system. Release first, then eject.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Release and Eject"))
        alert.addButton(withTitle: L("Eject Anyway"))
        alert.addButton(withTitle: L("Cancel"))
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
