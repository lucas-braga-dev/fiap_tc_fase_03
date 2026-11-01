package main

import (
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"time"
)

var validFlagName = regexp.MustCompile(`^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}$`)

func internalServiceRequest(base, resource, flag string) (*http.Request, error) {
	if !validFlagName.MatchString(flag) {
		return nil, fmt.Errorf("invalid flag name")
	}
	endpoint, err := url.Parse(base)
	if err != nil || (endpoint.Scheme != "http" && endpoint.Scheme != "https") {
		return nil, fmt.Errorf("invalid internal service URL")
	}
	if endpoint.User != nil || endpoint.RawQuery != "" || endpoint.Fragment != "" || (endpoint.Path != "" && endpoint.Path != "/") {
		return nil, fmt.Errorf("internal service URL must contain only scheme and host")
	}
	// The destination is configuration, but is still restricted to known services.
	allowed := map[string]map[string]bool{
		"flags": {
			"flag-service:8002": true,
			"flag-service.togglemaster.svc.cluster.local:8002": true,
			"localhost:8002": true,
			"127.0.0.1:8002": true,
		},
		"rules": {
			"targeting-service:8003":                                true,
			"targeting-service.togglemaster.svc.cluster.local:8003": true,
			"localhost:8003":                                        true,
			"127.0.0.1:8003":                                        true,
		},
	}
	if !allowed[resource][endpoint.Host] {
		return nil, fmt.Errorf("destination is not an approved internal service")
	}
	endpoint.Path = "/" + resource + "/" + flag
	// #nosec G704 -- Exact host/port allowlist and a single validated flag segment above; no arbitrary URL is accepted.
	return http.NewRequest(http.MethodGet, endpoint.String(), nil)
}

func internalHTTPClient() *http.Client {
	return &http.Client{
		Timeout: 5 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			// An internal service cannot redirect the API key to another destination.
			return http.ErrUseLastResponse
		},
	}
}
