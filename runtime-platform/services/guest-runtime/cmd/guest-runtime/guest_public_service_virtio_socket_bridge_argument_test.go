package main

import (
	"strings"
	"testing"
)

func TestParseGuestPublicServiceVirtioSocketBridgeArgumentsPreservesNamedRouteAndLoopbackTarget(t *testing.T) {
	bridges, err := parseGuestPublicServiceVirtioSocketBridgeArguments(guestPublicServiceVirtioSocketBridgeArguments{
		"recorder-gateway,18090,127.0.0.1:8090",
		"vitalserver-browser,18088,127.0.0.1:8088",
	})
	if err != nil {
		t.Fatalf("explicit public bridge arguments rejected: %v", err)
	}
	if len(bridges) != 2 || bridges[0].RouteID != "recorder-gateway" || bridges[0].VirtioSocketPort != 18090 || bridges[0].TargetTCPAddress != "127.0.0.1:8090" {
		t.Fatalf("parsed public service bridges = %#v", bridges)
	}
}

func TestParseGuestPublicServiceVirtioSocketBridgeArgumentsRejectsGuestIPAddressAndDuplicateRoute(t *testing.T) {
	_, err := parseGuestPublicServiceVirtioSocketBridgeArguments(guestPublicServiceVirtioSocketBridgeArguments{"recorder-gateway,18090,192.168.64.2:8090"})
	if err == nil || !strings.Contains(err.Error(), "127.0.0.1") {
		t.Fatalf("Guest IP target error = %v", err)
	}
	_, err = parseGuestPublicServiceVirtioSocketBridgeArguments(guestPublicServiceVirtioSocketBridgeArguments{
		"recorder-gateway,18090,127.0.0.1:8090",
		"recorder-gateway,18088,127.0.0.1:8088",
	})
	if err == nil || !strings.Contains(err.Error(), "duplicated") {
		t.Fatalf("duplicate route error = %v", err)
	}
}
