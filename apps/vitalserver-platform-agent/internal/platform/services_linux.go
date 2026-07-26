//go:build linux

package platform

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/coreos/go-systemd/v22/dbus"
	godbus "github.com/godbus/dbus/v5"
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

func (observer ServiceObserver) ControlRuntimeProvider(ctx context.Context, action provider.Action) error {
	if err := provider.ValidateAction(action); err != nil {
		return provider.EffectError{Kind: "invalid-action", Message: err.Error()}
	}
	name := observer.bindings["runtime-provider"]
	if name == nil {
		return provider.EffectError{Kind: "runtime-provider-unavailable", Message: "Linux Runtime Provider service binding is unavailable."}
	}
	controlContext, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	connection, err := dbus.NewSystemConnectionContext(controlContext)
	if err != nil {
		return linuxRuntimeProviderEffectError("systemd connection failed", err)
	}
	defer connection.Close()
	result := make(chan string, 1)
	switch action {
	case provider.ActionStart:
		_, err = connection.StartUnitContext(controlContext, *name, "replace", result)
	case provider.ActionStop:
		_, err = connection.StopUnitContext(controlContext, *name, "replace", result)
	case provider.ActionRestart:
		_, err = connection.RestartUnitContext(controlContext, *name, "replace", result)
	}
	if err != nil {
		return linuxRuntimeProviderEffectError(fmt.Sprintf("systemd %s request failed service=%s", action, *name), err)
	}
	select {
	case state := <-result:
		if state != "done" {
			return provider.EffectError{
				Kind:    "runtime-provider-control-failed",
				Message: fmt.Sprintf("systemd %s job failed service=%s result=%s", action, *name, state),
			}
		}
		return nil
	case <-controlContext.Done():
		return provider.EffectError{
			Kind:    "runtime-provider-control-timeout",
			Message: fmt.Sprintf("systemd %s job timed out service=%s reason=%v", action, *name, controlContext.Err()),
		}
	}
}

func linuxRuntimeProviderEffectError(stage string, err error) provider.EffectError {
	kind := "runtime-provider-control-failed"
	var dbusError godbus.Error
	if errors.As(err, &dbusError) {
		switch dbusError.Name {
		case "org.freedesktop.DBus.Error.AccessDenied":
			kind = "permission-denied"
		case "org.freedesktop.systemd1.NoSuchUnit":
			kind = "runtime-provider-not-installed"
		}
	}
	return provider.EffectError{Kind: kind, Message: fmt.Sprintf("%s reason=%v", stage, err)}
}

func (observer ServiceObserver) ReadPlatformServices() ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, err := dbus.NewSystemConnectionContext(ctx)
	if err != nil {
		return observer.connectionFailure(err)
	}
	defer connection.Close()

	names := make([]string, 0, len(observer.bindings))
	for _, name := range observer.bindings {
		if name != nil {
			names = append(names, *name)
		}
	}
	units, err := connection.ListUnitsByNamesContext(ctx, names)
	if err != nil {
		return observer.connectionFailure(err)
	}
	byName := make(map[string]dbus.UnitStatus, len(units))
	for _, unit := range units {
		byName[unit.Name] = unit
	}
	services := orderedServices(observer.bindings, func(role, name string) contract.PlatformServiceStatus {
		unit, exists := byName[name]
		if !exists || unit.LoadState == "not-found" {
			return contract.PlatformServiceStatus{Role: role, State: "not-installed"}
		}
		if unit.LoadState != "loaded" {
			return failedService(role, "failed", fmt.Sprintf("systemd load state=%s", unit.LoadState))
		}
		switch unit.ActiveState {
		case "active", "activating", "reloading":
			return contract.PlatformServiceStatus{Role: role, State: "running"}
		case "inactive", "deactivating":
			return contract.PlatformServiceStatus{Role: role, State: "stopped"}
		case "failed":
			return failedService(role, "failed", "systemd unit is failed")
		default:
			return unavailableService(role, fmt.Sprintf("unsupported systemd active state=%s", unit.ActiveState))
		}
	})
	return services, []contract.ReadIssue{}
}

func (observer ServiceObserver) connectionFailure(err error) ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	state := "read-failed"
	var dbusError godbus.Error
	if errors.As(err, &dbusError) && dbusError.Name == "org.freedesktop.DBus.Error.AccessDenied" {
		state = "permission-denied"
	}
	message := fmt.Sprintf("systemd service state read failed: %v", err)
	services := orderedServices(observer.bindings, func(role, _ string) contract.PlatformServiceStatus {
		return failedService(role, state, message)
	})
	return services, []contract.ReadIssue{{Source: "platform-services", Message: message}}
}
