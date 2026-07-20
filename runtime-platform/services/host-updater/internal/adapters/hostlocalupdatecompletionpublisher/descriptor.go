package hostlocalupdatecompletionpublisher

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

const maximumHostLocalAdministrationDescriptorBytes int64 = 1 << 20

// HostLocalAdministrationEndpointDescriptor is C52 as consumed by the
// staged next updater. It carries an OS-local address only; authorization is
// enforced by the Host Agent listener before this updater's request is read.
type HostLocalAdministrationEndpointDescriptor struct {
	SchemaVersion string `json:"schemaVersion"`
	Transport     string `json:"transport"`
	Address       string `json:"address"`
}

// HostLocalDescriptorStagedProductUpdateCompletionPublisher binds C27 to the
// one C52 address the Host Agent published. Its caller cannot replace that
// address with an arbitrary HTTP origin at publish time.
type HostLocalDescriptorStagedProductUpdateCompletionPublisher struct {
	descriptor HostLocalAdministrationEndpointDescriptor
	httpClient *http.Client
}

// NewHostLocalDescriptorStagedProductUpdateCompletionPublisher opens one
// explicit C52 descriptor. The descriptor must be a regular, non-symlinked
// file; missing or malformed local-control state is unavailable, never a
// fallback to a TCP address.
func NewHostLocalDescriptorStagedProductUpdateCompletionPublisher(descriptorPath string, timeout time.Duration) (*HostLocalDescriptorStagedProductUpdateCompletionPublisher, error) {
	if timeout <= 0 {
		return nil, fmt.Errorf("Host-local completion timeout must be positive")
	}
	descriptor, err := ReadHostLocalAdministrationEndpointDescriptor(descriptorPath)
	if err != nil {
		return nil, err
	}
	httpClient, err := newHostLocalDescriptorHTTPClient(descriptor, timeout)
	if err != nil {
		return nil, err
	}
	return &HostLocalDescriptorStagedProductUpdateCompletionPublisher{descriptor: descriptor, httpClient: httpClient}, nil
}

// EndpointAddress exposes the C52 value this publisher was constructed with
// so the application keeps an explicit endpoint input while this adapter
// rejects substitutions.
func (publisher *HostLocalDescriptorStagedProductUpdateCompletionPublisher) EndpointAddress() string {
	if publisher == nil {
		return ""
	}
	return publisher.descriptor.Address
}

func (publisher *HostLocalDescriptorStagedProductUpdateCompletionPublisher) Publish(ctx context.Context, completionEndpoint string, command hostupdaterdomain.StagedProductUpdateCompletionCommand) error {
	if publisher == nil || publisher.httpClient == nil {
		return fmt.Errorf("Host-local descriptor completion publisher is unavailable")
	}
	if completionEndpoint != publisher.descriptor.Address {
		return fmt.Errorf("C27 completion endpoint does not match the configured C52 descriptor")
	}
	endpoint, err := stagedProductUpdateCompletionURL("http://host-agent", command.UpdateID)
	if err != nil {
		return err
	}
	return publishStagedProductUpdateCompletion(ctx, publisher.httpClient, endpoint, command)
}

// ReadHostLocalAdministrationEndpointDescriptor reads one strict C52
// descriptor. It does not consult C33, derive an address, or treat a missing
// descriptor as a development-loopback endpoint.
func ReadHostLocalAdministrationEndpointDescriptor(path string) (HostLocalAdministrationEndpointDescriptor, error) {
	if path == "" || !filepath.IsAbs(path) {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("C52 descriptor path must be absolute")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("C52 descriptor is missing, not regular, or a symbolic link")
	}
	file, err := os.Open(path)
	if err != nil {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("open C52 descriptor: %w", err)
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumHostLocalAdministrationDescriptorBytes+1))
	if err != nil {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("read C52 descriptor: %w", err)
	}
	if int64(len(contents)) > maximumHostLocalAdministrationDescriptorBytes {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("C52 descriptor exceeds maximum document size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var descriptor HostLocalAdministrationEndpointDescriptor
	if err := decoder.Decode(&descriptor); err != nil {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("decode C52 descriptor: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return HostLocalAdministrationEndpointDescriptor{}, fmt.Errorf("C52 descriptor must contain exactly one JSON object")
	}
	if err := validateHostLocalAdministrationEndpointDescriptor(descriptor); err != nil {
		return HostLocalAdministrationEndpointDescriptor{}, err
	}
	return descriptor, nil
}

func validateHostLocalAdministrationEndpointDescriptor(descriptor HostLocalAdministrationEndpointDescriptor) error {
	if descriptor.SchemaVersion != "v1" {
		return fmt.Errorf("C52 descriptor schemaVersion must be v1")
	}
	switch descriptor.Transport {
	case "unix-domain-socket":
		if !filepath.IsAbs(descriptor.Address) || strings.Contains(descriptor.Address, "\\") || strings.Contains(descriptor.Address, "..") || len(descriptor.Address) > 104 {
			return fmt.Errorf("C52 unix-domain-socket address is invalid")
		}
	case "windows-named-pipe":
		const prefix = `\\.\pipe\`
		name := strings.TrimPrefix(descriptor.Address, prefix)
		if !strings.HasPrefix(descriptor.Address, prefix) || name == "" || len(name) > 128 || !validDescriptorIdentifier(name) {
			return fmt.Errorf("C52 windows-named-pipe address is invalid")
		}
	default:
		return fmt.Errorf("C52 descriptor transport is unsupported")
	}
	return nil
}

func validDescriptorIdentifier(value string) bool {
	for index, character := range value {
		if !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != '-' {
			return false
		}
		if index == 0 && !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') {
			return false
		}
	}
	return true
}
