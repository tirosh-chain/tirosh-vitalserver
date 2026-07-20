// Package hostlocaladministration owns the Host Agent's OS-local
// administration listener and its public C52 descriptor. It does not decide
// Host or Guest commands; it only admits an OS-authorized local connection to
// the already-versioned Host Agent HTTP facade.
package hostlocaladministration

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

const schemaVersion = "v1"

// EndpointDescriptor is C52. It contains no authorization policy or secret:
// the Host Agent applied those before publishing the descriptor.
type EndpointDescriptor struct {
	SchemaVersion string `json:"schemaVersion"`
	Transport     string `json:"transport"`
	Address       string `json:"address"`
}

// Listener is the Host-owned local administration listener. Closing it also
// removes the descriptor that advertised this instance, so descriptor absence
// remains different from an available local endpoint.
type Listener struct {
	net.Listener
	descriptorPath string
	closeTransport func() error
}

// Open validates the explicit C33 transport selection, binds exactly that
// local endpoint, and publishes C52 only after the listener is ready. It does
// not create a fallback TCP port, discover a user, or infer another endpoint.
func Open(configuration hostdeployment.HostLocalAdministrationConfiguration) (*Listener, error) {
	if err := configuration.Validate(); err != nil {
		return nil, fmt.Errorf("local administration deployment: %w", err)
	}
	listener, closeTransport, err := openPlatformLocalControlListener(configuration)
	if err != nil {
		return nil, err
	}
	result := &Listener{Listener: listener, descriptorPath: configuration.DescriptorPath, closeTransport: closeTransport}
	if err := publishDescriptor(configuration); err != nil {
		_ = result.closeTransport()
		return nil, err
	}
	return result, nil
}

// Close withdraws C52 before closing the local endpoint. A close error is
// explicit because a stale descriptor must not be silently treated as a live
// local-control endpoint.
func (listener *Listener) Close() error {
	if listener == nil {
		return nil
	}
	var failures []error
	if listener.descriptorPath != "" {
		if err := os.Remove(listener.descriptorPath); err != nil && !errors.Is(err, os.ErrNotExist) {
			failures = append(failures, fmt.Errorf("remove C52 descriptor: %w", err))
		}
	}
	if listener.closeTransport != nil {
		if err := listener.closeTransport(); err != nil && !errors.Is(err, net.ErrClosed) {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}

func publishDescriptor(configuration hostdeployment.HostLocalAdministrationConfiguration) error {
	directory := filepath.Dir(configuration.DescriptorPath)
	directoryInfo, err := os.Lstat(directory)
	if err != nil {
		return fmt.Errorf("C52 descriptor directory is unavailable: %w", err)
	}
	if !directoryInfo.IsDir() || directoryInfo.Mode()&os.ModeSymlink != 0 {
		return errors.New("C52 descriptor directory must be a non-symlink directory")
	}
	if existing, statErr := os.Lstat(configuration.DescriptorPath); statErr == nil {
		if !existing.Mode().IsRegular() || existing.Mode()&os.ModeSymlink != 0 {
			return errors.New("C52 descriptor path must be absent or a regular non-symlink file")
		}
	} else if !errors.Is(statErr, os.ErrNotExist) {
		return fmt.Errorf("inspect C52 descriptor path: %w", statErr)
	}
	encoded, err := json.Marshal(EndpointDescriptor{
		SchemaVersion: schemaVersion,
		Transport:     configuration.Transport,
		Address:       configuration.EndpointAddress,
	})
	if err != nil {
		return fmt.Errorf("encode C52 descriptor: %w", err)
	}
	temporary, err := os.CreateTemp(directory, ".host-local-administration-descriptor.*")
	if err != nil {
		return fmt.Errorf("create C52 descriptor: %w", err)
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	if err := temporary.Chmod(0o644); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("set C52 descriptor mode: %w", err)
	}
	if _, err := temporary.Write(append(encoded, '\n')); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write C52 descriptor: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close C52 descriptor: %w", err)
	}
	if err := os.Rename(temporaryPath, configuration.DescriptorPath); err != nil {
		return fmt.Errorf("publish C52 descriptor: %w", err)
	}
	return nil
}
