import AppKit
import Combine
import Core
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var mountPoints: [String] = []
    @Published var selectedVolume: String?
    @Published var processes: [OccupyingProcess] = []
    @Published var selectedPIDs: Set<pid_t> = []
    /// 防重入标志（轮询与手动共用，不驱动 UI）
    var isScanning = false
    /// 仅手动刷新时为 true，驱动 header 加载圈；轮询保持无感知
    @Published var isManualRefreshing = false
    @Published var alertText: String?
    @Published var showAlert = false
    @Published var showKillAllConfirm = false
    /// 卷上有占用时点「弹出」的引导确认
    @Published var showEjectConfirm = false
    /// 一键解除执行中（防重复点击）
    @Published var isReleasing = false
    /// 选中卷的容量概况
    /// 详情弹窗当前展示的进程（item-based sheet）
    @Published var detailProcess: OccupyingProcess?
    @Published var volumeUsage: (total: Int64, free: Int64)?
    @Published var showSpaceAnalysis = false
    /// 菜单栏面板：各卷占用进程数
    @Published var menuCounts: [String: Int] = [:]

    private var observers: [NSObjectProtocol] = []
    /// 实时刷新定时器（fd 占用无系统通知，只能轮询；扫描 ~30ms，1s 间隔开销可忽略）
    private var pollTimer: Timer?
    /// 菜单栏计数轮询（驱动托盘图标状态，5s 一轮足够）
    private var menuPollTimer: Timer?

    init() {
        // 挂载/卸载事件自动刷新卷列表
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification]
        for name in names {
            let obs = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.refreshVolumes() }
            }
            observers.append(obs)
        }
        // 实时轮询当前卷的占用情况
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollTick() }
        }
        // 菜单栏计数轮询
        menuPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMenuCounts() }
        }
    }

    /// 托盘图标状态：任意卷有占用时切换警示符号
    var traySymbol: String {
        let busy = menuCounts.values.contains { $0 > 0 }
        return busy ? "externaldrive.fill.badge.exclamationmark" : "externaldrive.connected.to.line.below"
    }

    deinit {
        // ViewModel 与 app 同生命周期，observer/timer 无需显式移除；
        // 在此访问 MainActor 隔离属性会触发 swift-frontend (SendNonSendable) 崩溃
    }

    // MARK: 刷新

    /// 轮询 tick：扫描中或一键解除执行中时跳过，避免重叠
    func pollTick() {
        guard !isScanning, !isReleasing else { return }
        refreshVolumes()
    }

    /// 刷新卷列表并保持选中项。manual=true 时显示加载圈（手动刷新），轮询静默
    func refreshVolumes(manual: Bool = false) {
        let newMPs = VolumeScanner.localVolumeMountPoints()
        if newMPs != mountPoints {
            mountPoints = newMPs
        }
        if let sel = selectedVolume, mountPoints.contains(sel) {
            refreshProcesses(showSpinner: manual)
        } else {
            selectedVolume = mountPoints.first
            if selectedVolume == nil { processes = [] }
        }
    }

    /// 扫描选中卷的占用进程。showSpinner 仅手动刷新时传 true
    func refreshProcesses(showSpinner: Bool = false) {
        guard let mp = selectedVolume else {
            processes = []
            return
        }
        guard !isScanning else { return }
        isScanning = true
        if showSpinner { isManualRefreshing = true }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                VolumeScanner.scan(mountPoint: mp)
            }.value
            let usage = await Task.detached(priority: .utility) {
                SpaceScanner.volumeUsage(mountPoint: mp)
            }.value
            // 扫描间隙卷可能已卸载；结果无变化时不动 @Published，避免整表重渲染
            if mountPoints.contains(mp) {
                if result != processes {
                    processes = result
                }
                if volumeUsage?.total != usage?.total || volumeUsage?.free != usage?.free {
                    volumeUsage = usage
                }
            }
            isScanning = false
            isManualRefreshing = false
        }
    }

    /// 菜单栏面板：并行扫描所有卷，更新各卷占用数
    func refreshMenuCounts() {
        let mps = mountPoints
        guard !mps.isEmpty else { return }
        Task {
            let counts = await Task.detached(priority: .utility) {
                await withTaskGroup(of: (String, Int).self) { group in
                    for mp in mps {
                        group.addTask { (mp, VolumeScanner.scan(mountPoint: mp).count) }
                    }
                    var out: [(String, Int)] = []
                    for await r in group { out.append(r) }
                    return out
                }
            }.value
            var map: [String: Int] = [:]
            counts.forEach { map[$0.0] = $0.1 }
            menuCounts = map
        }
    }

    // MARK: 进程操作

    /// 结束选中进程。force=false 走 SIGTERM，否则 SIGKILL
    func killSelected(force: Bool) {
        var errors: [String] = []
        for pid in selectedPIDs.sorted() {
            if let err = force ? ProcessKiller.forceKill(pid) : ProcessKiller.terminate(pid) {
                errors.append(LF("PID %d: %@", pid, err))
            }
        }
        if !errors.isEmpty {
            alert(errors.joined(separator: "\n"))
        }
        // 留时间给进程退出，再刷新占用表
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            refreshProcesses()
        }
    }

    /// 一键解除全部占用：先 TERM，800ms 后对仍在占用的补 KILL；ejectAfter=true 完成后弹出
    func killAll(ejectAfter: Bool = false) {
        guard let mp = selectedVolume, !isReleasing else { return }
        let targets = processes.filter { !$0.isSelf }
        guard !targets.isEmpty else { return }
        performRelease(targets: targets, mountPoint: mp, ejectAfter: ejectAfter)
    }

    /// 托盘入口：解除指定卷的全部占用（自行扫描目标进程）
    func releaseVolume(_ mp: String, ejectAfter: Bool = false) {
        guard !isReleasing else { return }
        isReleasing = true
        Task {
            let targets = await Task.detached(priority: .userInitiated) {
                VolumeScanner.scan(mountPoint: mp).filter { !$0.isSelf }
            }.value
            performRelease(targets: targets, mountPoint: mp, ejectAfter: ejectAfter)
        }
    }

    /// 两阶段解除：TERM → 800ms → 对仍占用者补 KILL → 刷新（可选拼弹出）
    /// 调用方负责 isReleasing 冲突检查，这里幂等置位
    private func performRelease(targets: [OccupyingProcess], mountPoint: String, ejectAfter: Bool) {
        guard !targets.isEmpty else { return }
        isReleasing = true
        Task {
            // 第一轮：优雅终止
            var denied: [String] = []
            for p in targets {
                if let err = ProcessKiller.terminate(p.pid) {
                    // EPERM 等：KILL 也会失败，记录后不重试
                    denied.append(LF("%@ (PID %d): %@", p.name, p.pid, err))
                }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)

            // 第二轮：仍占用卷的补强制终止
            let remaining = await Task.detached(priority: .userInitiated) {
                VolumeScanner.scan(mountPoint: mountPoint)
            }.value
            let stillThere = Set(remaining.map(\.pid))
            for p in targets where stillThere.contains(p.pid) {
                _ = ProcessKiller.forceKill(p.pid)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            isReleasing = false
            refreshProcesses()
            refreshMenuCounts()

            if !denied.isEmpty {
                alert(L("No permission to release the following (root processes — sudo required):\n")
                      + denied.joined(separator: "\n"))
            } else if ejectAfter {
                // 留一轮扫描确认清空后再弹
                try? await Task.sleep(nanoseconds: 500_000_000)
                eject(mountPoint)
            }
        }
    }

    // MARK: 磁盘操作

    /// 弹出选中卷：有占用时先引导「解除并弹出」，避免必然失败的系统拒绝
    func ejectSelected() {
        guard let mp = selectedVolume else { return }
        if processes.isEmpty {
            eject(mp)
        } else {
            showEjectConfirm = true
        }
    }

    /// 弹出指定挂载点。失败时解析 dissent 进程，给出可操作的诊断
    func eject(_ mp: String) {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                EjectService.eject(mountPoint: mp)
            }.value
            guard let err = result else { return }

            // 回查 dissent 进程，分类给出建议
            let summary = await Task.detached(priority: .userInitiated) { () -> (pid: pid_t, info: (name: String, execPath: String?, uid: uid_t))? in
                guard let pid = EjectService.parseDissentPID(from: err),
                      let info = VolumeScanner.processSummary(pid: pid)
                else { return nil }
                return (pid, info)
            }.value

            var message = err
            if let s = summary {
                let isRoot = s.info.uid != getuid()
                let rootNote = isRoot ? L(" (running as root — cannot be released automatically)") : ""
                message = LF("Eject blocked by PID %d — %@%@", s.pid, s.info.name, rootNote)
                    + "\n\n" + err
                if let hint = ProcessKnowledge.describe(name: s.info.name) {
                    message += "\n\n" + LF("Hint: %@", hint)
                } else if !isRoot {
                    message += "\n\n" + L("Hint: release it from the list, then eject again.")
                }
            }
            alert(message)
        }
    }

    private func alert(_ text: String) {
        alertText = text
        showAlert = true
    }
}
