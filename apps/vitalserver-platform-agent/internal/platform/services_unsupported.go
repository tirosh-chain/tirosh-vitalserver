//go:build !linux && !windows

package platform

import (
	"context"
	"fmt"
	"runtime"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

type ServiceObserver struct {
	bindings map[string]*string
}

func NewServiceObserver(bindings map[string]*string) ServiceObserver {
	return ServiceObserver{bindings: bindings}
}

func (observer ServiceObserver) RuntimeProviderControlAvailable() bool {
	return false
}

func (observer ServiceObserver) ControlRuntimeProvider(_ context.Context, _ provider.Action) error {
	message := fmt.Sprintf("%s Runtime Provider control adapter is unavailable", runtime.GOOS)
	return provider.EffectError{Kind: "runtime-provider-unavailable", Message: message}
}

func (observer ServiceObserver) ReadPlatformServices() ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	message := fmt.Sprintf("%s service adapter is unavailable", runtime.GOOS)
	services := orderedServices(observer.bindings, func(role, _ string) contract.PlatformServiceStatus {
		return unavailableService(role, message)
	})
	return services, []contract.ReadIssue{{Source: "platform-services", Message: message}}
}
