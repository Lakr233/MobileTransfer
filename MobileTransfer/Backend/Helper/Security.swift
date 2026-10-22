//
//  Security.swift
//  Axchange
//
//  Created by 秋星桥 on 2024/12/2.
//

import Foundation
import Security

enum Security {
    static let requirementText =
        #"""
        anchor apple generic
        and identifier "tech.nootag.itm"
        and (
            certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */
            or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
                and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
                and certificate leaf[subject.OU] = "BK368UYPY3"
        )
        """#
        .trimmingCharacters(in: .whitespacesAndNewlines)

    private static func secCall<T>(_ exec: (_ input: UnsafeMutablePointer<T?>) -> (OSStatus)) throws -> T {
        let pointer = UnsafeMutablePointer<T?>.allocate(capacity: 1)
        let err = exec(pointer)
        guard err == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err))
        }
        guard let value = pointer.pointee else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err))
        }
        return value
    }

    static func validateAppSignature() -> Bool {
        #if DEBUG
            return true
        #else
            do {
                let req = try secCall { SecRequirementCreateWithString(requirementText as NSString, [], $0) }
                let url = URL(fileURLWithPath: CommandLine.arguments.first!)
                let code = try secCall { SecStaticCodeCreateWithPath(url as NSURL, [], $0) }

                var errorQ: Unmanaged<CFError>?
                let err = SecStaticCodeCheckValidityWithErrors(code, [], req, &errorQ)
                if err == errSecSuccess { return true }
            } catch {}
            return false
        #endif
    }

    static func removeDebugger() {
        #if !DEBUG
            do {
                typealias ptrace = @convention(c) (_ request: Int, _ pid: Int, _ addr: Int, _ data: Int) -> AnyObject
                let open = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOW)
                if unsafeBitCast(open, to: Int.self) > 0x1024 {
                    let result = dlsym(open, "ptrace")
                    if let result {
                        let target = unsafeBitCast(result, to: ptrace.self)
                        _ = target(0x1F, 0, 0, 0)
                    }
                }
            }
        #endif
    }

    static func crashOut() -> Never {
        fatalError("Binary integrity validation failed.")
    }
}
