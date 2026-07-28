// Command host-update-ownership-fixture provides the explicit C80 idle
// contract used by Linux package acceptance where systemd is intentionally
// absent. It is test tooling, not a Host Agent fallback.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

const schemaVersion = "v1"

type endpointDescriptor struct {
	SchemaVersion string `json:"schemaVersion"`
	Transport     string `json:"transport"`
	Address       string `json:"address"`
}

type ownership struct {
	SchemaVersion        string `json:"schemaVersion"`
	InstallationID       string `json:"installationId"`
	InstallationRevision int    `json:"installationRevision"`
	State                string `json:"state"`
}

type readResult struct {
	SchemaVersion string    `json:"schemaVersion"`
	State         string    `json:"state"`
	ObservedAt    string    `json:"observedAt"`
	Value         ownership `json:"value"`
}

func main() {
	socketPath := flag.String("socket", "", "required absolute Unix socket path")
	descriptorPath := flag.String("descriptor", "", "required absolute endpoint descriptor path")
	installationID := flag.String("installation-id", "", "required installation identity")
	installationRevision := flag.Int("installation-revision", 0, "required positive installation revision")
	flag.Parse()
	if !filepath.IsAbs(*socketPath) || !filepath.IsAbs(*descriptorPath) || *installationID == "" || *installationRevision < 1 {
		fmt.Fprintln(os.Stderr, "absolute socket/descriptor paths, installation id, and positive revision are required")
		os.Exit(2)
	}
	if err := os.MkdirAll(filepath.Dir(*socketPath), 0o755); err != nil {
		fail("create socket directory", err)
	}
	if err := os.MkdirAll(filepath.Dir(*descriptorPath), 0o755); err != nil {
		fail("create descriptor directory", err)
	}
	listener, err := net.Listen("unix", *socketPath)
	if err != nil {
		fail("listen on ownership socket", err)
	}
	defer listener.Close()
	if err := os.Chmod(*socketPath, 0o600); err != nil {
		fail("protect ownership socket", err)
	}
	descriptor, err := json.Marshal(endpointDescriptor{
		SchemaVersion: schemaVersion,
		Transport:     "unix-domain-socket",
		Address:       *socketPath,
	})
	if err != nil {
		fail("encode ownership descriptor", err)
	}
	if err := os.WriteFile(*descriptorPath, append(descriptor, '\n'), 0o600); err != nil {
		fail("publish ownership descriptor", err)
	}

	result := readResult{
		SchemaVersion: schemaVersion,
		State:         "available",
		ObservedAt:    time.Now().UTC().Format(time.RFC3339),
		Value: ownership{
			SchemaVersion:        schemaVersion,
			InstallationID:       *installationID,
			InstallationRevision: *installationRevision,
			State:                "idle",
		},
	}
	handler := http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet || request.URL.Path != "/v1/platform/update-operation-ownership" {
			http.NotFound(response, request)
			return
		}
		response.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(response).Encode(result)
	})
	if err := http.Serve(listener, handler); err != nil {
		fail("serve ownership contract", err)
	}
}

func fail(operation string, err error) {
	fmt.Fprintf(os.Stderr, "%s: %v\n", operation, err)
	os.Exit(1)
}
