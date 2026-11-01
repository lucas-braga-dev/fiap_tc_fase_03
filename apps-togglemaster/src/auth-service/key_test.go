package main

import (
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGeneratedKeysAreUniqueAndWellFormed(t *testing.T) {
	seen := make(map[string]bool)
	for i := 0; i < 100; i++ {
		key, err := generateAPIKey()
		if err != nil {
			t.Fatal(err)
		}
		if !strings.HasPrefix(key, "tm_key_") {
			t.Fatal("missing key prefix")
		}
		raw, err := hex.DecodeString(strings.TrimPrefix(key, "tm_key_"))
		if err != nil || len(raw) != 32 {
			t.Fatal("key must contain 256 random bits")
		}
		if seen[key] {
			t.Fatal("duplicate API key")
		}
		seen[key] = true
	}
}

func TestHashAPIKey(t *testing.T) {
	const expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	if got := hashAPIKey("abc"); got != expected {
		t.Fatalf("unexpected hash: %s", got)
	}
}

func TestMasterKeyRejectsMissingOrWrongCredentials(t *testing.T) {
	app := &App{MasterKey: "expected-master"}
	handler := app.masterKeyAuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	for _, test := range []struct {
		header string
		status int
	}{
		{"", http.StatusForbidden},
		{"Bearer wrong", http.StatusForbidden},
		{"Bearer expected-master", http.StatusNoContent},
	} {
		req := httptest.NewRequest(http.MethodPost, "/admin/keys", nil)
		req.Header.Set("Authorization", test.header)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, req)
		if response.Code != test.status {
			t.Fatalf("header %q: got %d", test.header, response.Code)
		}
	}
}
