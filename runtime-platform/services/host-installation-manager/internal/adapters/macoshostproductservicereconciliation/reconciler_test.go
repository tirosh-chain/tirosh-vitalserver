package macoshostproductservicereconciliation

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type hostServiceReconciliationCall struct {
	executable string
	arguments  []string
}

type hostServiceReconciliationRunnerFake struct {
	calls   []hostServiceReconciliationCall
	results map[string]HostServiceReconciliationCommandResult
	errors  map[string]error
}

func (fake *hostServiceReconciliationRunnerFake) RunHostServiceReconciliationCommand(_ context.Context, executable string, arguments ...string) (HostServiceReconciliationCommandResult, error) {
	fake.calls = append(fake.calls, hostServiceReconciliationCall{executable: executable, arguments: append([]string(nil), arguments...)})
	key := executable + "|" + strings.Join(arguments, "|")
	if err := fake.errors[key]; err != nil {
		return HostServiceReconciliationCommandResult{}, err
	}
	return fake.results[key], nil
}

func reconciledHostProductManifest() hostinstallationmanagerdomain.HostProductInstallationManifest {
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		Platform: "macos",
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist"},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist"},
			{Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist"},
		},
	}
}

func TestReconcileHostProductServicesBootsOutThenBootstrapsEveryDeclaredService(t *testing.T) {
	runner := &hostServiceReconciliationRunnerFake{results: map[string]HostServiceReconciliationCommandResult{
		"launchctl|bootout|system/com.tirosh.vitalserver.host-agent":                                                    {ExitCode: 113, Stderr: "Bad request.\nCould not find service \"com.tirosh.vitalserver.host-agent\" in domain for system\n"},
		"launchctl|bootstrap|system|/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist":                     {},
		"launchctl|bootout|system/com.tirosh.vitalserver.host-edge-proxy":                                               {ExitCode: 0},
		"launchctl|bootstrap|system|/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist":                {},
		"launchctl|bootout|system/com.tirosh.vitalserver.host-update-handoff-supervisor":                                {ExitCode: 113, Stderr: "Bad request.\nCould not find service \"com.tirosh.vitalserver.host-update-handoff-supervisor\" in domain for system\n"},
		"launchctl|bootstrap|system|/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist": {},
	}}
	reconciler, err := NewMacOSHostProductServiceReconcilerWithCommandRunner("launchctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	if err := reconciler.ReconcileHostProductServices(context.Background(), reconciledHostProductManifest()); err != nil {
		t.Fatal(err)
	}
	if len(runner.calls) != 6 {
		t.Fatalf("calls=%+v", runner.calls)
	}
	want := [][]string{
		{"bootout", "system/com.tirosh.vitalserver.host-agent"},
		{"bootstrap", "system", "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist"},
		{"bootout", "system/com.tirosh.vitalserver.host-edge-proxy"},
		{"bootstrap", "system", "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist"},
		{"bootout", "system/com.tirosh.vitalserver.host-update-handoff-supervisor"},
		{"bootstrap", "system", "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist"},
	}
	for index, call := range runner.calls {
		if call.executable != "launchctl" || strings.Join(call.arguments, "|") != strings.Join(want[index], "|") {
			t.Fatalf("call[%d]=%+v want=%v", index, call, want[index])
		}
	}
}

func TestReconcileHostProductServicesRejectsAmbiguousMacOS26BootoutFailure(t *testing.T) {
	runner := &hostServiceReconciliationRunnerFake{results: map[string]HostServiceReconciliationCommandResult{
		"launchctl|bootout|system/com.tirosh.vitalserver.host-agent": {ExitCode: 113, Stderr: "launchctl transport temporarily unavailable"},
	}}
	reconciler, err := NewMacOSHostProductServiceReconcilerWithCommandRunner("launchctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	err = reconciler.ReconcileHostProductServices(context.Background(), reconciledHostProductManifest())
	if err == nil || !strings.Contains(err.Error(), "status 113") {
		t.Fatalf("err=%v", err)
	}
}

func TestReconcileHostProductServicesReportsBootstrapFailure(t *testing.T) {
	runner := &hostServiceReconciliationRunnerFake{results: map[string]HostServiceReconciliationCommandResult{
		"launchctl|bootout|system/com.tirosh.vitalserver.host-agent":                                {},
		"launchctl|bootstrap|system|/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist": {ExitCode: 1, Stderr: "invalid plist"},
	}}
	reconciler, err := NewMacOSHostProductServiceReconcilerWithCommandRunner("launchctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	err = reconciler.ReconcileHostProductServices(context.Background(), reconciledHostProductManifest())
	if err == nil || !strings.Contains(err.Error(), "bootstrap declared Host service") {
		t.Fatalf("err=%v", err)
	}
}

func TestReconcileHostProductServicesReportsCommandStartFailure(t *testing.T) {
	runner := &hostServiceReconciliationRunnerFake{errors: map[string]error{
		"launchctl|bootout|system/com.tirosh.vitalserver.host-agent": errors.New("permission denied"),
	}}
	reconciler, err := NewMacOSHostProductServiceReconcilerWithCommandRunner("launchctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	err = reconciler.ReconcileHostProductServices(context.Background(), reconciledHostProductManifest())
	if err == nil || !strings.Contains(err.Error(), "permission denied") {
		t.Fatalf("err=%v", err)
	}
}
