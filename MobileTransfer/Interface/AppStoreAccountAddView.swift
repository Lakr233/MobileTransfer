import ApplePackage
import SwiftUI

struct AppStoreAccountAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State var email: String = ""
    @State private var password = ""
    @State private var code = ""
    @State private var codeRequired = false
    @State private var authenticator: ApplePackage.Authenticator?
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var challengeMessage: String?
    @State private var accountRestricted = false
    @State private var showOfficialVerification = false
    var completion: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("登录 Apple 账号").font(.headline)
            Divider()
            TextField("Apple 账号", text: $email)
                .disableAutocorrection(true)
                .disabled(isAuthenticating)
            SecureField("密码", text: $password).disabled(isAuthenticating)
            if codeRequired {
                TextField("六位验证码", text: $code).disabled(isAuthenticating)
                Text(challengeMessage ?? "商店登录尚未完成。如果没有收到验证码，可请求短信验证。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("发送短信验证码") { requestCode() }
                    .disabled(accountRestricted || isAuthenticating)
            }
            if isAuthenticating {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在登录…").foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("通过 Apple 官方页面获取验证码…") { openOfficialVerification() }
                .disabled(isAuthenticating || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            Link("iforgot.apple.com · 重设密码／恢复账号", destination: URL(string: "https://iforgot.apple.com/")!)
            if accountRestricted {
                Button("账号已恢复，重新登录") {
                    accountRestricted = false
                    resetAuthentication()
                }
            }
            Divider()
            HStack {
                Button("取消") { dismiss() }
                    .disabled(isAuthenticating)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(codeRequired ? "验证" : "登录") { authenticate() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(accountRestricted || isAuthenticating || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (codeRequired && code.filter(\.isNumber).count != 6))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled(isAuthenticating)
        .sheet(isPresented: $showOfficialVerification) {
            OfficialAppleVerificationView {
                showOfficialVerification = false
                codeRequired = true
                errorMessage = nil
                challengeMessage = "请填写 Apple 设备上收到的验证码。iTM 尚未完成商店登录。"
            }
        }
        .onChange(of: email) { accountRestricted = false; resetAuthentication() }
        .onChange(of: password) { resetAuthentication() }
        .onDisappear { password = ""; code = ""; authenticator = nil }
    }

    private func resetAuthentication() {
        authenticator = nil
        codeRequired = false
        code = ""
        errorMessage = nil
        challengeMessage = nil
    }

    private func reportAuthentication(_ stage: String) {
        #if DEBUG
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let status = ["stage": stage, "implementation": "ApplePackage-2.0.3", "time": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: root.appendingPathComponent("Build/ipa-probe-status.json"), options: [.atomic, .completeFileProtection])
        }
        #endif
    }

    private func openOfficialVerification() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                if authenticator == nil { authenticator = try await ApplePackage.Authenticator() }
                errorMessage = nil
                accountRestricted = false
                showOfficialVerification = true
                reportAuthentication("official-verification-opened")
            } catch {
                errorMessage = "无法建立商店认证会话，请检查网络后重试。"
            }
        }
    }

    private func requestCode(system: Bool = false) {
        guard !isAuthenticating, system || !accountRestricted else { return }
        isAuthenticating = true
        errorMessage = nil
        reportAuthentication(system ? "system-authenticating" : "requesting-sms")
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                let response = try await AppleIDChallenge.send(email: email, password: password, system: system)
                if response.status == "authenticated", let account = response.account {
                    try AppStoreBackend.shared.save(email: email, password: "", appleAccount: account)
                    reportAuthentication("system-authenticated")
                    password = ""
                    code = ""
                    completion?(email)
                    dismiss()
                    return
                }
                let message = AppleIDChallenge.message(for: response)
                if response.status == "failed", system || ["password-init", "password-complete"].contains(response.phase) {
                    codeRequired = false
                    code = ""
                    authenticator = nil
                    challengeMessage = nil
                    errorMessage = message
                } else {
                    challengeMessage = message
                }
                reportAuthentication((system ? "system-" : "sms-") + response.status + "-" + response.phase)
            } catch {
                errorMessage = "验证码请求未完成，请检查网络后重试。"
                reportAuthentication("sms-request-failed")
            }
        }
    }

    private func authenticate() {
        guard !isAuthenticating, !accountRestricted else { return }
        isAuthenticating = true
        errorMessage = nil
        reportAuthentication("authenticating")
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                let session: ApplePackage.Authenticator
                if let authenticator { session = authenticator }
                else {
                    session = try await ApplePackage.Authenticator()
                    authenticator = session
                }
                let account = try await session.authenticate(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password, code: code
                )
                try AppStoreBackend.shared.save(email: email, password: password, appleAccount: account)
                reportAuthentication("authenticated")
                password = ""
                code = ""
                completion?(email)
                dismiss()
            } catch {
                if case ApplePackage.AuthenticationError.verificationCodeRequired = error {
                    reportAuthentication("verification-required")
                    codeRequired = true
                    errorMessage = nil
                } else {
                    let description = error.localizedDescription.lowercased()
                    if description.contains("disabled for security reasons") || description.contains("locked for security reasons") {
                        accountRestricted = true
                        codeRequired = false
                        reportAuthentication("account-security-restricted")
                        errorMessage = "Apple 商店认证返回账号受限。请在 Apple 官网核查，或确认后重新登录。"
                    } else {
                        reportAuthentication("failed")
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
