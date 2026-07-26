//go:build darwin || linux

package platformctlcontrolclient_test

import (
	"context"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/platformctl/internal/platformctlcontrolclient"
)

func TestLocalAdministrationDescriptorUsesOnlyItsUnixSocketTransport(t *testing.T) {
	directory, err := os.MkdirTemp(os.TempDir(), "platformctl-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	socketPath := filepath.Join(directory, "host-agent.sock")
	descriptorPath := filepath.Join(directory, "host-agent.local.json")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/v1/platform/installation" {
			t.Fatalf("request path = %q", request.URL.Path)
		}
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write([]byte(`{"schemaVersion":"v1","state":"available"}`))
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() {
		_ = server.Close()
		_ = listener.Close()
	})
	if err := os.WriteFile(descriptorPath, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"`+socketPath+`"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	endpoint, err := platformctlcontrolclient.LoadLocalAdministrationEndpointDescriptor(descriptorPath)
	if err != nil {
		t.Fatalf("LoadLocalAdministrationEndpointDescriptor() error = %v", err)
	}
	client, err := platformctlcontrolclient.NewClientForLocalAdministrationEndpoint(endpoint, time.Second)
	if err != nil {
		t.Fatalf("NewClientForLocalAdministrationEndpoint() error = %v", err)
	}
	response, err := client.Execute(context.Background(), endpoint, http.MethodGet, "/v1/platform/installation", nil)
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if response.HTTPStatus != http.StatusOK || string(response.Document) != `{"schemaVersion":"v1","state":"available"}` {
		t.Fatalf("response = %#v", response)
	}
}

func TestLocalAdministrationDescriptorRejectsUnknownFields(t *testing.T) {
	directory, err := os.MkdirTemp(os.TempDir(), "platformctl-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	descriptorPath := filepath.Join(directory, "host-agent.local.json")
	if err := os.WriteFile(descriptorPath, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"/tmp/host-agent.sock","unexpected":true}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := platformctlcontrolclient.LoadLocalAdministrationEndpointDescriptor(descriptorPath); err == nil {
		t.Fatal("LoadLocalAdministrationEndpointDescriptor() accepted unknown C52 field")
	}
}
