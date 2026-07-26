//go:build darwin || linux

package hostlocalupdatecompletionpublisher

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func TestHostLocalDescriptorCompletionPublisherUsesTheDeclaredUnixSocket(t *testing.T) {
	temporaryRoot, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil {
		t.Fatalf("resolve temporary root: %v", err)
	}
	directory, err := os.MkdirTemp(temporaryRoot, "vshup-")
	if err != nil {
		t.Fatalf("create short temporary directory: %v", err)
	}
	defer os.RemoveAll(directory)
	socketPath := filepath.Join(directory, "host-agent.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("listen C52 socket: %v", err)
	}
	defer listener.Close()
	server := &http.Server{Handler: http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != "/v1/platform/updates/update-020:complete" {
			t.Fatalf("request method=%s path=%s", request.Method, request.URL.Path)
		}
		var command hostupdaterdomain.StagedProductUpdateCompletionCommand
		if err := json.NewDecoder(request.Body).Decode(&command); err != nil || command.UpdateID != "update-020" {
			t.Fatalf("decode C27 command=%+v err=%v", command, err)
		}
		response.WriteHeader(http.StatusAccepted)
	})}
	go func() { _ = server.Serve(listener) }()
	defer server.Close()

	descriptorPath := filepath.Join(directory, "endpoint.json")
	descriptor := HostLocalAdministrationEndpointDescriptor{SchemaVersion: "v1", Transport: "unix-domain-socket", Address: socketPath}
	contents, err := json.Marshal(descriptor)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(descriptorPath, contents, 0o600); err != nil {
		t.Fatalf("write C52 descriptor: %v", err)
	}
	publisher, err := NewHostLocalDescriptorStagedProductUpdateCompletionPublisher(descriptorPath, time.Second)
	if err != nil {
		t.Fatalf("configure C52 publisher: %v", err)
	}
	command := hostupdaterdomain.StagedProductUpdateCompletionCommand{SchemaVersion: "v1", UpdateID: "update-020", ExpectedJournalRevision: 3, Report: hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-020", RequestID: "request-020"}}
	if err := publisher.Publish(context.Background(), socketPath, command); err != nil {
		t.Fatalf("publish C27 through C52: %v", err)
	}
}

func TestHostLocalDescriptorCompletionPublisherRejectsEndpointSubstitution(t *testing.T) {
	publisher := &HostLocalDescriptorStagedProductUpdateCompletionPublisher{descriptor: HostLocalAdministrationEndpointDescriptor{SchemaVersion: "v1", Transport: "unix-domain-socket", Address: "/tmp/host-agent.sock"}, httpClient: http.DefaultClient}
	if err := publisher.Publish(context.Background(), "/tmp/other.sock", hostupdaterdomain.StagedProductUpdateCompletionCommand{UpdateID: "update-020"}); err == nil {
		t.Fatal("expected C52 endpoint substitution to be rejected")
	}
}
