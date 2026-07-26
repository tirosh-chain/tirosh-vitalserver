//go:build linux

// Package guestruntimecontrolvirtiolistener adapts the C37 Guest Runtime
// control listener declaration to the generic Linux AF_VSOCK transport.
package guestruntimecontrolvirtiolistener

import (
	"net"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestvirtiotransport"
)

// ListenGuestRuntimeControlVirtioSocket opens the Guest-owned C37 control
// listener. Its name intentionally does not imply that AF_VSOCK is a TCP or
// Guest-IP transport.
func ListenGuestRuntimeControlVirtioSocket(port uint32) (net.Listener, error) {
	return guestvirtiotransport.ListenGuestVirtioSocket(port)
}
