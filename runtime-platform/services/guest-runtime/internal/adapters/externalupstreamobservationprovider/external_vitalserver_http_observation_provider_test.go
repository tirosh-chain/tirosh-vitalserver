package externalupstreamobservationprovider

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestExternalVitalServerHTTPObservationProviderUsesOnlyDeclaredEndpointAndStatus(t *testing.T) {
	server := newExternalVitalServerObservationTestServer(t, http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet || request.URL.Path != "/operator-approved-status" {
			t.Fatalf("observation request = %s %s", request.Method, request.URL.Path)
		}
		response.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	configurationPath := writeExternalVitalServerObservationConfiguration(t, server.URL, "/operator-approved-status", []int{204})
	reference := guestruntimedomain.IntegrationProviderReference{Kind: "external-vitalserver-http", ID: "external-vitalserver-primary", CapabilityRevision: 1}
	provider, err := NewExternalVitalServerHTTPObservationProviderFromFile(reference, configurationPath, time.Second)
	if err != nil {
		t.Fatalf("open provider: %v", err)
	}
	observation, err := provider.ObserveExternalUpstream(context.Background(), "external-vitalserver-primary", guestruntimedomain.ExternalUpstreamSpec{Provider: reference, EndpointReference: guestruntimedomain.ResourceReference{ResourceType: "external-vitalserver-delivery-configuration", ResourceID: "external-vitalserver-primary-delivery"}}, "2026-07-20T00:00:00Z")
	if err != nil || observation.State != "available" || observation.Connection.State != "reachable" || observation.Capability == nil {
		t.Fatalf("observation = %+v error=%v", observation, err)
	}
}

func TestExternalVitalServerHTTPObservationProviderPreservesUnacceptedResponseAsUnavailable(t *testing.T) {
	server := newExternalVitalServerObservationTestServer(t, http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()
	configurationPath := writeExternalVitalServerObservationConfiguration(t, server.URL, "/healthz", []int{200})
	reference := guestruntimedomain.IntegrationProviderReference{Kind: "external-vitalserver-http", ID: "external-vitalserver-primary", CapabilityRevision: 1}
	provider, err := NewExternalVitalServerHTTPObservationProviderFromFile(reference, configurationPath, time.Second)
	if err != nil {
		t.Fatalf("open provider: %v", err)
	}
	observation, err := provider.ObserveExternalUpstream(context.Background(), "external-vitalserver-primary", guestruntimedomain.ExternalUpstreamSpec{Provider: reference, EndpointReference: guestruntimedomain.ResourceReference{ResourceType: "external-vitalserver-delivery-configuration", ResourceID: "external-vitalserver-primary-delivery"}}, "2026-07-20T00:00:00Z")
	if err != nil || observation.State != "unavailable" || observation.Connection.State != "unavailable" || observation.Issue == nil || observation.Issue.Code != "external-vitalserver-observation-status-unaccepted" {
		t.Fatalf("observation = %+v error=%v", observation, err)
	}
}

func TestExternalVitalServerHTTPObservationProviderRejectsMissingOrMismatchedC46(t *testing.T) {
	reference := guestruntimedomain.IntegrationProviderReference{Kind: "external-vitalserver-http", ID: "external-vitalserver-primary", CapabilityRevision: 1}
	if _, err := NewExternalVitalServerHTTPObservationProviderFromFile(reference, filepath.Join(t.TempDir(), "missing.json"), time.Second); err == nil {
		t.Fatal("missing C46 configuration configured an External VitalServer observation provider")
	}
	server := newExternalVitalServerObservationTestServer(t, http.NotFoundHandler())
	defer server.Close()
	configurationPath := writeExternalVitalServerObservationConfiguration(t, server.URL, "/healthz", []int{200})
	mismatched := guestruntimedomain.IntegrationProviderReference{Kind: "external-vitalserver-http", ID: "other-vitalserver", CapabilityRevision: 1}
	if _, err := NewExternalVitalServerHTTPObservationProviderFromFile(mismatched, configurationPath, time.Second); err == nil {
		t.Fatal("mismatched C46 configuration configured an External VitalServer observation provider")
	}
}

func newExternalVitalServerObservationTestServer(t *testing.T, handler http.Handler) *httptest.Server {
	t.Helper()
	listener, err := net.Listen("tcp4", "0.0.0.0:0")
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewUnstartedServer(handler)
	server.Listener = listener
	server.Start()
	return server
}

func writeExternalVitalServerObservationConfiguration(t *testing.T, serverURL string, observationPath string, acceptedStatusCodes []int) string {
	t.Helper()
	parsed, err := url.Parse(serverURL)
	if err != nil {
		t.Fatal(err)
	}
	host, portText, err := net.SplitHostPort(parsed.Host)
	if err != nil {
		t.Fatal(err)
	}
	var port int
	if _, err := fmt.Sscanf(portText, "%d", &port); err != nil {
		t.Fatal(err)
	}
	configuration := fmt.Sprintf(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary-delivery","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"http","host":%q,"port":%d},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"http","host":%q,"port":%d,"path":%q,"acceptedStatusCodes":%s},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"external-vitalserver-primary-library","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"http","host":%q,"port":%d},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"external-vitalserver-primary-library"},"vitalServerArchiveRequestTimeoutMilliseconds":1000}`,
		host, port, host, port, observationPath, statusCodesJSON(t, acceptedStatusCodes), host, port)
	path := filepath.Join(t.TempDir(), "external-vitalserver-delivery.json")
	if err := os.WriteFile(path, []byte(configuration), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func statusCodesJSON(t *testing.T, statusCodes []int) string {
	t.Helper()
	if len(statusCodes) == 1 {
		return fmt.Sprintf("[%d]", statusCodes[0])
	}
	t.Fatal("test helper only supports one status code")
	return ""
}
