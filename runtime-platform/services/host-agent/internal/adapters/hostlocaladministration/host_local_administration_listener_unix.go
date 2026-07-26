//go:build darwin || linux

package hostlocaladministration

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

func openPlatformLocalControlListener(configuration hostdeployment.HostLocalAdministrationConfiguration) (net.Listener, func() error, error) {
	if configuration.Transport != "unix-domain-socket" {
		return nil, nil, fmt.Errorf("local administration transport %q is not supported by this Host OS", configuration.Transport)
	}
	if err := verifyUnixSocketParent(configuration.EndpointAddress); err != nil {
		return nil, nil, err
	}
	if existing, err := os.Lstat(configuration.EndpointAddress); err == nil {
		if existing.Mode()&os.ModeSocket == 0 {
			return nil, nil, errors.New("local administration socket path must be absent or a socket")
		}
		if err := os.Remove(configuration.EndpointAddress); err != nil {
			return nil, nil, fmt.Errorf("remove stale local administration socket: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, nil, fmt.Errorf("inspect local administration socket path: %w", err)
	}
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: configuration.EndpointAddress, Net: "unix"})
	if err != nil {
		return nil, nil, fmt.Errorf("listen on local administration socket: %w", err)
	}
	if err := os.Chmod(configuration.EndpointAddress, 0o666); err != nil {
		_ = listener.Close()
		_ = os.Remove(configuration.EndpointAddress)
		return nil, nil, fmt.Errorf("set local administration socket permissions: %w", err)
	}
	authorized := *configuration.AuthorizedUserID
	secured := peerAuthorizedUnixListener{Listener: listener, authorizedUserID: authorized}
	return secured, func() error {
		closeErr := listener.Close()
		removeErr := os.Remove(configuration.EndpointAddress)
		if errors.Is(removeErr, os.ErrNotExist) {
			removeErr = nil
		}
		return errors.Join(closeErr, removeErr)
	}, nil
}

func verifyUnixSocketParent(address string) error {
	directory := filepath.Dir(address)
	information, err := os.Stat(directory)
	if err != nil {
		return fmt.Errorf("local administration socket directory is unavailable: %w", err)
	}
	if !information.IsDir() {
		return errors.New("local administration socket parent must be a directory")
	}
	if information.Mode().Perm()&0o022 != 0 {
		return errors.New("local administration socket parent must not be group or world writable")
	}
	metadata, ok := information.Sys().(*syscall.Stat_t)
	if !ok || metadata.Uid != uint32(os.Geteuid()) {
		return errors.New("local administration socket parent must be owned by the Host Agent effective user")
	}
	return nil
}

type peerAuthorizedUnixListener struct {
	net.Listener
	authorizedUserID int
}

func (listener peerAuthorizedUnixListener) Accept() (net.Conn, error) {
	for {
		connection, err := listener.Listener.Accept()
		if err != nil {
			return nil, err
		}
		userID, peerErr := unixPeerUserID(connection)
		if peerErr == nil && userID == listener.authorizedUserID {
			return connection, nil
		}
		_ = connection.Close()
	}
}
