package main

import (
	"context"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"crypto/pbkdf2"
)

const appleDefaultRefererURL = "https://developer.apple.com/download/os/"

type appleAuthContext struct {
	WidgetKey    string
	LoginPageURL string
	Referer      string
}

var (
	appleAuthWidgetRe = regexp.MustCompile(`"authWidgetConfig"\s*:\s*\{[^}]*"widgetKey"\s*:\s*"([^"]+)"`)
	appleSignInReqRe  = regexp.MustCompile(`"signInRequestUrl"\s*:\s*"([^"]+)"`)
)

func defaultAppleAuthContext() appleAuthContext {
	return appleAuthContext{
		WidgetKey:    appleDefaultWidgetKey,
		LoginPageURL: appleLoginPageURL,
		Referer:      appleDefaultRefererURL,
	}
}

func fetchAppleAuthContext(client *http.Client) appleAuthContext {
	ctx := defaultAppleAuthContext()
	if client == nil {
		return ctx
	}

	req, err := http.NewRequest("GET", appleDefaultRefererURL, nil)
	if err != nil {
		return ctx
	}
	req.Header.Set("User-Agent", appleUA())
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")

	resp, err := client.Do(req)
	if err != nil {
		return ctx
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK || len(body) == 0 {
		return ctx
	}

	raw := string(body)
	if m := appleAuthWidgetRe.FindStringSubmatch(raw); len(m) > 1 {
		if k := strings.TrimSpace(m[1]); k != "" {
			ctx.WidgetKey = k
		}
	}

	if m := appleSignInReqRe.FindStringSubmatch(raw); len(m) > 1 {
		signInURL := decodeAppleEscapedURL(m[1])
		if signInURL != "" {
			ctx.LoginPageURL = signInURL
		}
	}

	return ctx
}

func decodeAppleEscapedURL(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	if unquoted, err := strconv.Unquote(`"` + s + `"`); err == nil && strings.TrimSpace(unquoted) != "" {
		s = unquoted
	}
	if decoded, err := url.QueryUnescape(s); err == nil && strings.TrimSpace(decoded) != "" {
		s = decoded
	}
	return s
}

func snippetBody(body []byte, limit int) string {
	s := strings.TrimSpace(string(body))
	if limit <= 0 {
		limit = 200
	}
	if len(s) > limit {
		s = s[:limit]
	}
	return s
}

func fetchAppleHashcash(client *http.Client, widgetKey string) string {
	widgetKey = strings.TrimSpace(widgetKey)
	if client == nil || widgetKey == "" {
		return ""
	}
	endpoint := "https://idmsa.apple.com/appleauth/auth/signin?widgetKey=" + url.QueryEscape(widgetKey)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return ""
	}
	req.Header.Set("User-Agent", appleUA())
	req.Header.Set("Accept", "application/json, text/javascript")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")

	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()

	bits := strings.TrimSpace(resp.Header.Get("X-Apple-HC-Bits"))
	challenge := strings.TrimSpace(resp.Header.Get("X-Apple-HC-Challenge"))
	if bits == "" || challenge == "" {
		return ""
	}
	return solveHashcash(context.Background(), bits, challenge)
}

func setAppleBrowserLikeHeaders(req *http.Request, authCtx appleAuthContext) {
	if req == nil {
		return
	}
	req.Header.Set("X-Apple-Trusted-Domain", "https://idmsa.apple.com")
	req.Header.Set("X-Apple-Locale", "CN-ZH")
	req.Header.Set("X-Apple-App-Id", "632")
	req.Header.Set("X-Apple-Privacy-Consent", "true")
	req.Header.Set("X-Apple-Privacy-Consent-Accepted", "true")
	if strings.TrimSpace(authCtx.WidgetKey) != "" {
		req.Header.Set("X-Apple-Widget-Key", authCtx.WidgetKey)
	}
	if strings.TrimSpace(authCtx.LoginPageURL) != "" {
		req.Header.Set("Referer", authCtx.LoginPageURL)
	}
}

