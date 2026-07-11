package platform

import (
	"testing"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func TestOrderedServicesPreservesEveryRoleAndExplicitUnavailable(t *testing.T) {
	runtimeProvider := "runtime-provider.service"
	bindings := map[string]*string{
		"runtime-provider": runtimeProviderPointer(runtimeProvider),
		"public-proxy":     nil,
		"log-sync":         nil,
		"sleep-prevention": nil,
		"watchdog":         nil,
	}
	services := orderedServices(bindings, func(role, _ string) contract.PlatformServiceStatus {
		return contract.PlatformServiceStatus{Role: role, State: "running"}
	})
	if len(services) != 5 {
		t.Fatalf("service count=%d", len(services))
	}
	if services[0].Role != "runtime-provider" || services[0].State != "running" {
		t.Fatalf("runtime provider mapping=%+v", services[0])
	}
	for _, service := range services[1:] {
		if service.State != "unavailable" || service.ReadError == nil {
			t.Fatalf("unavailable role must preserve reason: %+v", service)
		}
	}
}

func runtimeProviderPointer(value string) *string {
	return &value
}
