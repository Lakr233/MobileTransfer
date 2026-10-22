@testable import ApplePackage
import AsyncHTTPClient
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

@MainActor
final class SAPAuthenticationRequestTests: XCTestCase {
    private actor RecordingSigner: SAPRequestSigning {
        private var bodies: [Data] = []

        func sign(_ body: Data) throws -> Data {
            bodies.append(body)
            return Data([0xA5, UInt8(bodies.count)])
        }

        func recordedBodies() -> [Data] {
            bodies
        }
    }

    private actor FailingSigner: SAPRequestSigning { func sign(_: Data) throws -> Data {
        throw TestError.signingFailed
    } }

    private enum TestError: Error {
        case signingFailed
        case unexpectedBodyChunk
    }

    /// Run the actual AsyncHTTPClient body producer without opening a socket.
    private func bodyData(_ request: HTTPClient.Request) throws -> Data {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let eventLoop = group.next()
        let captured = NIOLockedValueBox(Data())
        let body = try XCTUnwrap(request.body)
        try body.stream(
            .init { part in
                guard case let .byteBuffer(buffer) = part else { return eventLoop.makeFailedFuture(TestError.unexpectedBodyChunk) }
                captured.withLockedValue { $0.append(contentsOf: buffer.readableBytesView) }
                return eventLoop.makeSucceededFuture(())
            },
        ).wait()
        return captured.withLockedValue { $0 }
    }

    private func makeRequest(
        endpoint: String = "https://auth.itunes.apple.com/login", code: String = "", signer: any SAPRequestSigning = RecordingSigner(),
    ) async throws -> HTTPClient.Request {
        try await Authenticator.makeRequest(
            endpoint: XCTUnwrap(URL(string: endpoint)), email: "reader+ä@example.invalid", password: "test<&password", code: code,
            cookies: [], deviceIdentifier: "00-11-22-33-44-55", sapSigner: signer,
        )
    }

    func testSignatureCoversExactSerializedHTTPBody() async throws {
        let signer = RecordingSigner()
        let request = try await makeRequest(code: "123456", signer: signer)
        let sentBody = try bodyData(request)
        let signedBodies = await signer.recordedBodies()
        XCTAssertEqual(signedBodies, [sentBody])
        XCTAssertEqual(request.method.rawValue, "POST")
        XCTAssertEqual(request.headers.first(name: "Content-Type"), "application/x-apple-plist")
        let signature = try XCTUnwrap(request.headers.first(name: "X-Apple-ActionSignature"))
        XCTAssertEqual(Data(base64Encoded: signature), Data([0xA5, 1]))
        let parameters = try XCTUnwrap(PropertyListSerialization.propertyList(from: sentBody, format: nil) as? [String: String])
        XCTAssertEqual(parameters["appleId"], "reader+ä@example.invalid")
        XCTAssertEqual(parameters["password"], "test<&password123456")
        XCTAssertEqual(parameters["attempt"], "2")
    }

    func testRetryRedirectAndVerificationReuseSignerState() async throws {
        let signer = RecordingSigner()
        let first = try await makeRequest(signer: signer)
        let retry = try await makeRequest(signer: signer)
        let redirect = try await makeRequest(endpoint: "https://p25-buy.itunes.apple.com/login", signer: signer)
        let verification = try await makeRequest(endpoint: "https://p25-buy.itunes.apple.com/login", code: "654321", signer: signer)
        let requests = [first, retry, redirect, verification]
        let sentBodies = try requests.map(bodyData)
        let signedBodies = await signer.recordedBodies()
        XCTAssertEqual(signedBodies, sentBodies)
        XCTAssertEqual(sentBodies[0], sentBodies[1])
        XCTAssertEqual(sentBodies[0], sentBodies[2])
        XCTAssertNotEqual(sentBodies[2], sentBodies[3])
        for (index, request) in requests.enumerated() {
            let header = try XCTUnwrap(request.headers.first(name: "X-Apple-ActionSignature"))
            XCTAssertEqual(Data(base64Encoded: header), Data([0xA5, UInt8(index + 1)]))
        }
    }

    func testUnapprovedEndpointNeverReachesSigner() async throws {
        let signer = RecordingSigner()
        do {
            _ = try await makeRequest(endpoint: "http://auth.itunes.apple.com/login", signer: signer)
            XCTFail("Expected unapproved endpoint rejection")
        } catch {
            let bodies = await signer.recordedBodies()
            XCTAssertTrue(bodies.isEmpty)
        }
    }

    func testSigningFailurePreventsRequestConstruction() async throws {
        do {
            _ = try await makeRequest(signer: FailingSigner())
            XCTFail("Expected signing failure")
        } catch TestError.signingFailed {
            // No request is returned to the HTTP client.
        }
    }

    func testSignatureHeaderIsRedactedCaseInsensitively() {
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Apple-ActionSignature", value: "sensitive-blob"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "x-apple-actionsignature", value: "sensitive-blob"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Token", value: "secret"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "Content-Type", value: "application/x-apple-plist"), "application/x-apple-plist")
        for header in ["Cookie", "Set-Cookie", "Authorization", "X-Apple-DSID", "Location", "X-Unknown"] {
            XCTAssertEqual(APLogger.safeHeaderValue(name: header, value: "private-value"), "<redacted>")
        }
        XCTAssertEqual(APLogger.safeURL("https://user:pass@apple.com/auth?guid=private#fragment"), "https://apple.com/auth")
    }

    func testLegacyAuthenticationEndpointRequiresTrailingSlash() throws {
        let path = "/WebObjects/MZFinance.woa/wa/authenticate"
        for host in ["buy.itunes.apple.com", "p25-buy.itunes.apple.com", "p123-buy.itunes.apple.com"] {
            let original = "https://\(host)\(path)?guid=A%2FB&value=1"
            let normalized = try XCTUnwrap(Bag.normalizedAuthEndpoint(from: original))
            XCTAssertEqual(normalized.absoluteString, "https://\(host)\(path)/?guid=A%2FB&value=1")
            XCTAssertEqual(Bag.normalizedAuthEndpoint(from: normalized.absoluteString), normalized)
        }
        for original in [
            "http://buy.itunes.apple.com\(path)", "https://example.invalid\(path)", "https://evilbuy.itunes.apple.com\(path)",
            "https://pfoo-buy.itunes.apple.com\(path)", "https://p25-buy.itunes.apple.com.example.invalid\(path)",
            "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/other",
        ] {
            XCTAssertEqual(Bag.normalizedAuthEndpoint(from: original)?.absoluteString, original)
        }
    }

    func testNativeAuthenticationEndpointNormalizationIsPreserved() {
        for path in ["/auth/v1/native", "/auth/v1/native/", "/auth/v1/native/fast", "/auth/v1/native/fast/"] {
            let original = "https://auth.itunes.apple.com\(path)?guid=example"
            XCTAssertEqual(
                Bag.normalizedAuthEndpoint(from: original)?.absoluteString,
                "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=example",
            )
        }
    }
}
