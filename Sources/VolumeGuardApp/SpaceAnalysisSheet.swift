import Core
import SwiftUI

/// 空间分析面板：卷容量概况 + 一级子目录大小排行（增量显示）
struct SpaceAnalysisSheet: View {
    let mountPoint: String

    @State private var entries: [DirectorySizeEntry] = []
    @State private var usage: (total: Int64, free: Int64)?
    @State private var isScanning = true
    @State private var scanTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(shortName(mountPoint) + L(" — Space Analysis"))
                    .font(.headline)
                Spacer()
                if let u = usage {
                    Text(LF("Used %@ of %@", fmt(Double(u.total - u.free)), fmt(Double(u.total))))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button(L("Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isScanning && entries.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L("Measuring first-level directories…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { e in
                    HStack(spacing: 10) {
                        Text(e.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(e.path)
                            .frame(width: 240, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.blue.opacity(0.10))
                                Capsule().fill(Color.blue.opacity(0.45))
                                    .frame(width: barWidth(e.size, geo.size.width))
                            }
                        }
                        Text(fmt(Double(e.size)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                if isScanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("Scanning — showing partial results…"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear { start() }
        .onDisappear { scanTask?.cancel() }
    }

    private func start() {
        usage = SpaceScanner.volumeUsage(mountPoint: mountPoint)
        scanTask = Task {
            await SpaceScanner.childDirectorySizes(at: mountPoint) { snapshot in
                Task { @MainActor in entries = snapshot }
            }
            Task { @MainActor in isScanning = false }
        }
    }

    private func barWidth(_ size: Int64, _ width: CGFloat) -> CGFloat {
        guard let maxSize = entries.first?.size, maxSize > 0 else { return 0 }
        return max(2, width * CGFloat(size) / CGFloat(maxSize))
    }

    private func fmt(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func shortName(_ mp: String) -> String {
        mp.hasPrefix("/Volumes/") ? String(mp.dropFirst("/Volumes/".count)) : mp
    }
}
