package platformctlcontrolclient_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/platformctl/internal/platformctlcontrolclient"
)

func TestParseLocalControlEndpointRejectsNonLoopbackAndAmbiguousAddresses(t *testing.T) {
	for _, address := range []string{
		"https://127.0.0.1:18280",
		"http://localhost:18280",
		"http://127.0.0.2:18280",
		"http://192.0.2.10:18280",
		"http://operator@127.0.0.1:18280",
		"http://127.0.0.1:18280/v1/platform/installation",
		"http://127.0.0.1:18280?unexpected=true",
	} {
		t.Run(address, func(t *testing.T) {
			_, err := platformctlcontrolclient.ParseLocalControlEndpoint(address)
			if err == nil {
				t.Fatalf("ParseLocalControlEndpoint(%q) error = nil, want rejection", address)
			}
		})
	}
}

func TestClientDoesNotFollowAControlRedirectToAnotherAddress(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Location", "http://192.0.2.200:18280/v1/platform/installation")
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusFound)
		_, _ = writer.Write([]byte(`{"error":"redirect is not a control response"}`))
	}))
	defer server.Close()

	endpoint, err := platformctlcontrolclient.ParseLocalControlEndpoint(server.URL)
	if err != nil {
		t.Fatalf("ParseLocalControlEndpoint() error = %v", err)
	}
	client, err := platformctlcontrolclient.NewClient(server.Client())
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	response, err := client.Execute(context.Background(), endpoint, http.MethodGet, "/v1/platform/installation", nil)
	var statusError *platformctlcontrolclient.ResponseStatusError
	if !errors.As(err, &statusError) || statusError.Status != http.StatusFound {
		t.Fatalf("Execute() error = %v, want redirect status error", err)
	}
	if response.HTTPStatus != http.StatusFound {
		t.Fatalf("response status = %d, want %d", response.HTTPStatus, http.StatusFound)
	}
}

func TestClientPreservesTypedNonSuccessDocument(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != "/v1/platform/guest:start" {
			t.Fatalf("unexpected request %s %s", request.Method, request.URL.Path)
		}
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusServiceUnavailable)
		_, _ = writer.Write([]byte(`{"schemaVersion":"v1","state":"failed","requestId":"operator-start-1"}`))
	}))
	defer server.Close()

	endpoint, err := platformctlcontrolclient.ParseLocalControlEndpoint(server.URL)
	if err != nil {
		t.Fatalf("ParseLocalControlEndpoint() error = %v", err)
	}
	client, err := platformctlcontrolclient.NewClient(server.Client())
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	response, err := client.Execute(context.Background(), endpoint, http.MethodPost, "/v1/platform/guest:start", []byte(`{"requestId":"operator-start-1"}`))
	var statusError *platformctlcontrolclient.ResponseStatusError
	if !errors.As(err, &statusError) || statusError.Status != http.StatusServiceUnavailable {
		t.Fatalf("Execute() error = %v, want HTTP status error", err)
	}
	if response.HTTPStatus != http.StatusServiceUnavailable {
		t.Fatalf("response status = %d, want %d", response.HTTPStatus, http.StatusServiceUnavailable)
	}
	if string(response.Document) != `{"schemaVersion":"v1","state":"failed","requestId":"operator-start-1"}` {
		t.Fatalf("response document = %s", response.Document)
	}
}

func TestClientRejectsNonJSONResponseWithoutInventingAReadResult(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusOK)
		_, _ = writer.Write([]byte("not-json"))
	}))
	defer server.Close()

	endpoint, err := platformctlcontrolclient.ParseLocalControlEndpoint(server.URL)
	if err != nil {
		t.Fatalf("ParseLocalControlEndpoint() error = %v", err)
	}
	client, err := platformctlcontrolclient.NewClient(server.Client())
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	if _, err := client.Execute(context.Background(), endpoint, http.MethodGet, "/v1/platform/installation", nil); err == nil {
		t.Fatal("Execute() error = nil, want invalid JSON error")
	}
}
