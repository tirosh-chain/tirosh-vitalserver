//go:build !linux

package guestruntimecontrolvirtiolistener

import (
	"fmt"
	"net"
	"runtime"
)

// ListenGuestRuntimeControlVirtioSocket makes unsupported execution explicit.
// The Guest Product's Linux deployment may require AF_VSOCK; this adapter must
// not replace it with TCP or a synthetic ready listener on another platform.
func ListenGuestRuntimeControlVirtioSocket(port uint32) (net.Listener, error) {
	return nil, fmt.Errorf(
		"Guest Runtime control virtio-socket listener is unavailable on %s for declared port %d",
		runtime.GOOS,
		port,
	)
}
