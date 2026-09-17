import AppKit
import Core
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(vm.mountPoints, id: \.self, selection: $vm.selectedVolume) { mp in
                Label(shortName(mp), systemImage: "externaldrive")
                    .badge(badgeText(mp))
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 780, minHeight: 480)
        .alert("操作失败", isPresented: $vm.showAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(vm.alertText ?? "")
        }
        .onAppear { vm.refreshVolumes() }
        .onChange(of: vm.selectedVolume) { _ in vm.refreshProcesses() }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider()
            processTable
                .frame(maxHeight: .infinity)
            Divider()
            actionBar
        }
        .confirmationDialog("解除全部占用？", isPresented: $vm.showKillAllConfirm, titleVisibility: .visible) {
            Button("解除全部（\(vm.processes.count) 个进程）", role: .destructive) {
                vm.killAll()
            }
            Button("解除并弹出", role: .destructive) {
                vm.killAll(ejectAfter: true)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将先发送 SIGTERM，对未退出的进程自动补 SIGKILL。root 进程无法解除。")
        }
        .sheet(isPresented: $vm.showSpaceAnalysis) {
            if let mp = vm.selectedVolume {
                SpaceAnalysisSheet(mountPoint: mp)
            }
        }
        .confirmationDialog("当前卷有 \(vm.processes.count) 个进程占用", isPresented: $vm.showEjectConfirm, titleVisibility: .visible) {
            Button("解除并弹出", role: .destructive) {
                vm.killAll(ejectAfter: true)
            }
            Button("仍要直接弹出", role: .destructive) {
                if let mp = vm.selectedVolume {
                    vm.eject(mp)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("直接弹出会被系统拒绝。建议先解除占用，完成后再弹出。")
        }
        .sheet(item: $vm.detailProcess) { p in
            DetailSheetView(process: p) { force in
                vm.selectedPIDs = [p.pid]
                vm.killSelected(force: force)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(vm.selectedVolume ?? "未选择卷")
                .font(.headline)
                .textSelection(.enabled)
            if let u = vm.volumeUsage, vm.selectedVolume != nil {
                Text("已用 \(fmt(Double(u.total - u.free))) / 共 \(fmt(Double(u.total)))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isManualRefreshing {
                ProgressView().controlSize(.small)
            }
            Text(vm.selectedVolume == nil ? "—" : "\(vm.processes.count) 个进程占用")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding()
    }

    private var processTable: some View {
        Table(vm.processes, selection: $vm.selectedPIDs) {
            TableColumn("PID") { p in
                Text("\(p.pid)").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)

            TableColumn("进程") { p in
                HStack(spacing: 6) {
                    Image(nsImage: processIcon(p))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(p.name)
                    if let desc = ProcessKnowledge.describe(name: p.name) {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if p.isSelf {
                        Text("(本工具)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .help("双击查看完整详情")
            }

            TableColumn("占用详情") { p in
                Text(p.occupied.map { "[\($0.source.rawValue)] \($0.path)" }.joined(separator: "   "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(p.occupied.map { "[\($0.source.rawValue)] \($0.path)" }.joined(separator: "\n"))
            }
        }
        .overlay {
            if vm.selectedVolume != nil && !vm.isManualRefreshing && vm.processes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("无占用").font(.title3)
                    Text("当前没有进程占用这个卷，可以直接弹出")
                        .foregroundStyle(.secondary)
                }
            }
        }
        // 行级右键菜单 + 双击行打开详情（primaryAction）
        .contextMenu(forSelectionType: pid_t.self) { selection in
            rowMenuItems(selection)
        } primaryAction: { selection in
            guard let pid = selection.first,
                  let p = vm.processes.first(where: { $0.pid == pid })
            else { return }
            vm.detailProcess = p
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                vm.refreshVolumes(manual: true)
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            Button {
                vm.showSpaceAnalysis = true
            } label: {
                Label("空间分析", systemImage: "chart.bar.fill")
            }
            .disabled(vm.selectedVolume == nil)

            Button {
                vm.showKillAllConfirm = true
            } label: {
                if vm.isReleasing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("一键解除", systemImage: "sparkles.rectangle.stack")
                }
            }
            .disabled(vm.processes.isEmpty || vm.isReleasing)

            Button("结束进程") { vm.killSelected(force: false) }
                .disabled(vm.selectedPIDs.isEmpty)
            Button("强制结束") { vm.killSelected(force: true) }
                .disabled(vm.selectedPIDs.isEmpty)

            Divider()
                .frame(height: 18)

            Button {
                vm.ejectSelected()
            } label: {
                Label("弹出", systemImage: "eject")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedVolume == nil)
        }
        .padding()
    }

    /// 行级右键菜单（selection 为右键目标行的选择集合）
    @ViewBuilder private func rowMenuItems(_ selection: Set<pid_t>) -> some View {
        Button {
            guard selection.count == 1,
                  let p = vm.processes.first(where: { $0.pid == selection.first! })
            else { return }
            vm.detailProcess = p
        } label: {
            Label("查看详情", systemImage: "info.circle")
        }
        .disabled(selection.count != 1)

        Button("结束选中进程") {
            vm.selectedPIDs = selection
            vm.killSelected(force: false)
        }
        .disabled(selection.isEmpty)

        Button("强制结束选中进程", role: .destructive) {
            vm.selectedPIDs = selection
            vm.killSelected(force: true)
        }
        .disabled(selection.isEmpty)
    }

    // MARK: 工具

    private func processIcon(_ p: OccupyingProcess) -> NSImage {
        NSWorkspace.shared.icon(forFile: p.executablePath ?? "")
    }

    private func shortName(_ mp: String) -> String {
        mp.hasPrefix("/Volumes/") ? String(mp.dropFirst("/Volumes/".count)) : mp
    }

    private func fmt(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// 卷列表徽标：后台预扫占用数太重，这里只标「未扫描」，选中后显示真实数量
    private func badgeText(_ mp: String) -> String? {
        mp == vm.selectedVolume ? "\(vm.processes.count)" : nil
    }
}
