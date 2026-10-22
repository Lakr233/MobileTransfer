//
//  AMDManager+Apps.swift
//
//
//  Created by QAQ on 2023/8/15.
//

import AppleMobileDeviceLibrary
import Foundation

public extension AppleMobileDeviceManager {
    func requireInstallProxyService(
        device: idevice_t,
        name: String = UUID().uuidString,
        task: (instproxy_client_t?) -> Void
    ) {
        var client: instproxy_client_t?
        guard instproxy_client_start_service(device, &client, name) == INSTPROXY_E_SUCCESS,
              let client
        else {
            task(nil)
            return
        }
        task(client)
        instproxy_client_free(client)
    }

    func listApplications(device: idevice_t, includeIcons: Bool = true) -> AnyCodableDictionary? {
        var applicationDic: AnyCodableDictionary = [:]
        var fullyDecoded = false
        requireInstallProxyService(device: device) { inst_client in
            guard let inst_client else { return }
            let options: [String: Any] = [
                "ApplicationType": "User",
                "ReturnAttributes": [
                    "CFBundleIdentifier",
                    "CFBundleShortVersionString",
                    "CFBundleDisplayName",
                    "StaticDiskUsage",
                    "DynamicDiskUsage",
                    "ApplicationSINF",
                    "iTunesMetadata",
                ], // looks like that's all, really is?
            ]
            let data = try! PropertyListEncoder().encode(AnyCodable(options))
            var query: plist_t?
            defer { plist_free(query) }
            _ = data.withUnsafeBytes { byte in
                plist_from_memory(byte.baseAddress, UInt32(byte.count), &query, nil)
            }
            guard let query else { return }

            var apps: plist_t?
            defer { plist_free(apps) }

            instproxy_browse(inst_client, query, &apps)
            guard let apps, plist_get_node_type(apps) == PLIST_ARRAY else { return }

            var sb_client: sbservices_client_t?
            defer { if let sb_client { sbservices_client_free(sb_client) } }
            if includeIcons {
                sbservices_client_start_service(device, &sb_client, UUID().uuidString)
            }

            let appCount = plist_array_get_size(apps) // later just free apps, frees all
            for idx in 0 ..< appCount {
                // if any error, break entirely, none-fully-working backup is not acceptable
                guard let app_entry = plist_array_get_item(apps, idx),
                      plist_get_node_type(app_entry) == PLIST_DICT
                else {
                    assertionFailure()
                    return
                }

                guard let bundleHandler = plist_dict_get_item(app_entry, "CFBundleIdentifier"),
                      plist_get_node_type(bundleHandler) == PLIST_STRING
                else {
                    assertionFailure()
                    return
                }
                var buf: UnsafeMutablePointer<CChar>?
                defer { free(buf) }
                plist_get_string_val(bundleHandler, &buf)
                guard let buf else {
                    assertionFailure()
                    return
                }
                let bundleIdentifier = String(cString: buf)

                guard let data = read_plist_to_binary_data(plist: app_entry),
                      var appElement = try? PropertyListDecoder().decode([String: AnyCodable].self, from: data)
                else {
                    assertionFailure()
                    return
                }

                if let sb_client {
                    var buf: UnsafeMutablePointer<CChar>?
                    defer { free(buf) }
                    var len: UInt64 = 0
                    if sbservices_get_icon_pngdata(sb_client, bundleIdentifier, &buf, &len) == SBSERVICES_E_SUCCESS,
                       let buf,
                       len > 0
                    {
                        let pngData = Data(bytes: buf, count: Int(len))
                        appElement["PlaceholderIcon"] = .init(pngData)
                    }
                }

                applicationDic[bundleIdentifier] = .init(appElement)
            }

            fullyDecoded = true
        }
        guard fullyDecoded else { return nil }
        return applicationDic
    }

    /// Device usage is a dated snapshot, not the size of encrypted archive files.
    func applicationUsageSnapshot(udid: String) -> [String: Any]? {
        guard let apps = listApplications(udid: udid, connection: .usb, includeIcons: false),
              let data = try? PropertyListEncoder().encode(apps),
              let decoded = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: [String: Any]]
        else { return nil }
        var sizes: [String: [String: Int64]] = [:]
        for (identifier, app) in decoded {
            var entry: [String: Int64] = [:]
            for key in ["StaticDiskUsage", "DynamicDiskUsage"] {
                if let number = app[key] as? NSNumber, number.int64Value >= 0 {
                    entry[key] = number.int64Value
                }
            }
            if !entry.isEmpty { sizes[identifier] = entry }
        }
        return ["DeviceIdentifier": udid, "CapturedAt": Date(), "Applications": sizes]
    }

    /// Streams icons after the app list is available, reusing one SpringBoard service.
    /// Cancellation is checked between requests; a failed icon does not fail the list.
    func readApplicationIcons(
        udid: String,
        identifiers: [String],
        progress: Progress,
        onIcon: (String, Data) -> Void
    ) {
        guard !progress.isCancelled else { return }
        requireDevice(udid: udid, connection: .usb) { device in
            guard let device, !progress.isCancelled else { return }
            var client: sbservices_client_t?
            guard sbservices_client_start_service(device, &client, UUID().uuidString) == SBSERVICES_E_SUCCESS,
                  let client else { return }
            defer { sbservices_client_free(client) }
            for identifier in identifiers {
                guard !progress.isCancelled else { break }
                autoreleasepool {
                    var buffer: UnsafeMutablePointer<CChar>?
                    defer { free(buffer) }
                    var length: UInt64 = 0
                    guard sbservices_get_icon_pngdata(client, identifier, &buffer, &length) == SBSERVICES_E_SUCCESS,
                          let buffer, length > 0 else { return }
                    onIcon(identifier, Data(bytes: buffer, count: Int(length)))
                }
            }
        }
    }

    func listApplications(
        udid: String,
        connection: ConnectionMethod = configuration.connectionMethod,
        includeIcons: Bool = true
    ) -> AnyCodableDictionary? {
        var result: AnyCodableDictionary?
        requireDevice(udid: udid, connection: connection) { device in
            guard let device else { return }
            result = listApplications(device: device, includeIcons: includeIcons)
        }
        return result
    }
}

private func read_plist_to_binary_data(plist: plist_t?) -> Data? {
    guard let plist else { return nil }
    var buf: UnsafeMutablePointer<CChar>?
    defer { free(buf) }
    var len: UInt32 = 0
    guard plist_to_bin(plist, &buf, &len) == PLIST_ERR_SUCCESS,
          let buf,
          len > 0
    else { return nil }
    return Data(bytes: buf, count: Int(len))
}
