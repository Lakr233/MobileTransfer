//
//  InstallApplicationTaskView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/27.
//

import SwiftUI

struct InstallApplicationTaskView: View {
    var task: MobileInstallTask

    var overall: String {
        "\(Int(task.progress.fractionCompleted * 100))%"
    }

    var headline: LocalizedStringKey {
        if task.isWaitingForDeviceToConnect { return "Waiting for device to connect" }
        if let error = task.error { return .init(error) }
        if !task.failedList.isEmpty { return "Failed to install \(task.failedList.count) applications" }
        if !task.completed { return "Installing..." }
        return "Install completed"
    }

    var body: some View {
        CardContentView {
            CardContentHeader(
                icon: "arrow.down.app",
                title: "Install"
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
            .animation(.spring, value: task.progress)
            .animation(.spring, value: task.error)
            .animation(.spring, value: task.completed)
            .animation(.spring, value: task.isWaitingForDeviceToConnect)
            .animation(.spring, value: task.failedList)

            Text(headline)
                .contentTransition(.numericText())
                .animation(.spring, value: headline)
            ProgressView(
                value: Double(task.progress.completedUnitCount),
                total: Double(task.progress.totalUnitCount)
            )
            .progressViewStyle(.linear)
            .animation(.spring, value: task.progress)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(task.output.reversed()) { output in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Date().formatted(date: .omitted, time: .shortened))
                            Text(":")
                            Text(output.text)
                                .foregroundStyle(output.isError ? Color.red : .primary)
                                .textSelection(.enabled)
                        }
                        .font(.footnote)
                        .monospaced()
                    }
                }
            }
        }
    }
}
