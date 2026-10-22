# SAP authentication

SAP initialization, both setup exchanges, and request signing are integrated
into `ApplePackage`. There is one library product and one command-line product,
`ApplePackageTool`. `CApplePackage` is an internal implementation target.

## Login

```sh
swift run ApplePackageTool login you@example.com
# Or supply APPLEPACKAGE_PASSWORD in the process environment.
```

The command retrieves Apple's SAP certificate over verified HTTPS, generates
fresh local entropy and time inputs, sends protocol-200 setup, decrypts and
validates the reply's echoed client material, and signs the exact final XML
body in `X-Apple-ActionSignature`. Authentication and token rotation always
establish SAP; setup or signing failure stops authentication.

The terminal prompts for a six-digit verification code. The same authentication
actor retains its SAP signer, cookies, routing endpoint, and store information
for that continuation. `--code` supports noninteractive callers. Passwords can
be positional, read from `APPLEPACKAGE_PASSWORD`, or entered without terminal
echo. `--guid` accepts exactly twelve hexadecimal characters.

```swift
import ApplePackage

let session = try await Authenticator()
do {
    let account = try await session.authenticate(email: email, password: password)
    // Store the account securely.
} catch AuthenticationError.verificationCodeRequired {
    let account = try await session.authenticate(email: email, password: password, code: verificationCode)
    // Store the account securely.
}
```

The static `Authenticator.authenticate` convenience creates a fresh actor for
one call. Retain an instance when continuing a verification challenge.
Concurrent authentication calls on the same instance are rejected.

## Implementation

The setup RNG and whitening operations are repository-authored C arithmetic.
Swift owns RSA-OAEP/SHA-1, AES-128-CBC, HMAC, record parsing, F2, the session
cipher, and signature assembly. Standard cryptography uses statically linked
OpenSSL. No Apple private framework, original executable, runtime Python,
instruction interpreter, or saved handshake is used by the login path.

Address-like constants are integer salts in the reconstructed algorithm;
they are never dereferenced. Bundled tables are fixed algorithm data, checked
against SHA-256 hashes. Session bytes, RNG state, signatures, and credentials
are not production resources. The low-level logical-session and research
snapshot decoders remain available for offline compatibility checks only.

```text
blob = 03 || BE32(platform) || BE32(256) || F1
          || BE32(len(F2)) || F2 || BE32(len(F3)) || F3 || zero padding to 16 bytes
d = SHA1(blob || body)
a = E(IV XOR d[0:16])
tag = E(a XOR (d[16:20] || 12 zero bytes))
signature = 02 || IV || tag || BE32(len(blob)) || blob
```

`SAPSigner.connect()` also exposes fresh setup for clients needing only signing.
One signer actor advances one RNG stream. Signatures must remain paired with
the exact body supplied to `sign`.

## Verification

```sh
Scripts/run-tests.sh unit
APPLEPACKAGE_SAP_LIVE_PROBE=1 APPLEPACKAGE_SAP_PROBE_CONTROLS=1 \
  swift test --filter SAPLiveProbeTests
```

Offline tests compare four deterministic fresh exchanges with the independent
Python arithmetic implementation, including negative/overflowing Unix seconds,
zero and maximal entropy words, RSA serial sign padding, complete request
bytes, retained RNG state, and synthetic decrypted session fields. All fixture
certificates and server replies are synthetic. Malformed and unrelated replies
are rejected. Existing synthetic tests cover consecutive complete signatures,
F2/cipher vectors, serialization, resource hashes, and bounded input handling.

Request tests cover exact body/signature pairing, state advancement, signing
failure, HTTPS destination validation, and log redaction. Parser tests cover
password sources, code/GUID validation, and removed SAP options.

The opt-in live probe creates fresh SAP state and uses only invented
`example.invalid` credentials with a random GUID. It prints sanitized response
summaries. On 2026-10-20, the signed request returned HTTP 200 with a business
plist; unsigned and corrupted-tag controls returned HTTP 403. This establishes
signature acceptance for the tested service, not account authentication or
verification-code delivery. The generic `MZFinance.BadLogin.Configurator_message`
is also returned for invented accounts; entering the verification-code branch
alone does not establish that a code was delivered.

Verbose logs omit URL queries and redact every header except a small set of
public transport metadata. Never commit real account identifiers, passwords,
codes, cookies, tokens, signatures, or server-issued SAP state.

## Download requests

Legacy download and purchase requests use the authenticated account session;
they do not use the login `X-Apple-ActionSignature`. Download recovery follows
`volumeStoreDownloadProduct` → version-pinned `redownloadProduct` → `updateProduct`.
The last step is attempted only for an empty HTTP 500 and only when Apple's bag
advertises the approved update endpoint. Each endpoint is attempted at most once.
Recovery responses must match the requested app, bundle identifier, and version.

Compared with [ipatool's download implementation](https://github.com/majd/ipatool/blob/5dc4c8058db3a23e9de081ac766cc917713a65cf/pkg/appstore/appstore_download_product.go),
ApplePackage does not yet implement the preferred `ent/download` path and its
separate `kbsync` blob. That blob is not a SAP action signature. ipatool also signs
purchase-history requests with SAP; ApplePackage does not expose that API.

## Distribution

Release archives contain `ApplePackageTool`, `ApplePackage_ApplePackage.bundle`,
and Swift runtime libraries for older macOS versions; keep them together after extraction.
The CLI requires macOS 11+. The library supports iOS 15+, Mac Catalyst 15+,
tvOS 15+, and visionOS 1+, using Swift 6.2 or later. Linux is unsupported.
