package main

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"strings"
	"testing"
)

func TestProofMatchesIndependentSRPServer(t *testing.T) {
	b, e := os.ReadFile("srp_fixture.json")
	if e != nil {
		t.Fatal(e)
	}
	var f map[string]string
	_ = json.Unmarshal(b, &f)
	a, _ := new(big.Int).SetString(f["a"], 16)
	m1, m2, e := sirpProcessChallenge("fixture@example.invalid", a, f["A"], f["password"], f["salt"], f["B"])
	if e != nil || m1 != f["m1"] || m2 != f["m2"] {
		t.Fatal("SRP proof mismatch")
	}
}

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestRejectedAuthenticationDoesNotClaimDelivery(t *testing.T) {
	c := client{ctx: context.Background(), http: &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 401, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"serviceErrors":[{"code":"-20101","message":"private-content"}]}`))}, nil
	})}}
	_, _, err := c.request("POST", base+"/signin/complete", "password-complete", map[string]string{}, 200, 409)
	failure, ok := err.(rejection)
	if !ok || failure.Status != "failed" || failure.Code != "-20101" || failure.Phase != "password-complete" {
		t.Fatal("incorrect rejection")
	}
	raw, _ := json.Marshal(failure.result)
	if strings.Contains(string(raw), "private-content") {
		t.Fatal("response leaked")
	}
}
func TestSessionHeadersStayInMemory(t *testing.T) {
	c := client{ctx: context.Background(), http: &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Header: http.Header{"Scnt": []string{"fixture-scnt"}, "X-Apple-Id-Session-Id": []string{"fixture-session"}}, Body: io.NopCloser(strings.NewReader(`{}`))}, nil
	})}}
	_, _, err := c.request("GET", base, "options", nil, 200)
	if err != nil || c.scnt != "fixture-scnt" || c.sid != "fixture-session" {
		t.Fatal("missing context")
	}
}

func TestExplicitSMSRequestFollowsAuthenticationAndFactors(t *testing.T) {
	raw, _ := os.ReadFile("srp_fixture.json")
	var fixture map[string]string
	_ = json.Unmarshal(raw, &fixture)
	fromHex := func(s string) string { b, _ := hex.DecodeString(s); return base64.StdEncoding.EncodeToString(b) }
	sent := false
	challenged := false
	c := client{ctx: context.Background(), widget: "fixture-widget", http: &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		status := 200
		body := `{}`
		headers := http.Header{}
		switch r.URL.Path {
		case "/download/os/":
			status = 403
		case "/appleauth/auth/signin/init":
			body = fmt.Sprintf(`{"salt":%q,"b":%q,"c":"fixture","protocol":"s2k","iteration":100}`, fromHex(fixture["salt"]), fromHex(fixture["B"]))
		case "/appleauth/auth/signin/complete":
			if r.Header.Get("X-Apple-Privacy-Consent") != "true" || r.Header.Get("X-Apple-Privacy-Consent-Accepted") != "true" {
				t.Fatal("BetaCat authentication envelope mismatch")
			}
			if r.Header.Get("scnt") != "" || r.Header.Get("X-Apple-ID-Session-Id") != "" {
				t.Fatal("initial session context leaked into SRP completion")
			}
			status = 409
			headers.Set("scnt", "fixture-scnt")
			headers.Set("X-Apple-ID-Session-Id", "fixture-sid")
		case "/appleauth/auth/verify/device/key/challenge":
			challenged = true
		case "/appleauth/auth":
			if !challenged {
				t.Fatal("device challenge missing")
			}
			body = `{"trustedPhoneNumbers":[{"id":47}]}`
		case "/appleauth/auth/verify/phone":
			var p struct {
				Phone struct {
					ID int `json:"id"`
				} `json:"phoneNumber"`
			}
			_ = json.NewDecoder(r.Body).Decode(&p)
			if p.Phone.ID != 47 {
				t.Fatal("did not use Apple phone ID")
			}
			sent = true
		}
		return &http.Response{StatusCode: status, Header: headers, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
	result, err := c.send("fixture@example.invalid", "fixture-password")
	if err != nil || result.Status != "sms_requested" || !sent {
		t.Fatal("SMS request did not complete")
	}
}
