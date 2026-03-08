//
//  ApplicationDownloadTaskView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import Kingfisher
import SwiftUI

private let expectedImageSize: CGFloat = 32
private let scalingFactor = (NSScreen.main?.backingScaleFactor ?? 2)
private let imageResizer = Kingfisher.ResizingImageProcessor(
    referenceSize: .init(
        width: expectedImageSize * scalingFactor,
        height: expectedImageSize * scalingFactor
    ),
    mode: .aspectFill
)

struct ApplicationDownloadTaskView: View {
    var task: MobileAppConnectTask

    var overall: String {
        "\(Int(task.progress * 100))%"
    }

    var captionText: LocalizedStringKey {
        if task.runningTasks.isEmpty {
            if let last = task.logs.last {
                .init(last)
            } else if task.completed {
                "Completed"
            } else {
                "Waiting..."
            }
        } else {
            "Success \(task.successTasks.count) Failure \(task.failedTasks.count) Total \(task.appList.count)"
        }
    }

    var body: some View {
        CardContentView {
            CardContentHeader(
                icon: "icloud.and.arrow.down",
                title: "Download"
            ) {
                if task.completed {
                    if task.success {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        Image(systemName: task.successTasks.isEmpty ? "xmark.circle.fill" : "checkmark.circle.badge.xmark.fill")
                            .foregroundStyle(task.successTasks.isEmpty ? .red : .yellow)
                            .transition(.opacity.combined(with: .scale))
                    }
                } else {
                    Text(overall)
                        .multilineTextAlignment(.trailing)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .scale))
                }
            }

            Text(captionText)
                .contentTransition(.numericText())

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], alignment: .leading, spacing: 8) {
                        ForEach(task.successTasks) { app in
                            KFImage(URL(string: app.appAvatar))
                                .setProcessor(imageResizer)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: expectedImageSize, height: expectedImageSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay {
                                    Circle().foregroundStyle(.white)
                                        .frame(width: 8, height: 8)
                                        .overlay { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }

                    ForEach(task.runningTasks) { app in
                        ApplicationDownloadTaskSingleElementView(app: app)
                            .transition(.opacity)
                    }

                    ForEach(task.failedTasks) { app in
                        ApplicationDownloadTaskSingleElementView(app: app)
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(.spring, value: task.runningTasks)
        .animation(.spring, value: task.successTasks)
        .animation(.spring, value: task.failedTasks)
    }
}

private struct ApplicationDownloadTaskSingleElementView: View {
    var app: MobileAppConnectTask.DownloadTask

    var desc: LocalizedStringKey {
        if let error = app.error {
            .init(error)
        } else if app.progress == 1 {
            "Verifying download..."
        } else {
            "\(app.appVersion) - \(app.speedText)"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let avatarUrl = URL(string: app.appAvatar) {
                KFImage(avatarUrl)
                    .resizable()
                    .setProcessor(imageResizer)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Rectangle()
                    .foregroundStyle(.gray.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.appName)
                    .bold()
                    .contentTransition(.numericText())
                Text(desc)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if app.error != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .scale))
            } else {
                Text(app.progressText)
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring, value: app.progress)
        .animation(.spring, value: app.speed)
        .animation(.spring, value: app.error)
    }
}
