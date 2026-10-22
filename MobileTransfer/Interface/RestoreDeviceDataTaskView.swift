//
//  RestoreDeviceDataTaskView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct RestoreDeviceDataTaskView: View {
    let task: MobileRestoreTask
    @State private var showingDetails = false

    var body: some View {
        TransferProgressCard(title: "Restore", progress: task.overall.completedUnitCount > 0 ? task.overall.fractionCompleted : nil,
                             onDetails: { showingDetails = true }) {
            Text(task.overall.fractionCompleted >= 1 ? "正在完成恢复…" : task.overall.completedUnitCount > 0 ? "正在恢复设备数据…" : "准备开始恢复…")
        } supplement: {
            if task.current.completedUnitCount > 0 {
                Text("已传输 \(ByteCountFormatter.string(fromByteCount: task.current.completedUnitCount, countStyle: .file))")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $showingDetails) {
            VStack(alignment: .leading, spacing: 12) {
                Text("恢复日志").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(task.output.reversed()) { entry in
                            Text(entry.text).font(.footnote.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(20).frame(width: 620, height: 420)
        }
    }
}
