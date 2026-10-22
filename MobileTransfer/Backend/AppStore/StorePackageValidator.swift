// Adapted from Lakr233/Asspp 4.2.2, MIT License.
import Foundation
import ZIPFoundation

enum StorePackageValidator {
    static func validate(at url: URL, bundleID: String) throws {
        let archive = try Archive(url: url, accessMode: .read)
        let entries = archive.filter {
            let parts = $0.path.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }
        guard entries.count == 1, let entry = entries.first, entry.uncompressedSize <= 1024 * 1024 else {
            throw invalidPackage
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard chunk.count <= 1024 * 1024 - data.count else { throw invalidPackage }
            data.append(chunk)
        }
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              (info["CFBundleSupportedPlatforms"] as? [String])?.contains("iPhoneOS") == true else {
            throw invalidPackage
        }
    }

    private static var invalidPackage: NSError {
        NSError(domain: "iTM.AppPackage", code: 1, userInfo: [NSLocalizedDescriptionKey: "下载的安装包与此 App 或 iPhone 平台不匹配。"])
    }
}
