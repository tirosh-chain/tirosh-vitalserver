//go:build darwin || linux

package hostupdateoperationownershipclient

import (
	"context"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestClientReadsExplicitHostUpdateOwnershipThroughUnixSocket(t *testing.T) {
	directory, err := os.MkdirTemp("/tmp", "him-c80-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	socketPath := filepath.Join(directory, "host-agent.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	server := &http.Server{Handler: http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet || request.URL.Path != "/v1/platform/update-operation-ownership" {
			http.NotFound(response, request)
			return
		}
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"schemaVersion":"v1","state":"available","observedAt":"2026-07-27T00:00:00Z","sourceRevision":7,"evidenceReferences":[{"kind":"host-update-journal","reference":"update-1"}],"value":{"schemaVersion":"v1","installationId":"installation-1","installationRevision":4,"state":"active","updateId":"update-1","operationId":"operation-1","requestId":"request-1","updateState":"applying","interruptionRequested":true,"interruptionRequestId":"interrupt-1","journalRevision":7}}`))
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Shutdown(context.Background()) })

	descriptorPath := filepath.Join(directory, "host-agent.local.json")
	if err := os.WriteFile(descriptorPath, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"`+socketPath+`"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	client, err := New(descriptorPath, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	observation, err := client.ReadHostUpdateOperationOwnership(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if observation.ReadState != hostinstallationmanagerdomain.HostUpdateOwnershipReadAvailable || observation.Ownership == nil || observation.Ownership.State != "active" || observation.Ownership.UpdateID != "update-1" || observation.Ownership.JournalRevision != 7 {
		t.Fatalf("observation=%+v", observation)
	}
}

func TestClientPreservesUnavailableOwnershipRead(t *testing.T) {
	directory, err := os.MkdirTemp("/tmp", "him-c80-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	socketPath := filepath.Join(directory, "host-agent.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	server := &http.Server{Handler: http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		response.WriteHeader(http.StatusServiceUnavailable)
		_, _ = response.Write([]byte(`{"schemaVersion":"v1","state":"failed","observedAt":"2026-07-27T00:00:00Z","issue":{"code":"active-host-update-state-read-failed","message":"sqlite unavailable","dependency":"host-state-store"}}`))
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Shutdown(context.Background()) })

	descriptorPath := filepath.Join(directory, "host-agent.local.json")
	if err := os.WriteFile(descriptorPath, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"`+socketPath+`"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	client, err := New(descriptorPath, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	observation, err := client.ReadHostUpdateOperationOwnership(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if observation.ReadState != hostinstallationmanagerdomain.HostUpdateOwnershipReadFailed || observation.Issue == nil || observation.Issue.Code != "active-host-update-state-read-failed" || observation.Ownership != nil {
		t.Fatalf("observation=%+v", observation)
	}
}
