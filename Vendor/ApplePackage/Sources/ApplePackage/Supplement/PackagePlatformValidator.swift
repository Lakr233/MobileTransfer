//
//  PackagePlatformValidator.swift
//  ApplePackage
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import ZIPFoundation

public enum PackagePlatformValidator {
    public static func ensurePackage(at url: URL, supports entityType: EntityType) throws {
        guard entityType == .appleTV else { return }

        let archive = try Archive(url: url, accessMode: .read)

        for entry in archive {
            guard entry.path.hasPrefix("Payload/"),
                  entry.path.hasSuffix(".app/Info.plist")
            else {
                continue
            }

            var data = Data()
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }

            guard let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil,
            ) as? [String: Any] else {
                continue
            }

            let supportedPlatforms = plist["CFBundleSupportedPlatforms"] as? [String] ?? []
            if supportedPlatforms.contains("AppleTVOS") {
                return
            }
        }

        try ensureFailed(Strings.appleTVPackageValidationFailed)
    }
}
