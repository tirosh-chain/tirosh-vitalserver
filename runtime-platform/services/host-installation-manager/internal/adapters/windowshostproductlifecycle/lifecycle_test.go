package windowshostproductlifecycle

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type commandRunnerFake struct {
	results map[string]CommandResult
	calls   []string
}

func (fake *commandRunnerFake) RunWindowsHostProductLifecycleCommand(_ context.Context, executable string, arguments ...string) (CommandResult, error) {
	key := executable
	for _, argument := range arguments {
		key += "|" + argument
	}
	fake.calls = append(fake.calls, key)
	return fake.results[key], nil
}

func TestQuiesceHostProductServicesRequiresObservedStoppedState(t *testing.T) {
	service := hostinstallationmanagerdomain.HostProductRequiredService{Role: "host-agent", Manager: "windows-scm", Name: "vitalserver-host-agent", WindowsSCMRegistration: &hostinstallationmanagerdomain.HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-agent.exe`, StartMode: "automatic", Account: "LocalSystem"}}
	runner := &commandRunnerFake{results: map[string]CommandResult{
		"sc.exe|stop|vitalserver-host-agent":  {},
		"sc.exe|query|vitalserver-host-agent": {Stdout: "STATE              : 1  STOPPED\n"},
	}}
	lifecycle, err := NewWindowsHostProductLifecycleWithCommandRunner("cmd.exe", "sc.exe", runner, func(context.Context) error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "windows", Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{ReferenceKind: "directory-junction"}, RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{service}}
	if err := lifecycle.QuiesceHostProductServices(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
}

func TestReconcileHostProductServicesDoesNotTreatStartedAsRunning(t *testing.T) {
	service := hostinstallationmanagerdomain.HostProductRequiredService{Role: "host-agent", Manager: "windows-scm", Name: "vitalserver-host-agent", WindowsSCMRegistration: &hostinstallationmanagerdomain.HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-agent.exe`, StartMode: "automatic", Account: "LocalSystem"}}
	commandLine := `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-agent.exe`
	runner := &commandRunnerFake{results: map[string]CommandResult{
		"sc.exe|create|vitalserver-host-agent|binPath=|" + commandLine + "|start=|auto|obj=|LocalSystem": {},
		"sc.exe|start|vitalserver-host-agent": {},
		"sc.exe|query|vitalserver-host-agent": {Stdout: "STATE              : 2  START_PENDING\n"},
	}}
	lifecycle, err := NewWindowsHostProductLifecycleWithCommandRunner("cmd.exe", "sc.exe", runner, func(context.Context) error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "windows", Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{ReferenceKind: "directory-junction"}, RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{service}}
	if err := lifecycle.ReconcileHostProductServices(context.Background(), manifest); err == nil {
		t.Fatal("expected a non-running SCM service to remain an error")
	}
}
