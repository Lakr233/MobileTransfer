# Synthetic SAP setup vectors

`handshake.json` was generated on 2026-10-20 by the independent Python
initialization/exchange arithmetic implementation. Its certificate is a new
self-signed RSA-2048 test certificate with a deliberately sign-padded serial.
The private key is not included and is not needed for verification.

All entropy words, times, server fields, echoes and replies are synthetic.
No certificate from Apple's service, account information, password, token,
cookie, server-issued session or recorded handshake is present.

Each case includes the complete expected setup request, a synthetic CBC
reply, SHA-256 of the retained RNG words in little-endian order, its cursor
and seeds, and the F2 material. Cases cover zero/maximal entropy and signed
or overflowing Unix seconds. The retained response key and echo are test
values used to check this synthetic exchange only.
