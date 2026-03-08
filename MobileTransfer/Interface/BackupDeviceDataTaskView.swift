//
//  BackupDeviceDataTaskView.swift
//  BBackupp
//
//  Created by 秋星桥 on 2024/3/15.
//

import SwiftUI

struct BackupDeviceDataTaskView: View {
    let spacing: CGFloat = 16

    var task: MobileBackupTask

    var overall: String {
        "\(Int(task.overall.fractionCompleted * 100))%"
    }

    var body: some View {
        CardContentView {
            CardContentHeader(
                icon: "arrow.right.doc.on.clipboard",
                title: "Backup"
            ) {
                if task.completed {
                    if task.success {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .scale))
                    }
                } else {
                    Text(overall)
                        .multilineTextAlignment(.trailing)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.spring, value: task.completed)
            .animation(.spring, value: task.overall)
            VStack(alignment: .leading, spacing: 8) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var currentProgress: String {
        guard !task.completed else { return "" }
        guard task.current.fractionCompleted > 0,
              task.current.fractionCompleted < 1,
              task.current.completedUnitCount > 0,
              task.current.totalUnitCount > 0
        else { return "..." }
        let char = "="
        let charCountMax = 10
        let charCount = Int(task.current.fractionCompleted * Double(charCountMax))
        let charCountLeft = charCountMax - charCount
        let valueA = String(repeating: char, count: charCount)
        let valueB = String(repeating: " ", count: charCountLeft)
        let percent = Int(task.current.fractionCompleted * 100)
        let bytesFmt = ByteCountFormatter()
        bytesFmt.allowedUnits = [.useAll]
        bytesFmt.countStyle = .file
        let done = bytesFmt.string(fromByteCount: task.current.completedUnitCount)
        let total = bytesFmt.string(fromByteCount: task.current.totalUnitCount)
        return "Receiving \(total) - [\(valueA)>\(valueB)] \(percent)% (\(done))"
    }

    @ViewBuilder
    var content: some View {
        ProgressView(
            value: Double(task.overall.completedUnitCount),
            total: Double(task.overall.totalUnitCount)
        )
        .progressViewStyle(.linear)
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                if !currentProgress.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text(Date().formatted(date: .omitted, time: .shortened))
                        Text(":")
                        Text(currentProgress)
                    }
                    .font(.footnote)
                    .monospaced()
                }

                ForEach(task.output.reversed()) { input in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Date().formatted(date: .omitted, time: .shortened))
                        Text(":")
                        Text(input.text)
                            .foregroundStyle(input.color)
                            .textSelection(.enabled)
                    }
                    .font(.footnote)
                    .monospaced()
                }
            }
        }
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
