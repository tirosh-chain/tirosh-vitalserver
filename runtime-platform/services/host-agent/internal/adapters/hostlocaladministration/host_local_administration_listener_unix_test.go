//go:build darwin || linux

package hostlocaladministration_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hostlocaladministration"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

func TestOpenPublishesDescriptorOnlyForPeerAuthorizedUnixControl(t *testing.T) {
	directory := shortUnixSocketTemporaryDirectory(t)
	authorizedUserID := os.Geteuid()
	configuration := hostdeployment.HostLocalAdministrationConfiguration{
		Transport:        "unix-domain-socket",
		EndpointAddress:  filepath.Join(directory, "host-agent.sock"),
		DescriptorPath:   filepath.Join(directory, "host-agent.local.json"),
		AuthorizedUserID: &authorizedUserID,
	}
	listener, err := hostlocaladministration.Open(configuration)
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/v1/platform/installation" {
			t.Fatalf("request path = %q", request.URL.Path)
		}
		writer.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(writer, `{"schemaVersion":"v1","state":"available"}`)
	})}
	serveResults := make(chan error, 1)
	go func() { serveResults <- server.Serve(listener) }()

	encodedDescriptor, err := os.ReadFile(configuration.DescriptorPath)
	if err != nil {
		t.Fatalf("read C52 descriptor: %v", err)
	}
	var descriptor hostlocaladministration.EndpointDescriptor
	if err := json.Unmarshal(encodedDescriptor, &descriptor); err != nil {
		t.Fatalf("decode C52 descriptor: %v", err)
	}
	if descriptor.SchemaVersion != "v1" || descriptor.Transport != configuration.Transport || descriptor.Address != configuration.EndpointAddress {
		t.Fatalf("C52 descriptor = %#v", descriptor)
	}

	response, err := unixSocketHTTPClient(configuration.EndpointAddress).Get("http://host-agent.local/v1/platform/installation")
	if err != nil {
		t.Fatalf("authorized local control request: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("response status = %d", response.StatusCode)
	}

	if err := listener.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	if err := <-serveResults; !errors.Is(err, http.ErrServerClosed) && !errors.Is(err, net.ErrClosed) {
		t.Fatalf("Serve() error = %v", err)
	}
	if _, err := os.Lstat(configuration.DescriptorPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("C52 descriptor remains after Close: %v", err)
	}
	if _, err := os.Lstat(configuration.EndpointAddress); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("local socket remains after Close: %v", err)
	}
}

func TestOpenRejectsAUnixPeerWhoseEffectiveUserDoesNotMatchC33(t *testing.T) {
	directory := shortUnixSocketTemporaryDirectory(t)
	unauthorizedUserID := os.Geteuid() + 1
	configuration := hostdeployment.HostLocalAdministrationConfiguration{
		Transport:        "unix-domain-socket",
		EndpointAddress:  filepath.Join(directory, "host-agent.sock"),
		DescriptorPath:   filepath.Join(directory, "host-agent.local.json"),
		AuthorizedUserID: &unauthorizedUserID,
	}
	listener, err := hostlocaladministration.Open(configuration)
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer func() {
		if err := listener.Close(); err != nil {
			t.Fatalf("Close() error = %v", err)
		}
	}()
	server := &http.Server{Handler: http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("unauthorized Unix peer reached Host Agent HTTP handler")
	})}
	go func() { _ = server.Serve(listener) }()

	requestContext, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	request, err := http.NewRequestWithContext(requestContext, http.MethodGet, "http://host-agent.local/v1/platform/installation", nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := unixSocketHTTPClient(configuration.EndpointAddress).Do(request); err == nil {
		t.Fatal("unauthorized local control request succeeded")
	}
}

func unixSocketHTTPClient(socketPath string) *http.Client {
	return &http.Client{Transport: &http.Transport{
		DialContext: func(context.Context, string, string) (net.Conn, error) {
			return net.Dial("unix", socketPath)
		},
	}}
}

func shortUnixSocketTemporaryDirectory(t *testing.T) string {
	t.Helper()
	directory, err := os.MkdirTemp(os.TempDir(), "vsctl-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	return directory
}
