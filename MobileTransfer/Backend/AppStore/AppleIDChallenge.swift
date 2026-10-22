import Foundation
import ApplePackage

/// BetaCat-style explicit challenge request. Raw credentials travel only over a private pipe.
enum AppleIDChallenge {
    struct Response: Decodable, Sendable {
        let status: String
        let phase: String
        let httpStatus: Int?
        let failureType: String?
        let errorDomain: String?
        let account: ApplePackage.Account?
    }
    private struct Request: Encodable { let email: String; let password: String }

    static func send(email: String, password: String, system: Bool = false) async throws -> Response {
        guard let url = Bundle.main.url(forResource: system ? "itm-system-store-auth" : "itm-apple-challenge", withExtension: nil, subdirectory: "Helpers") else {
            throw failure("验证码组件不可用。")
        }
        let input = try JSONEncoder().encode(Request(email: email, password: password))
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdin = Pipe(), stdout = Pipe()
            process.executableURL = url
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            try process.run()
            do {
                try stdin.fileHandleForWriting.write(contentsOf: input)
                try stdin.fileHandleForWriting.close()
            } catch {
                try? stdin.fileHandleForWriting.close()
                process.terminate()
                throw error
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, data.count <= 65536 else { throw failure("验证码请求未完成。") }
            return try JSONDecoder().decode(Response.self, from: data)
        }.value
    }

    static func message(for response: Response) -> String {
        if response.status == "sms_requested" { return "已请求发送短信验证码，请查看此 Apple 账号绑定的手机。" }
        if response.status == "no_challenge" { return "Apple 网页认证已通过，但没有提供验证码挑战；商店登录尚未完成。" }
        let step: String
        switch response.phase {
        case "password-init", "password-complete": step = "Apple 未通过账号认证，尚未发送验证码"
        case "no-sms-number", "challenge-options": step = "Apple 未提供可用的短信验证方式"
        case "send-sms": step = "Apple 未接受发送短信请求"
        case "system-authentication": step = "macOS 系统认证未完成" + (response.errorDomain.map { "（\($0)）" } ?? "")
        case "system-store-credentials": step = "系统认证未返回可用的商店凭据"
        case "system-account-mismatch": step = "系统返回的账号与当前填写的账号不一致，已停止登录"
        case "system-options", "system-component", "system-request", "system-framework": step = "此系统未提供可用的商店认证接口"
        default: step = "无法建立 Apple 验证会话"
        }
        let details = [response.httpStatus.map { "HTTP \($0)" }, response.failureType.map { "错误 \($0)" }].compactMap { $0 }.joined(separator: "，")
        return step + (details.isEmpty ? "。" : "（\(details)）。")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "iTM.AppleIDChallenge", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