func appleAuthFederate(client *http.Client, authCtx appleAuthContext, accountName, scnt, sessionID string) error {
	if client == nil {
		return fmt.Errorf("nil http client")
	}
	scnt = strings.TrimSpace(scnt)
	sessionID = strings.TrimSpace(sessionID)
	if scnt == "" || sessionID == "" {
		return fmt.Errorf("missing scnt/session id")
	}

	payload := map[string]any{
		"accountName": accountName,
		"rememberMe":  true,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST",
		"https://idmsa.apple.com/appleauth/auth/federate?isRememberMeEnabled=true",
		strings.NewReader(string(body)))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json, text/javascript, */*; q=0.01")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	req.Header.Set("Origin", "https://idmsa.apple.com")
	req.Header.Set("User-Agent", appleUA())
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	req.Header.Set("scnt", scnt)
	req.Header.Set("X-Apple-ID-Session-Id", sessionID)
	setAppleBrowserLikeHeaders(req, authCtx)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusNoContent {
		return nil
	}
	bodyBytes, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("sirp federate failed (status=%d, ct=%s, body=%s)",
		resp.StatusCode, strings.TrimSpace(resp.Header.Get("Content-Type")), snippetBody(bodyBytes, 200))
}

func originalBetaHashcash(bitsStr, challenge string) (string, error) {
	bits, err := strconv.Atoi(strings.TrimSpace(bitsStr))
	if err != nil || bits <= 0 {
		return "", fmt.Errorf("invalid hashcash bits: %s", bitsStr)
	}
	challenge = strings.TrimSpace(challenge)
	if challenge == "" {
		return "", fmt.Errorf("empty hashcash challenge")
	}

	date := time.Now().Format("20060102150405")
	for counter := 0; counter < 1_000_000_000; counter++ {
		stamp := fmt.Sprintf("1:%d:%s:%s::%d", bits, date, challenge, counter)
		sum := sha1.Sum([]byte(stamp))
		if hasLeadingZeroBits(sum[:], bits) {
			return stamp, nil
		}
	}
	return "", fmt.Errorf("hashcash solve timeout")
}

func hasLeadingZeroBits(data []byte, bits int) bool {
	if bits <= 0 {
		return true
	}
	fullBytes := bits / 8
	remBits := bits % 8
	if fullBytes > len(data) {
		return false
	}
	for i := 0; i < fullBytes; i++ {
		if data[i] != 0 {
			return false
		}
	}
	if remBits == 0 {
		return true
	}
	if fullBytes >= len(data) {
		return false
	}
	mask := byte(0xFF << (8 - remBits))
	return data[fullBytes]&mask == 0
}

func betaSignIn(client *http.Client, authCtx appleAuthContext, email, password string) (appleSigninResult, error) {
	if client == nil {
		return appleSigninResult{}, fmt.Errorf("nil http client")
	}
	if strings.TrimSpace(authCtx.WidgetKey) == "" || strings.TrimSpace(authCtx.LoginPageURL) == "" {
		authCtx = fetchAppleAuthContext(client)
	}

	srpASecret, srpAHex, err := sirpStartAuthentication()
	if err != nil {
		return appleSigninResult{}, err
	}
	aBytes, err := hex.DecodeString(srpAHex)
	if err != nil {
		return appleSigninResult{}, err
	}

	accountName := appleNormalizeAccountName(email)
	initPayload := map[string]any{
		"a":           base64.StdEncoding.EncodeToString(aBytes),
		"accountName": accountName,
		"protocols":   []string{"s2k", "s2k_fo"},
	}
	initBody, _ := json.Marshal(initPayload)
	initReq, err := http.NewRequest("POST", "https://idmsa.apple.com/appleauth/auth/signin/init", strings.NewReader(string(initBody)))
	if err != nil {
		return appleSigninResult{}, err
	}
	initReq.Header.Set("Content-Type", "application/json")
	initReq.Header.Set("Accept", "application/json, text/javascript")
	initReq.Header.Set("X-Requested-With", "XMLHttpRequest")
	initReq.Header.Set("Origin", "https://idmsa.apple.com")
	initReq.Header.Set("User-Agent", appleUA())
	initReq.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	setAppleBrowserLikeHeaders(initReq, authCtx)

	initResp, err := client.Do(initReq)
	if err != nil {
		return appleSigninResult{}, err
	}
	initScnt := strings.TrimSpace(initResp.Header.Get("scnt"))
	initSID := strings.TrimSpace(initResp.Header.Get("X-Apple-ID-Session-Id"))
	initRespBody, _ := io.ReadAll(initResp.Body)
	_ = initResp.Body.Close()
	if initResp.StatusCode != http.StatusOK {
		return appleSigninResult{}, fmt.Errorf("sirp signin init failed (status=%d, ct=%s, body=%s)",
			initResp.StatusCode, strings.TrimSpace(initResp.Header.Get("Content-Type")), snippetBody(initRespBody, 300))
	}

	var initJSON struct {
		Iteration    int    `json:"iteration"`
		Salt         string `json:"salt"`
		Protocol     string `json:"protocol"`
		B            string `json:"b"`
		C            string `json:"c"`
		ServiceError any    `json:"serviceErrors"`
	}
	if err := json.Unmarshal(initRespBody, &initJSON); err != nil {
		return appleSigninResult{}, fmt.Errorf("sirp signin init invalid json: %v", err)
	}
	if initJSON.ServiceError != nil {
		return appleSigninResult{}, fmt.Errorf("sirp signin init serviceErrors=%v", initJSON.ServiceError)
	}
	if (initJSON.Iteration <= 0 || initJSON.Iteration > 1000000) || initJSON.Salt == "" || initJSON.B == "" || initJSON.C == "" {
		return appleSigninResult{}, fmt.Errorf("sirp signin init missing fields (iteration=%d, salt=%t, b=%t, c=%t)",
			initJSON.Iteration, initJSON.Salt != "", initJSON.B != "", initJSON.C != "")
	}
	// Keep sign-in sequence stable for our SMS flow. Browser calls `federate`,
	// but in backend mode this may produce a session variant rejected by factors API.
	_ = initScnt
	_ = initSID

	saltRaw, err := base64.StdEncoding.DecodeString(initJSON.Salt)
	if err != nil {
		return appleSigninResult{}, fmt.Errorf("sirp salt decode failed: %v", err)
	}
	bRaw, err := base64.StdEncoding.DecodeString(initJSON.B)
	if err != nil {
		return appleSigninResult{}, fmt.Errorf("sirp b decode failed: %v", err)
	}

	encryptedPassword := applePBKDF2Password(password, saltRaw, initJSON.Iteration, initJSON.Protocol)
	m1Hex, m2Hex, err := sirpProcessChallenge(
		accountName,
		srpASecret,
		srpAHex,
		hex.EncodeToString(encryptedPassword),
		hex.EncodeToString(saltRaw),
		hex.EncodeToString(bRaw),
	)
	if err != nil {
		return appleSigninResult{}, fmt.Errorf("sirp challenge failed: %v", err)
	}

	m1Bytes, err := hex.DecodeString(m1Hex)
	if err != nil {
		return appleSigninResult{}, fmt.Errorf("sirp m1 decode failed: %v", err)
	}
	m2Bytes, err := hex.DecodeString(m2Hex)
	if err != nil {
		return appleSigninResult{}, fmt.Errorf("sirp m2 decode failed: %v", err)
	}

	completePayload := map[string]any{
		"accountName": accountName,
		"c":           initJSON.C,
		"m1":          base64.StdEncoding.EncodeToString(m1Bytes),
		"m2":          base64.StdEncoding.EncodeToString(m2Bytes),
		// Align with browser flow to increase chance of longer-lived trusted session.
		"rememberMe": true,
	}
	completeBody, _ := json.Marshal(completePayload)
	completeReq, err := http.NewRequest("POST", "https://idmsa.apple.com/appleauth/auth/signin/complete?isRememberMeEnabled=true", strings.NewReader(string(completeBody)))
	if err != nil {
		return appleSigninResult{}, err
	}
	completeReq.Header.Set("Content-Type", "application/json")
	completeReq.Header.Set("Accept", "application/json, text/javascript")
	completeReq.Header.Set("X-Requested-With", "XMLHttpRequest")
	completeReq.Header.Set("Origin", "https://idmsa.apple.com")
	completeReq.Header.Set("User-Agent", appleUA())
	completeReq.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	setAppleBrowserLikeHeaders(completeReq, authCtx)
	if hc := fetchAppleHashcash(client, authCtx.WidgetKey); hc != "" {
		completeReq.Header.Set("X-Apple-HC", hc)
	}

	completeResp, err := client.Do(completeReq)
	if err != nil {
		return appleSigninResult{}, err
	}
	completeRespBody, _ := io.ReadAll(completeResp.Body)
	_ = completeResp.Body.Close()

	scnt := strings.TrimSpace(completeResp.Header.Get("scnt"))
	sid := strings.TrimSpace(completeResp.Header.Get("X-Apple-ID-Session-Id"))
	if completeResp.StatusCode != http.StatusOK && completeResp.StatusCode != http.StatusConflict {
		return appleSigninResult{}, fmt.Errorf(
			"sirp signin complete failed (status=%d, ct=%s, scnt=%t, sid=%t, body=%s)",
			completeResp.StatusCode,
			strings.TrimSpace(completeResp.Header.Get("Content-Type")),
			scnt != "",
			sid != "",
			snippetBody(completeRespBody, 300),
		)
	}

	need2FA := completeResp.StatusCode == http.StatusConflict
	if completeResp.StatusCode == http.StatusOK && scnt != "" && sid != "" {
		need2FA = true
	}
	if need2FA && (scnt == "" || sid == "") {
		return appleSigninResult{}, fmt.Errorf(
			"sirp signin complete missing headers (status=%d, scnt=%t, sid=%t, body=%s)",
			completeResp.StatusCode, scnt != "", sid != "", snippetBody(completeRespBody, 200),
		)
	}

	return appleSigninResult{
		Scnt:         scnt,
		SessionID:    sid,
		Need2FA:      need2FA,
		CookieOnly:   !need2FA,
		WidgetKey:    authCtx.WidgetKey,
		LoginPageURL: authCtx.LoginPageURL,
	}, nil
}

func applePBKDF2Password(password string, salt []byte, iterations int, protocol string) []byte {
	keyLength := 32
	raw := sha256.Sum256([]byte(password))
	passwordBytes := raw[:]
	if strings.TrimSpace(protocol) == "s2k_fo" {
		passwordBytes = []byte(hex.EncodeToString(passwordBytes))
	}
	result, _ := pbkdf2.Key(sha256.New, string(passwordBytes), salt, iterations, keyLength)
	return result
}

const appleDeveloperAppIDKey = "891bd3417a7776362562d2197f89480a8547b108fd934911bcbea0110d07f757"
const appleDefaultWidgetKey = "92f19b477c5c9be6ab17f3ec2b1b2b7db4d00a9a8c973e3d6c90dac08b91de71"
const appleLoginPageURL = loginURL

func appleNormalizeAccountName(s string) string { return strings.TrimSpace(s) }
func appleUA() string                           { return ua }

type appleSigninResult struct {
	Scnt, SessionID, WidgetKey, LoginPageURL string
	Need2FA, CookieOnly                      bool
}
