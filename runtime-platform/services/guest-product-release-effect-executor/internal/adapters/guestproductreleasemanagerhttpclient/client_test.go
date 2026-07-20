package guestproductreleasemanagerhttpclient

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

func TestApplyReleaseUpdateStreamsCommandAndArchiveToDeclaredLoopbackEndpoint(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerPath {
			t.Fatalf("unexpected request %s %s", request.Method, request.URL.Path)
		}
		reader, err := request.MultipartReader()
		if err != nil {
			t.Fatal(err)
		}
		commandPart, err := reader.NextPart()
		if err != nil || commandPart.FormName() != "command" {
			t.Fatalf("unexpected command part: %v %#v", err, commandPart)
		}
		var command guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand
		if err := json.NewDecoder(commandPart).Decode(&command); err != nil {
			t.Fatal(err)
		}
		archivePart, err := reader.NextPart()
		if err != nil || archivePart.FormName() != "releaseArchive" {
			t.Fatalf("unexpected archive part: %v %#v", err, archivePart)
		}
		archive, err := io.ReadAll(archivePart)
		if err != nil || string(archive) != "release-archive" {
			t.Fatalf("unexpected archive %q: %v", archive, err)
		}
		if _, err := reader.NextPart(); err != io.EOF {
			t.Fatalf("expected exactly two parts, got %v", err)
		}
		operation := guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{SchemaVersion: "v1", UpdateID: command.UpdateID, ExpectedActiveReleaseID: command.ExpectedActiveReleaseID, TargetRelease: command.TargetRelease, State: "succeeded", ActiveReleaseID: command.TargetRelease.ReleaseID, ObservedAt: "2026-07-20T00:00:02Z"}
		response.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(response).Encode(operation); err != nil {
			t.Fatal(err)
		}
	}))
	server.Listener = listener
	server.Start()
	defer server.Close()
	port := listener.Addr().(*net.TCPAddr).Port
	archivePath := filepath.Join(t.TempDir(), "release.tar.gz")
	if err := os.WriteFile(archivePath, []byte("release-archive"), 0o600); err != nil {
		t.Fatal(err)
	}
	client, err := New(time.Second)
	if err != nil {
		t.Fatal(err)
	}
	command := guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand{SchemaVersion: "v1", UpdateID: "update-020", ExpectedActiveReleaseID: "release-020", TargetRelease: guestproductreleaseeffectexecutordomain.GuestProductReleaseTarget{ReleaseID: "release-021", ReleaseDirectory: "/opt/vitalserver/releases/release-021", Artifact: guestproductreleaseeffectexecutordomain.GuestProductReleaseArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 15, MediaType: guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerMediaType}}, RequestedAt: "2026-07-20T00:00:00Z"}
	operation, err := client.ApplyReleaseUpdate(context.Background(), guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerEndpoint{Scheme: "http", Host: "127.0.0.1", Port: port, Path: guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerPath, RequestTimeoutMilliseconds: 1000}, command, guestproductreleaseeffectexecutordomain.ReleaseArtifact{Path: archivePath, SHA256: command.TargetRelease.Artifact.SHA256, SizeBytes: 15})
	if err != nil {
		t.Fatal(err)
	}
	if operation.State != "succeeded" || operation.UpdateID != command.UpdateID {
		t.Fatalf("unexpected C59 operation: %+v", operation)
	}
}
