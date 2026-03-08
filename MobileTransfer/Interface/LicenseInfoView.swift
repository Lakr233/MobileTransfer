//
//  LicenseInfoView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/10/17.
//

import ConfettiSwiftUI
import SwiftUI

struct LicenseInfoView: View {
    let licenseInfo: ViewModel.LicenseInfo

    let title: LocalizedStringKey = "License"
    let spacing: CGFloat = 16

    @Environment(ViewModel.self) var vm
    @Environment(\.dismiss) var dismiss

    @State private var counter: Int = 0

    @State var openRevoke = false
    @State var errorText: String = ""

    @State var progress = false

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Text(title).bold()
                Spacer()
            }
            .padding(spacing)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                if progress {
                    HStack {
                        Text("Communicating with authorization server...")
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    content
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(spacing)
            Divider()
            HStack {
                Button("Revoke Activation") {
                    openRevoke.toggle()
                }
                .alert(isPresented: $openRevoke) {
                    Alert(
                        title: Text("Revoke License"),
                        message: Text("This operation is limited, please be careful."),
                        primaryButton: .destructive(Text("Revoke")) {
                            tryRevoke()
                        },
                        secondaryButton: .cancel()
                    )
                }
                Button("Contact Us") {}
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .background(
                    Circle()
                        .hidden()
                        .confettiCannon(trigger: $counter, num: 64)
                        .rotationEffect(.degrees(-45))
                )
            }
            .padding(spacing)
            .disabled(progress)
        }
        .frame(maxWidth: .infinity)
        .onAppear { counter += 1 }
    }

    var content: some View {
        Group {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Image(systemName: "rosette")
                    .bold()
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("The MobileTransfer installed on this computer is licensed to:")
                        .bold()
                    if licenseInfo.licensee.lowercased() == "trail" {
                        Text("Trail User")
                            .foregroundStyle(.red)
                    } else {
                        Text(licenseInfo.licensee)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Image(systemName: "calendar")
                    .bold()
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("License expires on:")
                        .bold()
                    if licenseInfo.validateTo.timeIntervalSinceNow > 3650 * 24 * 60 * 60 {
                        Text("Never Expire")
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(licenseInfo.validateTo.formatted())
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            if !errorText.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    EmptyView()
                        .frame(width: 32, alignment: .leading)
                    Text(errorText)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func tryRevoke() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            progress = true
//            Mew.shared.tryRevokeLicense { result in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                progress = false
            }
//            }
        }
    }
}
