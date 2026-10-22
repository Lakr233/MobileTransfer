# App Store IPA backup integration

Uses the same ApplePackage 2.0.3 release as Lakr233/Asspp 4.2.2
(commit 6682eb8f831a7b5c62dc14ea97088769c6adba48).
Vendored ApplePackage is based on 2.0.3 (773583a29c6b1f1b0d0783d0a15d3ddafcd85eec).

- Reuses the existing iTM account sheet and application backup task.
- Keeps one SAP-signed Authenticator instance across verification-code attempts.
- Uses ApplePackage's volumeStore -> redownload -> updateProduct recovery chain.
- Stores accounts in the macOS Keychain; persistence failure keeps the login sheet open.
- Validates the main Payload app's bundle identifier and iPhoneOS platform before signature injection.
- Downloads packages owned by the account. Does not automatically purchase apps.
- These are App Store downloads; installed apps are not extracted from the phone.
- TestFlight and enterprise apps are excluded by the existing scan.

The package validation logic is adapted from Asspp's StorePackageValidator.swift,
under its MIT license (see LICENSE).

The previous native-helper / Python authentication probes are no longer used.
The only vendored compatibility change is the OpenSSL minimum from 4.0.1 to
3.6.2, to share the existing device library dependency. Upstream SAP protocol
code is unchanged.

Live authentication and IPA downloading require user-entered credentials and
must be verified separately from compilation.
