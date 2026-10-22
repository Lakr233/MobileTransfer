# macOS native Store authentication experiment

Uses the system AppleMediaServices authentication task instead of reconstructing
Apple's SAP/SRP login protocol. This is a private, OS-dependent API.

The request explicitly enables ephemeral mode, disables account activation,
account creation and secondary credentials, and leaves account save options at
zero. It validates the returned account username against the requested username
before returning any token to iTM. It never enumerates existing system accounts.
Credentials use private stdin/stdout pipes. Result/error bodies and raw userInfo
are never logged for real accounts. A --no-dialog diagnostic mode only allows
extra sanitized error descriptions for the reserved @example.invalid domain.

--preflight constructs and verifies options without sending credentials or
performing authentication. It succeeded on this Mac. A reserved synthetic
account received AMSErrorDomain 100; that result neither proves nor disproves
real-account authentication. User-driven live verification remains required.

The helper is built and bundled by Tools/AppleIDChallenge/build.sh.
No purchase, download, account recovery or system account switch is performed.

Live test result (2026-10-21): AMSErrorDomain 100 -> AMSErrorDomain 2 ->
NSCocoaErrorDomain 4099. A synthetic diagnostic confirms the failing connection
is com.apple.ak.auth.xpc. The user akd launch service is running. This is a
system-service connection failure and provides no evidence that the Apple
account is disabled. No successful authentication/token export or IPA download
has been established. Do not keep requesting user credentials for this route.
