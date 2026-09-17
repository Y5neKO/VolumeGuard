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
        .frame(minWidth: 860, minHeight: 480)
        .alert(L("Action failed"), isPresented: $vm.showAlert) {
            Button(L("OK"), role: .cancel) {}
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
        .confirmationDialog(L("Release all occupancy?"), isPresented: $vm.showKillAllConfirm, titleVisibility: .visible) {
            Button(LF("Release all (%d processes)", vm.processes.count), role: .destructive) {
                vm.killAll()
            }
            Button(L("Release and Eject"), role: .destructive) {
                vm.killAll(ejectAfter: true)
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("SIGTERM first; SIGKILL is sent automatically to anything still holding on. Root processes cannot be released."))
        }
        .sheet(isPresented: $vm.showSpaceAnalysis) {
            if let mp = vm.selectedVolume {
                SpaceAnalysisSheet(mountPoint: mp)
            }
        }
        .confirmationDialog(LF("%d processes are holding this volume", vm.processes.count), isPresented: $vm.showEjectConfirm, titleVisibility: .visible) {
            Button(L("Release and Eject"), role: .destructive) {
                vm.killAll(ejectAfter: true)
            }
            Button(L("Eject Anyway"), role: .destructive) {
                if let mp = vm.selectedVolume {
                    vm.eject(mp)
                }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Ejecting now will be rejected by the system. Release first, then eject."))
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
            Text(vm.selectedVolume ?? L("No volume selected"))
                .font(.headline)
                .textSelection(.enabled)
            if let u = vm.volumeUsage, vm.selectedVolume != nil {
                Text(LF("Used %@ of %@", fmt(Double(u.total - u.free)), fmt(Double(u.total))))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 空间分析放头部：底部栏按钮多，英文文案放不下
            Button {
                vm.showSpaceAnalysis = true
            } label: {
                Image(systemName: "chart.bar.fill")
            }
            .buttonStyle(.borderless)
            .disabled(vm.selectedVolume == nil)
            .help(L("Space Analysis"))
            if vm.isManualRefreshing {
                ProgressView().controlSize(.small)
            }
            Text(vm.selectedVolume == nil ? "—" : LF("%d processes holding it", vm.processes.count))
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

            TableColumn(L("Process")) { p in
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
                        Text(L("(this app)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .help(L("Double-click a row for full details"))
            }

            TableColumn(L("Occupation")) { p in
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
                    Text(L("No occupancy")).font(.title3)
                    Text(L("Nothing is holding this volume — you can eject it now"))
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
                Label(L("Refresh"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            Button {
                vm.showKillAllConfirm = true
            } label: {
                if vm.isReleasing {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("Release All"), systemImage: "sparkles.rectangle.stack")
                        .fixedSize()
                }
            }
            .disabled(vm.processes.isEmpty || vm.isReleasing)

            Button(L("Terminate")) { vm.killSelected(force: false) }
                .disabled(vm.selectedPIDs.isEmpty)
                .fixedSize()
            Button(L("Force Terminate")) { vm.killSelected(force: true) }
                .disabled(vm.selectedPIDs.isEmpty)
                .fixedSize()

            Divider()
                .frame(height: 18)

            Button {
                vm.ejectSelected()
            } label: {
                Label(L("Eject"), systemImage: "eject")
                    .fixedSize()
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
