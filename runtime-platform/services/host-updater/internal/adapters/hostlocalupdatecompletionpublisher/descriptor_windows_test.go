//go:build windows

package hostlocalupdatecompletionpublisher

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Microsoft/go-winio"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func TestHostLocalDescriptorCompletionPublisherUsesTheDeclaredWindowsNamedPipe(t *testing.T) {
	pipeAddress := fmt.Sprintf(`\\.\pipe\vitalserver-c52-%d`, time.Now().UnixNano())
	listener, err := winio.ListenPipe(pipeAddress, nil)
	if err != nil {
		t.Fatalf("listen C52 named pipe: %v", err)
	}
	defer listener.Close()

	requestObserved := make(chan error, 1)
	server := &http.Server{Handler: http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != "/v1/platform/updates/update-020:complete" {
			requestObserved <- fmt.Errorf("request method=%s path=%s", request.Method, request.URL.Path)
			http.Error(response, "unexpected completion request", http.StatusBadRequest)
			return
		}
		var command hostupdaterdomain.StagedProductUpdateCompletionCommand
		if err := json.NewDecoder(request.Body).Decode(&command); err != nil || command.UpdateID != "update-020" {
			requestObserved <- fmt.Errorf("decode C27 command=%+v err=%v", command, err)
			http.Error(response, "invalid completion command", http.StatusBadRequest)
			return
		}
		response.WriteHeader(http.StatusAccepted)
		requestObserved <- nil
	})}
	go func() { _ = server.Serve(listener) }()
	defer server.Close()

	descriptorPath := filepath.Join(t.TempDir(), "endpoint.json")
	descriptorContents, err := json.Marshal(HostLocalAdministrationEndpointDescriptor{
		SchemaVersion: "v1",
		Transport:     "windows-named-pipe",
		Address:       pipeAddress,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(descriptorPath, descriptorContents, 0o600); err != nil {
		t.Fatalf("write C52 descriptor: %v", err)
	}
	publisher, err := NewHostLocalDescriptorStagedProductUpdateCompletionPublisher(descriptorPath, time.Second)
	if err != nil {
		t.Fatalf("configure C52 publisher: %v", err)
	}
	command := hostupdaterdomain.StagedProductUpdateCompletionCommand{
		SchemaVersion:           "v1",
		UpdateID:                "update-020",
		ExpectedJournalRevision: 3,
		Report: hostupdaterdomain.StagedProductUpdateExecutionReport{
			SchemaVersion: "v1",
			UpdateID:      "update-020",
			RequestID:     "request-020",
		},
	}
	if err := publisher.Publish(context.Background(), pipeAddress, command); err != nil {
		t.Fatalf("publish C27 through C52 named pipe: %v", err)
	}
	select {
	case err := <-requestObserved:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("Host Agent did not observe the C27 completion request")
	}
}
