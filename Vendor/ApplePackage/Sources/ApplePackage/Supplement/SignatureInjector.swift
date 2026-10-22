//
//  SignatureInjector.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import Foundation
import ZIPFoundation

public enum SignatureInjector {
    public static func inject(
        sinfs: [Sinf],
        iTunesMetadata: Data,
        into packagePath: String,
    ) async throws {
        let archive = try Archive(url: URL(fileURLWithPath: packagePath), accessMode: .update)

        let bundleName = try readBundleName(from: archive)

        if let manifest = try readManifestPlist(from: archive) {
            try injectFromManifest(manifest, into: archive, sinfs: sinfs, bundleName: bundleName)
        } else if let info = try readInfoPlist(from: archive) {
            try injectFromInfo(info, into: archive, sinfs: sinfs, bundleName: bundleName)
        } else {
            try ensureFailed("could not read manifest or info plist")
        }

        try injectMetadata(iTunesMetadata, into: archive)
    }

    private static func readBundleName(from archive: Archive) throws -> String {
        for entry in archive {
            if entry.path.contains(".app/Info.plist"), !entry.path.contains("/Watch/") {
                let components = entry.path.split(separator: "/")
                if components.count >= 2 {
                    let appName = components[components.count - 2]
                    return String(appName.replacingOccurrences(of: ".app", with: ""))
                }
            }
        }
        try ensureFailed("could not read bundle name")
    }

    private static func readManifestPlist(from archive: Archive) throws -> PackageManifest? {
        for entry in archive {
            if entry.path.hasSuffix(".app/SC_Info/Manifest.plist") {
                var data = Data()
                _ = try archive.extract(entry, consumer: { data.append($0) })
                return try PropertyListDecoder().decode(PackageManifest.self, from: data)
            }
        }
        return nil
    }

    private static func readInfoPlist(from archive: Archive) throws -> PackageInfo? {
        for entry in archive {
            if entry.path.contains(".app/Info.plist") {
                var data = Data()
                _ = try archive.extract(entry, consumer: { data.append($0) })
                return try PropertyListDecoder().decode(PackageInfo.self, from: data)
            }
        }
        return nil
    }

    private static func injectFromManifest(
        _ manifest: PackageManifest,
        into archive: Archive,
        sinfs: [Sinf],
        bundleName: String,
    ) throws {
        for (index, sinfPath) in manifest.sinfPaths.enumerated() {
            guard index < sinfs.count else { continue }
            let sinf = sinfs[index]
            let fullPath = "Payload/\(bundleName).app/\(sinfPath)"
            if archive[fullPath] != nil {
                try ensureFailed("sinf file already exists: \(fullPath)")
            }
            try archive.addEntry(with: fullPath, type: .file, uncompressedSize: Int64(sinf.sinf.count), compressionMethod: .deflate, provider: { (position: Int64, size: Int) -> Data in
                let start = sinf.sinf.startIndex.advanced(by: Int(position))
                let end = start.advanced(by: size)
                return sinf.sinf.subdata(in: start ..< end)
            })
        }
    }

    private static func injectMetadata(
        _ metadata: Data,
        into archive: Archive,
    ) throws {
        let path = "iTunesMetadata.plist"
        guard archive[path] == nil else { return }
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(metadata.count),
            compressionMethod: .deflate,
            provider: { (position: Int64, size: Int) -> Data in
                let start = metadata.startIndex.advanced(by: Int(position))
                let end = start.advanced(by: size)
                return metadata.subdata(in: start ..< end)
            },
        )
    }

    private static func injectFromInfo(
        _ info: PackageInfo,
        into archive: Archive,
        sinfs: [Sinf],
        bundleName: String,
    ) throws {
        guard let sinf = sinfs.first else { return }
        let sinfPath = "Payload/\(bundleName).app/SC_Info/\(info.bundleExecutable).sinf"
        if archive[sinfPath] != nil {
            try ensureFailed("sinf file already exists: \(sinfPath)")
        }
        try archive.addEntry(with: sinfPath, type: .file, uncompressedSize: Int64(sinf.sinf.count), compressionMethod: .deflate, provider: { (position: Int64, size: Int) -> Data in
            let start = sinf.sinf.startIndex.advanced(by: Int(position))
            let end = start.advanced(by: size)
            return sinf.sinf.subdata(in: start ..< end)
        })
    }
}

private struct PackageManifest: Decodable {
    let sinfPaths: [String]

    enum CodingKeys: String, CodingKey {
        case sinfPaths = "SinfPaths"
    }
}

private struct PackageInfo: Decodable {
    let bundleExecutable: String

    enum CodingKeys: String, CodingKey {
        case bundleExecutable = "CFBundleExecutable"
    }
}
