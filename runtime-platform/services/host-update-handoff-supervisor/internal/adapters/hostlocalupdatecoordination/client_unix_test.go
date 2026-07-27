//go:build darwin || linux

package hostlocalupdatecoordination

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

func TestClientObservesAndConfirmsExactInterruptionOverUnixSocket(t *testing.T) {
	directory, err := os.MkdirTemp("/tmp", "host-update-coordination-")
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
	confirmationReceived := make(chan hostupdatehandoffsupervisordomain.HostUpdateInterruptionConfirmation, 1)
	server := &http.Server{Handler: http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/v1/platform/update-operation-ownership":
			response.Header().Set("Content-Type", "application/json")
			_, _ = response.Write([]byte(`{"schemaVersion":"v1","state":"available","observedAt":"2026-07-27T00:00:00Z","value":{"schemaVersion":"v1","installationId":"installation-1","installationRevision":4,"state":"active","updateId":"update-1","operationId":"operation-1","requestId":"update-request-1","updateState":"applying","interruptionRequested":true,"interruptionRequestId":"interruption-1","journalRevision":7}}`))
		case "/v1/platform/updates/update-1:confirm-interruption":
			var confirmation hostupdatehandoffsupervisordomain.HostUpdateInterruptionConfirmation
			if err := json.NewDecoder(request.Body).Decode(&confirmation); err != nil {
				http.Error(response, err.Error(), http.StatusBadRequest)
				return
			}
			confirmationReceived <- confirmation
			response.WriteHeader(http.StatusAccepted)
		default:
			http.NotFound(response, request)
		}
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Shutdown(context.Background()) })

	descriptorPath := filepath.Join(directory, "host-agent.local.json")
	if err := os.WriteFile(descriptorPath, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"`+socketPath+`"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	client := Client{}
	observation, err := client.WaitForInterruption(context.Background(), descriptorPath, "update-1", 10*time.Millisecond, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if observation.InstallationID != "installation-1" || observation.JournalRevision != 7 || observation.InterruptionRequestID != "interruption-1" {
		t.Fatalf("observation=%+v", observation)
	}
	confirmation, err := hostupdatehandoffsupervisordomain.NewHostUpdateInterruptionConfirmation("attempt-1", observation, "2026-07-27T00:00:01Z")
	if err != nil {
		t.Fatal(err)
	}
	if err := client.PublishInterruptionConfirmation(context.Background(), descriptorPath, time.Second, confirmation); err != nil {
		t.Fatal(err)
	}
	select {
	case received := <-confirmationReceived:
		if received.RequestID != confirmation.RequestID || received.ExpectedJournalRevision != 7 || received.TerminationEvidence.ID != "attempt-1" {
			t.Fatalf("received confirmation=%+v", received)
		}
	case <-time.After(time.Second):
		t.Fatal("Host Agent did not receive interruption confirmation")
	}
}
