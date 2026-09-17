import AppKit
import Core
import SwiftUI

/// 进程详情弹窗：完整展示进程属性与全部占用路径
struct DetailSheetView: View {
    let process: OccupyingProcess
    /// force=true 走 SIGKILL，false 走 SIGTERM；操作后自动关闭
    let onKill: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：图标 + 名称 + 说明
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: process.executablePath ?? ""))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(process.name).font(.title3.bold())
                        if process.isSelf {
                            Text("(本工具)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let desc = ProcessKnowledge.describe(name: process.name) {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // 属性
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("PID").foregroundStyle(.secondary)
                    Text("\(process.pid)").monospacedDigit().textSelection(.enabled)
                }
                GridRow {
                    Text("UID").foregroundStyle(.secondary)
                    Text("\(process.uid)").monospacedDigit().textSelection(.enabled)
                }
                GridRow {
                    Text("可执行文件").foregroundStyle(.secondary)
                    Text(process.executablePath ?? "（当前权限不可见）")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Divider()

            // 占用路径完整列表
            Text("占用路径（\(process.occupied.count)）").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(process.occupied, id: \.self) { f in
                    HStack(alignment: .top, spacing: 8) {
                        Text(f.source.rawValue.uppercased())
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(sourceColor(f).opacity(0.16), in: Capsule())
                            .foregroundStyle(sourceColor(f))
                        Text(f.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Divider()

            // 操作
            HStack {
                Button("强制结束", role: .destructive) { onKill(true) }
                    .disabled(process.isSelf)
                Button("结束进程") { onKill(false) }
                    .disabled(process.isSelf)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 580, alignment: .leading)
    }

    private func sourceColor(_ f: OccupiedFile) -> Color {
        switch f.source {
        case .fd: .blue
        case .cwd: .orange
        case .rdir: .purple
        }
    }
}
