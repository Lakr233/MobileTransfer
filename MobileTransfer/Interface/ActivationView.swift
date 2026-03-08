//
//  ActivationView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/17.
//

import SwiftUI

struct ActivationView: View {
    let title: LocalizedStringKey = "Activate"
    let spacing: CGFloat = 16

    @Environment(ViewModel.self) var vm
    @Environment(\.dismiss) var dismiss

    @State var email: String = ""
    @State var key: String = ""
    @State var error: String = ""

    @State var processing: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Text(title).bold()
                Spacer()
            }
            .padding(spacing)
            Divider()
            if processing {
                HStack {
                    Text("Communicating with authorization server...")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView()
                        .scaleEffect(0.5)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .padding(spacing)
            } else {
                Grid(alignment: .leading, horizontalSpacing: spacing, verticalSpacing: 8) {
                    GridRow {
                        Text("This is a trial version of MobileTransfer. Please activate the app to use all features.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Email")
                        TextField("xxxx@xxx.xxx", text: $email)
                            .onChange(of: key) { _, newValue in
                                let format = newValue
                                    .replacingOccurrences(of: "\n", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if format != newValue { key = format }
                            }
                    }
                    GridRow {
                        Text("Key")
                        TextField("MT-XXXX-XXXX-XXXX", text: $key)
                            .onChange(of: key) { _, newValue in
                                let format = newValue.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                                if format != newValue { key = format }
                            }
                    }
                    if let trailInfo = vm.licenseInfo {
                        GridRow {
                            Text("Trail End")
                            Text(trailInfo.validateTo, style: .date)
                        }
                        .foregroundStyle(.red)
                    }
                }
                .padding(spacing)
            }
            Divider()
            HStack {
                Text(error).foregroundColor(.red)
                Spacer()
                Button("Exit") {
                    exit(0)
                }
                Button("Activate") {
                    tryActivate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || key.isEmpty)
                .disabled(!key.hasPrefix("MT-"))
                .disabled(!email.contains("@"))
                .disabled(!email.contains("."))
            }
            .padding(spacing)
        }
        .disabled(processing)
        .frame(maxWidth: .infinity)
    }

    func tryActivate() {
        processing = true
        error = ""
        let activationInfo = (email, key)
        print("[*] activation info: \(activationInfo)")
        DispatchQueue.global().async {
            sleep(1)
            DispatchQueue.main.async {
                processing = false
                vm.licenseInfo = .init(
                    licensee: email,
                    licenseKey: key,
                    validateTo: Date(timeIntervalSinceNow: 3650 * 24 * 60 * 60)
                )
            }
        }
    }
}
