package main

import (
	"fmt"
	"net"
	"strconv"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestpublicservicevirtiobridge"
)

// guestPublicServiceVirtioSocketBridgeArguments holds the exact C37 process
// invocation values. It is a CLI boundary representation, not Guest Runtime
// domain state: C37 owns the route identity and target selection.
type guestPublicServiceVirtioSocketBridgeArguments []string

func (arguments *guestPublicServiceVirtioSocketBridgeArguments) String() string {
	return strings.Join(*arguments, ";")
}

func (arguments *guestPublicServiceVirtioSocketBridgeArguments) Set(value string) error {
	if value == "" {
		return fmt.Errorf("Guest public service virtio-socket bridge argument is empty")
	}
	*arguments = append(*arguments, value)
	return nil
}

func parseGuestPublicServiceVirtioSocketBridgeArguments(arguments guestPublicServiceVirtioSocketBridgeArguments) ([]guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration, error) {
	if len(arguments) == 0 {
		return nil, fmt.Errorf("Guest public service virtio-socket bridges are required")
	}
	configurations := make([]guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration, 0, len(arguments))
	routeIDs := make(map[string]struct{}, len(arguments))
	virtioSocketPorts := make(map[uint32]struct{}, len(arguments))
	for _, argument := range arguments {
		configuration, err := parseGuestPublicServiceVirtioSocketBridgeArgument(argument)
		if err != nil {
			return nil, err
		}
		if _, duplicate := routeIDs[configuration.RouteID]; duplicate {
			return nil, fmt.Errorf("Guest public service virtio-socket bridge routeId %q is duplicated", configuration.RouteID)
		}
		if _, duplicate := virtioSocketPorts[configuration.VirtioSocketPort]; duplicate {
			return nil, fmt.Errorf("Guest public service virtio-socket bridge port %d is duplicated", configuration.VirtioSocketPort)
		}
		routeIDs[configuration.RouteID] = struct{}{}
		virtioSocketPorts[configuration.VirtioSocketPort] = struct{}{}
		configurations = append(configurations, configuration)
	}
	return configurations, nil
}

func parseGuestPublicServiceVirtioSocketBridgeArgument(argument string) (guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration, error) {
	components := strings.Split(argument, ",")
	if len(components) != 3 || !validGuestRuntimeIdentifier(components[0]) {
		return guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration{}, fmt.Errorf("Guest public service virtio-socket bridge must be routeId,virtioSocketPort,127.0.0.1:targetPort")
	}
	virtioSocketPort, err := parseGuestRuntimePort(components[1])
	if err != nil {
		return guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration{}, fmt.Errorf("Guest public service route %s virtio-socket port is invalid: %w", components[0], err)
	}
	targetHost, targetPortText, err := net.SplitHostPort(components[2])
	if err != nil || targetHost != "127.0.0.1" {
		return guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration{}, fmt.Errorf("Guest public service route %s target must be an explicit 127.0.0.1 TCP address", components[0])
	}
	targetPort, err := parseGuestRuntimePort(targetPortText)
	if err != nil {
		return guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration{}, fmt.Errorf("Guest public service route %s target port is invalid: %w", components[0], err)
	}
	return guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration{
		RouteID:          components[0],
		VirtioSocketPort: virtioSocketPort,
		TargetTCPAddress: net.JoinHostPort(targetHost, strconv.Itoa(int(targetPort))),
	}, nil
}

func parseGuestRuntimePort(value string) (uint32, error) {
	parsed, err := strconv.ParseUint(value, 10, 16)
	if err != nil || parsed == 0 {
		return 0, fmt.Errorf("must be between 1 and 65535")
	}
	return uint32(parsed), nil
}

func validGuestRuntimeIdentifier(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '_' || character == '-' {
			if index == 0 && (character == '.' || character == '_' || character == '-') {
				return false
			}
			continue
		}
		return false
	}
	return true
}
