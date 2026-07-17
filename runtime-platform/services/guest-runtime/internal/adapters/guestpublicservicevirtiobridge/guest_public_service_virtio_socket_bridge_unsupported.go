//go:build !linux

// Package guestpublicservicevirtiobridge makes the Linux-only C37 public
// service transport explicit on unsupported Guest operating systems.
package guestpublicservicevirtiobridge

import (
	"context"
	"fmt"
)

type GuestPublicServiceVirtioSocketBridgeConfiguration struct {
	RouteID          string
	VirtioSocketPort uint32
	TargetTCPAddress string
}

func RunGuestPublicServiceVirtioSocketBridge(_ context.Context, configuration GuestPublicServiceVirtioSocketBridgeConfiguration) error {
	return fmt.Errorf("Guest public service route %s virtio-socket bridge is unsupported on this operating system", configuration.RouteID)
}
