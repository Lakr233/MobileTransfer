//
//  RestorePasswrodView.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/26.
//

import SwiftUI

struct RestorePasswordView: View {
    @Environment(ViewModel.self) var vm

    @State var helpURL: String?

    let inset: CGFloat = 4

    var body: some View {
        @Bindable var vm = vm
        CardContentView {
            CardContentHeader(icon: "key", title: "Password") {
                if vm.restorePassword.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            Text("This backup is encrypted, please provide the password to restore.")

            Text(String("888"))
                .frame(maxWidth: .infinity)
                .hidden()
                .overlay {
                    SecureField("Password", text: $vm.restorePassword)
                        .disableAutocorrection(true)
                        .textFieldStyle(.plain)
                        .padding(inset)
                        .background(RoundedRectangle(cornerRadius: 4).foregroundStyle(.accent.opacity(0.1)))
                        .padding(.horizontal, -inset)
                }

            Button {
                helpURL = "https://support.apple.com/108313"
            } label: {
                Text("Forgot password?")
                    .underline()
                    .foregroundStyle(.accent)
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $helpURL) {
            WebSheetView(url: URL(string: $0))
        }
    }
}
