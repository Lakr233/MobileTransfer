//
//  BackupTaskView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct BackupTaskView: View {
    var task: BackupTask

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            BackupDeviceDataTaskView(task: task.deviceDataTask)
            if let applicationDataTask = task.applicationDataTask {
                ApplicationDownloadTaskView(task: applicationDataTask)
            }
        }
    }
}
