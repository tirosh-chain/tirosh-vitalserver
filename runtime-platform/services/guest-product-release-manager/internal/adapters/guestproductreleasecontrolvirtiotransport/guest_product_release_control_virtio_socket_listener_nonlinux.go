//go:build !linux

package guestproductreleasecontrolvirtiotransport

import (
	"fmt"
	"net"
)

// ListenGuestProductReleaseManagerControlVirtioSocket makes the unsupported
// platform explicit rather than replacing C59's Guest transport with TCP.
func ListenGuestProductReleaseManagerControlVirtioSocket(port uint32) (net.Listener, error) {
	return nil, fmt.Errorf("Guest Product Release Manager control virtio-socket is only available on Linux")
}
