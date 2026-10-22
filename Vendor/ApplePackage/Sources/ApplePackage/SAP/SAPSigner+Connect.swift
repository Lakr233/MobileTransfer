import AsyncHTTPClient
import Foundation

public extension SAPSigner {
    /// Establish protocol-200 state using Apple's certificate and two-round setup service.
    static func connect() async throws -> SAPSigner {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        func exchange(url: String, payload: Data? = nil, key: String) async throws -> Data {
            let body = try payload.map {
                try PropertyListSerialization.data(fromPropertyList: ["sign-sap-setup-buffer": $0], format: .xml, options: 0)
            }
            let request = try HTTPClient.Request(
                url: url, method: body == nil ? .GET : .POST,
                headers: ["User-Agent": Configuration.userAgent, "Content-Type": "application/x-apple-plist"], body: body.map { .data($0) },
            )
            let accumulator = ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)
            let response = try await client.execute(request: request, delegate: accumulator).futureResult.get()
            guard response.status == .ok, let buffer = response.body, buffer.readableBytes <= 2 * 1024 * 1024,
                  let plist = try PropertyListSerialization.propertyList(from: Data(buffer.readableBytesView), format: nil) as? [String: Any],
                  let data = plist[key] as? Data, !data.isEmpty, data.count <= 1 << 20
            else { throw SAPError.invalidInput("SAP setup service returned an invalid response (HTTP \(response.status.code))") }
            return data
        }
        let certificate = try await exchange(url: "https://s.mzstatic.com/sap/setupCert.plist", key: "sign-sap-setup-cert")
        let handshake = try SAPHandshake(certificate: certificate)
        let reply = try await exchange(
            url: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy", payload: handshake.request, key: "sign-sap-setup-buffer",
        )
        return try SAPSigner(session: handshake.complete(reply))
    }
}
