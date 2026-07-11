//go:build windows

package platform

import (
	"context"
	"errors"
	"fmt"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"

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
	return observer.bindings["runtime-provider"] != nil
}

func (observer ServiceObserver) ControlRuntimeProvider(ctx context.Context, action provider.Action) (resultErr error) {
	if err := provider.ValidateAction(action); err != nil {
		return provider.EffectError{Kind: "invalid-action", Message: err.Error()}
	}
	name := observer.bindings["runtime-provider"]
	if name == nil {
		return provider.EffectError{Kind: "runtime-provider-unavailable", Message: "Windows Runtime Provider service binding is unavailable."}
	}
	manager, err := mgr.Connect()
	if err != nil {
		return windowsRuntimeProviderEffectError("Windows Service manager connection failed", err)
	}
	defer manager.Disconnect()
	service, err := manager.OpenService(*name)
	if err != nil {
		return windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider service open failed service=%s", *name), err)
	}
	defer func() {
		if closeErr := service.Close(); closeErr != nil && resultErr == nil {
			resultErr = windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider service handle close failed service=%s", *name), closeErr)
		}
	}()
	controlContext, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	switch action {
	case provider.ActionStart:
		return startWindowsRuntimeProvider(controlContext, service, *name)
	case provider.ActionStop:
		return stopWindowsRuntimeProvider(controlContext, service, *name)
	case provider.ActionRestart:
		if err := stopWindowsRuntimeProvider(controlContext, service, *name); err != nil {
			return err
		}
		return startWindowsRuntimeProvider(controlContext, service, *name)
	}
	return provider.EffectError{Kind: "invalid-action", Message: fmt.Sprintf("unsupported Runtime Provider action: %s", action)}
}

func startWindowsRuntimeProvider(ctx context.Context, service *mgr.Service, name string) error {
	status, err := service.Query()
	if err != nil {
		return windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider state query failed service=%s", name), err)
	}
	if status.State == svc.Running {
		return nil
	}
	if status.State == svc.StopPending {
		if err := waitWindowsRuntimeProviderState(ctx, service, name, svc.Stopped); err != nil {
			return err
		}
	}
	if err := service.Start(); err != nil {
		return windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider start failed service=%s", name), err)
	}
	return waitWindowsRuntimeProviderState(ctx, service, name, svc.Running)
}

func stopWindowsRuntimeProvider(ctx context.Context, service *mgr.Service, name string) error {
	status, err := service.Query()
	if err != nil {
		return windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider state query failed service=%s", name), err)
	}
	if status.State == svc.Stopped {
		return nil
	}
	if status.State != svc.StopPending {
		if _, err := service.Control(svc.Stop); err != nil {
			return windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider stop failed service=%s", name), err)
		}
	}
	return waitWindowsRuntimeProviderState(ctx, service, name, svc.Stopped)
}

func waitWindowsRuntimeProviderState(ctx context.Context, service *mgr.Service, name string, expected svc.State) error {
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	for {
		status, err := service.Query()
		if err != nil {
			return windowsRuntimeProviderEffectError(fmt.Sprintf("Windows Runtime Provider state query failed service=%s", name), err)
		}
		if status.State == expected {
			return nil
		}
		select {
		case <-ctx.Done():
			return provider.EffectError{
				Kind:    "runtime-provider-control-timeout",
				Message: fmt.Sprintf("Windows Runtime Provider state wait timed out service=%s expected=%d actual=%d reason=%v", name, expected, status.State, ctx.Err()),
			}
		case <-ticker.C:
		}
	}
}

func windowsRuntimeProviderEffectError(stage string, err error) provider.EffectError {
	kind := "runtime-provider-control-failed"
	switch {
	case errors.Is(err, windows.ERROR_ACCESS_DENIED):
		kind = "permission-denied"
	case errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST):
		kind = "runtime-provider-not-installed"
	}
	return provider.EffectError{Kind: kind, Message: fmt.Sprintf("%s reason=%v", stage, err)}
}

func (observer ServiceObserver) ReadPlatformServices() ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	manager, err := mgr.Connect()
	if err != nil {
		return observer.managerFailure(err)
	}
	defer manager.Disconnect()
	services := orderedServices(observer.bindings, func(role, name string) contract.PlatformServiceStatus {
		service, err := manager.OpenService(name)
		if err != nil {
			switch {
			case errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST):
				return contract.PlatformServiceStatus{Role: role, State: "not-installed"}
			case errors.Is(err, windows.ERROR_ACCESS_DENIED):
				return failedService(role, "permission-denied", fmt.Sprintf("Windows Service access denied service=%s", name))
			default:
				return failedService(role, "read-failed", fmt.Sprintf("Windows Service open failed service=%s reason=%v", name, err))
			}
		}
		status, err := service.Query()
		closeErr := service.Close()
		if err != nil {
			if errors.Is(err, windows.ERROR_ACCESS_DENIED) {
				return failedService(role, "permission-denied", fmt.Sprintf("Windows Service query access denied service=%s", name))
			}
			return failedService(role, "read-failed", fmt.Sprintf("Windows Service query failed service=%s reason=%v", name, err))
		}
		if closeErr != nil {
			return failedService(role, "read-failed", fmt.Sprintf("Windows Service handle close failed service=%s reason=%v", name, closeErr))
		}
		switch status.State {
		case svc.Running, svc.StartPending, svc.ContinuePending:
			return contract.PlatformServiceStatus{Role: role, State: "running"}
		case svc.Stopped, svc.StopPending, svc.Paused, svc.PausePending:
			return contract.PlatformServiceStatus{Role: role, State: "stopped"}
		default:
			return unavailableService(role, fmt.Sprintf("unsupported Windows Service state=%d", status.State))
		}
	})
	return services, []contract.ReadIssue{}
}

func (observer ServiceObserver) managerFailure(err error) ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	state := "read-failed"
	if errors.Is(err, windows.ERROR_ACCESS_DENIED) {
		state = "permission-denied"
	}
	message := fmt.Sprintf("Windows Service manager read failed: %v", err)
	services := orderedServices(observer.bindings, func(role, _ string) contract.PlatformServiceStatus {
		return failedService(role, state, message)
	})
	return services, []contract.ReadIssue{{Source: "platform-services", Message: message}}
}
