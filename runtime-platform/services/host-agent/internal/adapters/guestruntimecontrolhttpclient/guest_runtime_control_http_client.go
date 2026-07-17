// Package guestruntimecontrolhttpclient adapts the versioned Guest Runtime Control HTTP
// boundary to Host application ports.
package guestruntimecontrolhttpclient

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const maximumResponseBytes int64 = 8 << 20

// GuestRuntimeControlHTTPClient sends Host-owned control requests to the
// configured Guest Runtime Control HTTP endpoint. It owns HTTP transport only;
// Guest lifecycle policy remains in the Host application layer.
type GuestRuntimeControlHTTPClient struct {
	httpClient *http.Client
}

func NewGuestRuntimeControlHTTPClient(httpClient *http.Client) (*GuestRuntimeControlHTTPClient, error) {
	if httpClient == nil {
		return nil, fmt.Errorf("Guest Runtime Control HTTP client is required")
	}
	return &GuestRuntimeControlHTTPClient{httpClient: httpClient}, nil
}

func (client *GuestRuntimeControlHTTPClient) Probe(ctx context.Context, endpoint hostagentdomain.GuestRuntimeControlEndpoint) hostagentapplication.GuestRuntimeControlHTTPProbeResult {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, guestRuntimeControlEndpointURL(endpoint, "/v1/runtime/readiness"), nil)
	if err != nil {
		return hostagentapplication.GuestRuntimeControlHTTPProbeResult{Issue: issue("guest-control-probe-request-invalid", "Host could not build Guest Runtime Control probe request")}
	}
	request.Header.Set("Accept", "application/json")
	response, err := client.httpClient.Do(request)
	if err != nil {
		return hostagentapplication.GuestRuntimeControlHTTPProbeResult{Issue: issue("guest-control-probe-unavailable", "Host could not reach the configured Guest Runtime Control endpoint")}
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, maximumResponseBytes))
	return hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true}
}

func (client *GuestRuntimeControlHTTPClient) Forward(ctx context.Context, endpoint hostagentdomain.GuestRuntimeControlEndpoint, method string, path string, body []byte, contentType string) (hostagentapplication.GuestRuntimeControlHTTPForwardedResponse, *hostagentapplication.GuestRuntimeControlHTTPForwardingFailure) {
	request, err := http.NewRequestWithContext(ctx, method, guestRuntimeControlEndpointURL(endpoint, path), bytes.NewReader(body))
	if err != nil {
		return hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{}, &hostagentapplication.GuestRuntimeControlHTTPForwardingFailure{Issue: issue("guest-control-forward-request-invalid", "Host could not build Guest Runtime Control request")}
	}
	request.Header.Set("Accept", "application/json")
	if contentType != "" {
		request.Header.Set("Content-Type", contentType)
	}
	response, err := client.httpClient.Do(request)
	if err != nil {
		return hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{}, &hostagentapplication.GuestRuntimeControlHTTPForwardingFailure{Issue: issue("guest-control-forward-failed", "Host did not receive a Guest Runtime Control response")}
	}
	defer response.Body.Close()
	encoded, err := io.ReadAll(io.LimitReader(response.Body, maximumResponseBytes+1))
	if err != nil {
		return hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{}, &hostagentapplication.GuestRuntimeControlHTTPForwardingFailure{Issue: issue("guest-control-response-read-failed", "Host could not read Guest Runtime Control response")}
	}
	if len(encoded) > int(maximumResponseBytes) {
		return hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{}, &hostagentapplication.GuestRuntimeControlHTTPForwardingFailure{Issue: issue("guest-control-response-too-large", "Guest Runtime Control response exceeded the configured Host forwarding limit")}
	}
	return hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{StatusCode: response.StatusCode, ContentType: response.Header.Get("Content-Type"), Body: encoded}, nil
}

func guestRuntimeControlEndpointURL(endpoint hostagentdomain.GuestRuntimeControlEndpoint, path string) string {
	return (&url.URL{
		Scheme: endpoint.Address.Scheme,
		Host:   net.JoinHostPort(endpoint.Address.Host, fmt.Sprintf("%d", endpoint.Address.Port)),
		Path:   path,
	}).String()
}

func issue(code string, message string) *hostagentdomain.Issue {
	return &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(true), Dependency: "guest-runtime-control-http"}
}
