package systemdhostproductservicereconciliation

import (
	"context"
	"errors"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type commandRunnerFake struct {
	results map[string]CommandResult
	errors  map[string]error
}

func (fake commandRunnerFake) RunSystemdHostServiceCommand(_ context.Context, executable string, arguments ...string) (CommandResult, error) {
	key := executable
	for _, argument := range arguments {
		key += "|" + argument
	}
	if err := fake.errors[key]; err != nil {
		return CommandResult{}, err
	}
	return fake.results[key], nil
}

func TestReconcileReloadsThenEnablesOnlyDeclaredLinuxServices(t *testing.T) {
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "linux", RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
		{Role: "host-agent", Manager: "systemd", Name: "vitalserver-host-agent.service"},
		{Role: "host-edge-proxy", Manager: "systemd", Name: "vitalserver-host-edge-proxy.service"},
	}}
	reconciler, err := NewSystemdHostProductServiceReconcilerWithCommandRunner("systemctl", commandRunnerFake{results: map[string]CommandResult{
		"systemctl|daemon-reload":                                    {ExitCode: 0},
		"systemctl|enable|--now|vitalserver-host-agent.service":      {ExitCode: 0},
		"systemctl|enable|--now|vitalserver-host-edge-proxy.service": {ExitCode: 0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := reconciler.ReconcileHostProductServices(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
}

func TestReconcileKeepsSystemdCommandFailureExplicit(t *testing.T) {
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "linux"}
	reconciler, err := NewSystemdHostProductServiceReconcilerWithCommandRunner("systemctl", commandRunnerFake{errors: map[string]error{
		"systemctl|daemon-reload": errors.New("permission denied"),
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := reconciler.ReconcileHostProductServices(context.Background(), manifest); err == nil {
		t.Fatal("expected systemctl failure")
	}
}
