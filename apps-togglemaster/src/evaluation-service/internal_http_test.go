package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestInternalRequestsRejectUntrustedDestinationsAndPathInjection(t *testing.T) {
	for _, test := range []struct{ base, resource, flag string }{
		{"http://169.254.169.254", "flags", "checkout"},
		{"http://attacker.example:8002", "flags", "checkout"},
		{"http://flag-service:8002@attacker.example", "flags", "checkout"},
		{"http://flag-service:8002?redirect=external", "flags", "checkout"},
		{"http://flag-service:8002/admin", "flags", "checkout"},
		{"file://flag-service:8002", "flags", "checkout"},
		{"http://targeting-service:8003", "flags", "checkout"},
		{"http://flag-service:8002", "flags", "../admin"},
		{"http://flag-service:8002", "flags", ".."},
		{"http://flag-service:8002", "flags", "checkout?redirect=external"},
		{"http://flag-service:8002", "flags", "%2fadmin"},
	} {
		if _, err := internalServiceRequest(test.base, test.resource, test.flag); err == nil {
			t.Errorf("accepted untrusted request: %+v", test)
		}
	}
}

func TestInternalRequestsPreserveApprovedDestination(t *testing.T) {
	request, err := internalServiceRequest("http://flag-service:8002", "flags", "checkout_v2-test")
	if err != nil {
		t.Fatal(err)
	}
	if request.URL.Host != "flag-service:8002" || request.URL.Path != "/flags/checkout_v2-test" {
		t.Fatalf("unexpected endpoint: %s", request.URL)
	}
	if _, err := internalServiceRequest("http://localhost:8003", "rules", "checkout"); err != nil {
		t.Fatal(err)
	}
}

func TestInternalClientDoesNotFollowRedirects(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://169.254.169.254/latest/meta-data/", http.StatusFound)
	}))
	defer server.Close()
	response, err := internalHTTPClient().Get(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusFound {
		t.Fatalf("redirect was followed: %d", response.StatusCode)
	}
}

func TestEvaluationRejectsInvalidFlagBeforeAccessingDependencies(t *testing.T) {
	app := &App{}
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/evaluate?user_id=test&flag_name=..%2Fadmin", nil)
	app.evaluationHandler(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("got %d", response.Code)
	}
}
