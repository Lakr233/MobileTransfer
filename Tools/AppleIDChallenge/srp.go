package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"
)

var (
	appleSIRPN, _ = new(big.Int).SetString(
		"AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB694B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73",
		16,
	)
	appleSIRPG = big.NewInt(2)
)

func sirpStartAuthentication() (*big.Int, string, error) {
	randomBytes := make([]byte, 256)
	if _, err := rand.Read(randomBytes); err != nil {
		return nil, "", err
	}
	a := new(big.Int).SetBytes(randomBytes)
	A := new(big.Int).Exp(appleSIRPG, a, appleSIRPN)
	return a, numToEvenHex(A), nil
}

func sirpProcessChallenge(username string, aSecret *big.Int, aHex, encryptedPasswordHex, saltHex, bHex string) (string, string, error) {
	if aSecret == nil || strings.TrimSpace(aHex) == "" {
		return "", "", fmt.Errorf("sirp a not initialized")
	}
	bb, err := hexToBigInt(bHex)
	if err != nil {
		return "", "", fmt.Errorf("invalid srp b: %v", err)
	}
	if new(big.Int).Mod(bb, appleSIRPN).Sign() == 0 {
		return "", "", fmt.Errorf("invalid srp b modulo N")
	}

	k, err := srpH(numToEvenHex(appleSIRPN), numToEvenHex(appleSIRPG))
	if err != nil {
		return "", "", err
	}
	x, err := srpCalcXHex(encryptedPasswordHex, saltHex)
	if err != nil {
		return "", "", err
	}
	u, err := srpH(aHex, bHex)
	if err != nil {
		return "", "", err
	}
	if u.Sign() == 0 {
		return "", "", fmt.Errorf("invalid srp u")
	}

	gx := new(big.Int).Exp(appleSIRPG, x, appleSIRPN)
	kgx := new(big.Int).Mul(k, gx)
	base := new(big.Int).Sub(bb, kgx)
	base.Mod(base, appleSIRPN)
	if base.Sign() < 0 {
		base.Add(base, appleSIRPN)
	}

	ux := new(big.Int).Mul(u, x)
	exp := new(big.Int).Add(aSecret, ux)
	S := new(big.Int).Exp(base, exp, appleSIRPN)
	SHex := numToEvenHex(S)

	KHex, err := sha256HexFromHex(SHex)
	if err != nil {
		return "", "", err
	}
	MHex, err := srpCalcM(username, saltHex, aHex, bHex, KHex)
	if err != nil {
		return "", "", err
	}
	HAMKHex, err := srpCalcHAMK(aHex, MHex, KHex)
	if err != nil {
		return "", "", err
	}
	return MHex, HAMKHex, nil
}

func numToEvenHex(v *big.Int) string {
	if v == nil {
		return "00"
	}
	hexStr := strings.ToLower(v.Text(16))
	if len(hexStr)%2 == 1 {
		hexStr = "0" + hexStr
	}
	if hexStr == "" {
		hexStr = "00"
	}
	return hexStr
}

func normalizeHex(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	s = strings.TrimPrefix(s, "0x")
	if len(s)%2 == 1 {
		s = "0" + s
	}
	if s == "" {
		return "00"
	}
	return s
}

func hexToBigInt(s string) (*big.Int, error) {
	s = normalizeHex(s)
	v, ok := new(big.Int).SetString(s, 16)
	if !ok {
		return nil, fmt.Errorf("invalid hex integer")
	}
	return v, nil
}

func sha256HexFromHex(hexInput string) (string, error) {
	hexInput = normalizeHex(hexInput)
	b, err := hex.DecodeString(hexInput)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

func sha256HexString(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func srpH(parts ...string) (*big.Int, error) {
	nLen := len(numToEvenHex(appleSIRPN))
	var b strings.Builder
	for _, part := range parts {
		part = normalizeHex(part)
		if len(part) > nLen {
			return nil, fmt.Errorf("srp part width mismatch")
		}
		if len(part) < nLen {
			b.WriteString(strings.Repeat("0", nLen-len(part)))
		}
		b.WriteString(part)
	}
	h, err := sha256HexFromHex(b.String())
	if err != nil {
		return nil, err
	}
	v, ok := new(big.Int).SetString(h, 16)
	if !ok {
		return nil, fmt.Errorf("invalid srp hash output")
	}
	// fastlane-sirp's H(...) applies modulo N.
	// Keep this behavior aligned to avoid proof mismatches on signin/complete.
	v.Mod(v, appleSIRPN)
	return v, nil
}

func srpCalcXHex(encryptedPasswordHex, saltHex string) (*big.Int, error) {
	inner, err := sha256HexFromHex("3a" + normalizeHex(encryptedPasswordHex))
	if err != nil {
		return nil, err
	}
	outer, err := sha256HexFromHex(normalizeHex(saltHex) + inner)
	if err != nil {
		return nil, err
	}
	x, ok := new(big.Int).SetString(outer, 16)
	if !ok {
		return nil, fmt.Errorf("invalid x output")
	}
	return x, nil
}

func srpCalcM(username, saltHex, aHex, bHex, kHex string) (string, error) {
	hN, err := srpH(numToEvenHex(appleSIRPN))
	if err != nil {
		return "", err
	}
	hG, err := srpH(numToEvenHex(appleSIRPG))
	if err != nil {
		return "", err
	}
	hxor := new(big.Int).Xor(hN, hG)
	hxorHex := numToEvenHex(hxor)
	userHex := sha256HexString(username)

	// Keep concatenation semantics aligned with fastlane-sirp:
	// H( H(N) xor H(g), H(I), s, A, B, K )
	return sha256HexFromHex(
		hxorHex +
			userHex +
			normalizeHex(saltHex) +
			normalizeHex(aHex) +
			normalizeHex(bHex) +
			normalizeHex(kHex),
	)
}

func srpCalcHAMK(aHex, mHex, kHex string) (string, error) {
	// H(A, M, K)
	return sha256HexFromHex(
		normalizeHex(aHex) +
			normalizeHex(mHex) +
			normalizeHex(kHex),
	)
}

func sha256Bytes(data []byte) []byte {
	sum := sha256.Sum256(data)
	return sum[:]
}

func hexToBytes(hexInput string) ([]byte, error) {
	hexInput = normalizeHex(hexInput)
	return hex.DecodeString(hexInput)
}

func padBytesLeft(data []byte, size int) []byte {
	if len(data) >= size {
		return data
	}
	padded := make([]byte, size)
	copy(padded[size-len(data):], data)
	return padded
}

func xorBytes(a, b []byte) []byte {
	if len(a) != len(b) {
		return nil
	}
	out := make([]byte, len(a))
	for i := range a {
		out[i] = a[i] ^ b[i]
	}
	return out
}
