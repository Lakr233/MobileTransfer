// Local Apple authentication challenge request, modeled on BetaCat's local SMS flow.
// Credentials arrive through stdin; no account data, response bodies or session headers are logged.
package main

import (
	"context"
	"crypto/sha1"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const base = "https://idmsa.apple.com/appleauth/auth"
const loginURL = "https://idmsa.apple.com/signin?language=US-EN&rv=1&path=%2Fdownload%2Fos%2F&appIdKey=891bd3417a7776362562d2197f89480a8547b108fd934911bcbea0110d07f757"
const ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15"

type result struct {
	Status string `json:"status"`
	Phase  string `json:"phase"`
	HTTP   int    `json:"httpStatus,omitempty"`
	Code   string `json:"failureType,omitempty"`
}
type rejection struct{ result }

func (e rejection) Error() string { return e.Phase }

type client struct {
	http              *http.Client
	ctx               context.Context
	widget, scnt, sid string
	hashcash          string
}

func (c *client) request(method, url, phase string, payload any, allowed ...int) ([]byte, int, error) {
	var body io.Reader
	if payload != nil {
		b, e := json.Marshal(payload)
		if e != nil {
			return nil, 0, e
		}
		body = strings.NewReader(string(b))
	}
	req, e := http.NewRequestWithContext(c.ctx, method, url, body)
	if e != nil {
		return nil, 0, e
	}
	req.Header.Set("User-Agent", ua)
	req.Header.Set("Accept", "application/json, text/javascript")
	req.Header.Set("Origin", "https://idmsa.apple.com")
	req.Header.Set("Referer", loginURL)
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	if c.hashcash != "" && phase == "password-complete" {
		req.Header.Set("X-Apple-HC", c.hashcash)
	}
	req.Header.Set("X-Apple-Widget-Key", c.widget)
	req.Header.Set("X-Apple-Trusted-Domain", "https://idmsa.apple.com")
	req.Header.Set("X-Apple-Locale", "CN-ZH")
	req.Header.Set("X-Apple-App-Id", "632")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	if c.scnt != "" && !strings.HasPrefix(phase, "password-") && phase != "proof-of-work" {
		req.Header.Set("scnt", c.scnt)
	}
	if c.sid != "" && !strings.HasPrefix(phase, "password-") && phase != "proof-of-work" {
		req.Header.Set("X-Apple-ID-Session-Id", c.sid)
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, e := c.http.Do(req)
	if e != nil {
		return nil, 0, rejection{result{Status: "failed", Phase: phase}}
	}
	defer resp.Body.Close()
	if bits := resp.Header.Get("X-Apple-HC-Bits"); bits != "" {
		c.hashcash = solveHashcash(c.ctx, bits, resp.Header.Get("X-Apple-HC-Challenge"))
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024+1))
	if e != nil || len(b) > 2*1024*1024 {
		return nil, 0, rejection{result{Status: "failed", Phase: phase}}
	}
	if v := resp.Header.Get("scnt"); v != "" {
		c.scnt = v
	}
	if v := resp.Header.Get("X-Apple-ID-Session-Id"); v != "" {
		c.sid = v
	}
	for _, a := range allowed {
		if resp.StatusCode == a {
			return b, a, nil
		}
	}
	code := ""
	var data struct {
		Errors []struct {
			Code string `json:"code"`
		} `json:"serviceErrors"`
	}
	_ = json.Unmarshal(b, &data)
	if len(data.Errors) > 0 && regexp.MustCompile(`^-?[0-9]{1,10}$`).MatchString(data.Errors[0].Code) {
		code = data.Errors[0].Code
	}
	return nil, resp.StatusCode, rejection{result{Status: "failed", Phase: phase, HTTP: resp.StatusCode, Code: code}}
}
func (c *client) send(email, password string) (result, error) {

	transport := c.http.Transport
	if transport == nil {
		transport = http.DefaultTransport
	}
	c.http.Transport = deadlineTransport{ctx: c.ctx, next: transport}
	authCtx := fetchAppleAuthContext(c.http)
	seed, _ := http.NewRequestWithContext(c.ctx, "GET", authCtx.LoginPageURL, nil)
	seed.Header.Set("User-Agent", ua)
	if resp, err := c.http.Do(seed); err == nil {
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
	}
	signin, e := betaSignIn(c.http, authCtx, email, password)
	if e != nil {
		text := e.Error()
		status := 0
		code := ""
		phase := "password-complete"
		if strings.Contains(text, "signin init") {
			phase = "password-init"
		}
		if m := regexp.MustCompile(`status=([0-9]{3})`).FindStringSubmatch(text); len(m) > 1 {
			status, _ = strconv.Atoi(m[1])
		}
		if strings.Contains(text, "-20101") {
			code = "-20101"
		}
		return result{}, rejection{result{Status: "failed", Phase: phase, HTTP: status, Code: code}}
	}
	c.widget = signin.WidgetKey
	c.scnt = signin.Scnt
	c.sid = signin.SessionID
	if !signin.Need2FA {
		return result{Status: "no_challenge", Phase: "password-accepted"}, nil
	}
	if c.scnt == "" || c.sid == "" {
		return result{}, rejection{result{Status: "failed", Phase: "missing-session"}}
	}
	// BetaCat explicitly aligns the device challenge before requesting SMS factors.
	_, _, _ = c.request("POST", base+"/verify/device/key/challenge", "device-challenge", map[string]any{"passkeyAutofill": false}, 200, 204, 202, 409)
	var phone any
	for _, path := range []string{"", "/factors"} {
		raw, _, err := c.request("GET", base+path, "challenge-options", nil, 200, 201, 202, 409, 423)
		if err != nil {
			continue
		}
		var options map[string]any
		if json.Unmarshal(raw, &options) != nil {
			continue
		}
		list, _ := options["trustedPhoneNumbers"].([]any)
		if len(list) == 0 {
			if nested, ok := options["phoneNumberVerification"].(map[string]any); ok {
				list, _ = nested["trustedPhoneNumbers"].([]any)
				if p, ok := nested["trustedPhoneNumber"].(map[string]any); ok {
					list = []any{p}
				}
			}
		}
		if len(list) > 0 {
			if p, ok := list[0].(map[string]any); ok {
				phone = p["id"]
			}
		}
		if phone != nil {
			break
		}
	}
	if phone == nil {
		return result{Status: "failed", Phase: "no-sms-number"}, nil
	}
	_, _, e = c.request("PUT", base+"/verify/phone", "send-sms", map[string]any{"phoneNumber": map[string]any{"id": phone}, "mode": "sms"}, 200, 204, 202)
	if e != nil {
		return result{}, e
	}
	return result{Status: "sms_requested", Phase: "send-sms"}, nil
}
func main() {
	if len(os.Args) > 1 && os.Args[1] == "--preflight" {
		ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
		defer cancel()
		jar, _ := cookiejar.New(nil)
		c := client{ctx: ctx, widget: "92f19b477c5c9be6ab17f3ec2b1b2b7db4d00a9a8c973e3d6c90dac08b91de71", http: &http.Client{Jar: jar, Timeout: 25 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
		_, status, e := c.request("GET", loginURL, "session", nil, 200)
		r := result{Status: "ready", Phase: "session", HTTP: status}
		if e != nil {
			if v, ok := e.(rejection); ok {
				r = v.result
			} else {
				r = result{Status: "failed", Phase: "session"}
			}
		}
		_ = json.NewEncoder(os.Stdout).Encode(r)
		return
	}
	var input struct{ Email, Password string }
	if json.NewDecoder(io.LimitReader(os.Stdin, 65536)).Decode(&input) != nil || input.Email == "" || input.Password == "" {
		_ = json.NewEncoder(os.Stdout).Encode(result{Status: "failed", Phase: "input"})
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 75*time.Second)
	defer cancel()
	jar, _ := cookiejar.New(nil)
	c := client{http: &http.Client{Jar: jar, Timeout: 25 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, ctx: ctx, widget: "92f19b477c5c9be6ab17f3ec2b1b2b7db4d00a9a8c973e3d6c90dac08b91de71"}
	r, e := c.send(input.Email, input.Password)
	if e != nil {
		if v, ok := e.(rejection); ok {
			r = v.result
		} else {
			r = result{Status: "failed", Phase: "local-authentication"}
		}
	}
	_ = json.NewEncoder(os.Stdout).Encode(r)
}

// Apple browser authentication proof-of-work; never handles CAPTCHA challenges.
func solveHashcash(ctx context.Context, rawBits, challenge string) string {
	bits, e := strconv.Atoi(rawBits)
	if e != nil || bits < 1 || bits > 24 || challenge == "" || len(challenge) > 4096 {
		return ""
	}
	deadline := time.Now().Add(8 * time.Second)
	stampDate := time.Now().UTC().Format("20060102150405")
	for counter := 0; time.Now().Before(deadline); counter++ {
		if counter%1024 == 0 {
			select {
			case <-ctx.Done():
				return ""
			default:
			}
		}
		stamp := fmt.Sprintf("1:%d:%s:%s::%d", bits, stampDate, challenge, counter)
		hash := sha1.Sum([]byte(stamp))
		valid := true
		for i := 0; i < bits; i++ {
			if hash[i/8]&(0x80>>uint(i%8)) != 0 {
				valid = false
				break
			}
		}
		if valid {
			return stamp
		}
	}
	return ""
}

type deadlineTransport struct {
	ctx  context.Context
	next http.RoundTripper
}

func (t deadlineTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	return t.next.RoundTrip(r.WithContext(t.ctx))
}
