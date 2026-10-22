# Explicit Apple ID verification request

Models the local BetaCat flow from nibeta_betacat/internal/apple_admin:
SRP sign-in, trusted-device challenge, trusted-number factors, explicit SMS request.
The SRP arithmetic is reused from that project's apple_sirp.go.

The helper receives credentials over stdin, emits sanitized phase/status JSON,
and keeps all session cookies and Apple session headers in RAM until exit.
No account or device data is read from BetaCat's running service or configuration.
The app keeps its separate ApplePackage Authenticator instance for Store login.
A requested SMS does not establish App Store authentication or guarantee delivery.

Build: go build . (Go 1.25+). Xcode runs build.sh to bundle the helper.
Tests: go test ./... . srp_fixture.json contains only synthetic test values,
verified against an independent Python SRP server; no live account data.
--preflight checks only Apple's public login page and requires no credentials.

2026-10-21: public login preflight returns HTTP 200. Its embedded public widget
key matches BetaCat's default. Live attempt after restoring config fallback
failed at password-complete (HTTP 401, -20101), before SMS sending. Matched
BetaCat's original account casing and excluded init-session headers from SRP
completion; the final live retry returned the same HTTP 401 / -20101 at
password-complete. Further automatic retries were stopped. No successful SMS
or Store login has been established by this flow.

2026-10-21 follow-up: replaced the adapted SRP HTTP sequence with the original
BetaCat sign-in functions, including its browser headers and cookie bootstrap.
Only dependency/input wiring, bounded parameter checks and proof-of-work limits
are adapted. Live test via the retained iTM sheet still returned HTTP 401 / -20101
at password-complete. No SMS request occurred. Credential type/account validation
is required before further authenticated retries; no raw credentials were read
from BetaCat or the iTM sheet.

Final live finding: Store authentication using the original user-entered account
casing explicitly returned: account disabled for security reasons, reset required.
All authentication attempts stopped. Account recovery must be completed by the
user through Apple; the app now maps this condition to Chinese and gates retries.
