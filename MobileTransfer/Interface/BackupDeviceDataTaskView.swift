//
//  BackupDeviceDataTaskView.swift
//  BBackupp
//
//  Created by 秋星桥 on 2024/3/15.
//

import SwiftUI

struct BackupDeviceDataTaskView: View {
    let task: MobileBackupTask

    @State private var showingDetails = false

    private var hasOverallProgress: Bool {
        task.hasReportedOverallProgress
    }

    private var overallPercent: String {
        "\(Int(task.overall.fractionCompleted * 100))%"
    }

    private var hasCurrentProgress: Bool {
        task.hasStartedTransfer && task.current.totalUnitCount > 0
    }

    private var currentPercent: String {
        "\(Int(task.current.fractionCompleted * 100))%"
    }

    private var currentTransfer: String? {
        guard hasCurrentProgress else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let received = formatter.string(fromByteCount: task.current.completedUnitCount)
        let total = formatter.string(fromByteCount: task.current.totalUnitCount)
        return "\(received) / \(total)"
    }

    @ViewBuilder var body: some View {
        if task.completed && !task.success {
            failureContent
        } else {
            progressContent
        }
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("备份未完成").font(.title3.weight(.semibold))
                    Text("请处理以下问题后重新备份。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if task.reportedErrors.count > 3 {
                ScrollView { errorRows }.frame(height: 220)
            } else {
                errorRows
            }
            Text("未完成的备份不能用于恢复。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("查看日志") { showingDetails = true }
                    .popover(isPresented: $showingDetails) { details }
                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5) }
    }

    private var errorRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            if task.reportedErrors.isEmpty {
                Text("备份工具未提供具体原因。请查看详细日志。")
            } else {
                ForEach(task.reportedErrors, id: \.self) { message in
                    Text(verbatim: message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if message != task.reportedErrors.last { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressContent: some View {
        TransferProgressCard(title: "Backup", progress: hasOverallProgress ? task.overall.fractionCompleted : nil,
                             onDetails: { showingDetails = true }) {
            status
        } supplement: {
            if let currentTransfer, !task.completed {
                Text(currentTransfer).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !task.completed, !task.reportedErrors.isEmpty {
                ForEach(task.reportedErrors, id: \.self) { message in
                    Text(verbatim: message).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .popover(isPresented: $showingDetails) { details }
    }

    @ViewBuilder
    private var status: some View {
        if task.completed {
            if task.success {
                Text("Backup complete")
            } else {
                Text("Backup failed")
                    .foregroundStyle(.red)
            }
        } else if task.hasReportedOverallProgress && task.overall.fractionCompleted >= 1 {
            Text("正在完成备份…")
        } else if task.hasStartedTransfer {
            if let sourceName = task.currentSourceName {
                Text("Backing up \(sourceName)…")
            } else {
                Text("Transferring device data…")
            }
        } else {
            switch task.preparationStage {
            case .connecting: Text("准备开始备份…")
            case .waitingForPasscode: Text("请在 iPhone 上输入锁屏密码")
            case .preparing: Text("准备开始备份…")
            case .responding: Text("准备开始备份…")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup details")
                .font(.headline)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(task.output.reversed()) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                                .foregroundStyle(entry.color)
                                .textSelection(.enabled)
                        }
                        .font(.footnote.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 620, height: 420)
    }
}

private extension MobileBackupTask.Log {
    var color: Color {
        if text.lowercased().contains("error") {
            return .red
        }
        if text.lowercased().contains("warning") {
            return .orange
        }
        return .primary
    }
}

/// Both operations share the native progress presentation. Unknown progress is a spinner.
struct TransferProgressCard<Status: View, Supplement: View>: View {
    let title: LocalizedStringKey
    let progress: Double?
    let onDetails: () -> Void
    @ViewBuilder let status: Status
    @ViewBuilder let supplement: Supplement

    var body: some View {
        CardContentView {
            HStack {
                Image(systemName: "arrow.right.doc.on.clipboard").accessibilityHidden(true)
                Text(title).bold()
                Spacer()
                if let progress {
                    Text("传输进度 \(Int(min(1, max(0, progress)) * 100))%")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button(action: onDetails) { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).help("查看日志").accessibilityLabel("查看日志")
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    if progress == nil { ProgressView().progressViewStyle(.circular).controlSize(.small) }
                    status.font(.headline)
                }
                if let progress {
                    ProgressView(value: min(1, max(0, progress))).progressViewStyle(.linear)
                }
                supplement
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: 560)
    }
}

struct TransferResultView: View {
    let title: String
    var message: String? = nil
    var success = true
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 64)).foregroundStyle(success ? .green : .orange)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            if let message { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Button("完成", action: onDone).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: 560)
    }
}
