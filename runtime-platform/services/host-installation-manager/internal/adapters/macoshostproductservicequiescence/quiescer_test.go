package macoshostproductservicequiescence

import (
	"context"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type hostServiceQuiescenceCall struct {
	executable string
	arguments  []string
}

type hostServiceQuiescenceCommandRunnerFake struct {
	results []HostServiceQuiescenceCommandResult
	calls   []hostServiceQuiescenceCall
	err     error
}

func (fake *hostServiceQuiescenceCommandRunnerFake) RunHostServiceQuiescenceCommand(_ context.Context, executable string, arguments ...string) (HostServiceQuiescenceCommandResult, error) {
	fake.calls = append(fake.calls, hostServiceQuiescenceCall{executable: executable, arguments: arguments})
	if fake.err != nil {
		return HostServiceQuiescenceCommandResult{}, fake.err
	}
	index := len(fake.calls) - 1
	if index >= len(fake.results) {
		return HostServiceQuiescenceCommandResult{}, nil
	}
	return fake.results[index], nil
}

func quiescenceManifest() hostinstallationmanagerdomain.HostProductInstallationManifest {
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		Platform: "macos",
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent"},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy"},
		},
	}
}

func TestQuiesceHostProductServicesStopsOnlyDeclaredLaunchdServices(t *testing.T) {
	runner := &hostServiceQuiescenceCommandRunnerFake{results: []HostServiceQuiescenceCommandResult{{ExitCode: 0}, {ExitCode: 3}}}
	quiescer, err := NewMacOSHostProductServiceQuiescerWithCommandRunner("/bin/launchctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	if err := quiescer.QuiesceHostProductServices(context.Background(), quiescenceManifest()); err != nil {
		t.Fatal(err)
	}
	if len(runner.calls) != 2 {
		t.Fatalf("calls=%+v", runner.calls)
	}
	if runner.calls[0].executable != "/bin/launchctl" || strings.Join(runner.calls[0].arguments, " ") != "bootout system/com.tirosh.vitalserver.host-agent" || strings.Join(runner.calls[1].arguments, " ") != "bootout system/com.tirosh.vitalserver.host-edge-proxy" {
		t.Fatalf("calls=%+v", runner.calls)
	}
}

func TestQuiesceHostProductServicesReportsUnexpectedLaunchctlStatus(t *testing.T) {
	runner := &hostServiceQuiescenceCommandRunnerFake{results: []HostServiceQuiescenceCommandResult{{ExitCode: 75, Stderr: "temporary failure"}}}
	quiescer, err := NewMacOSHostProductServiceQuiescerWithCommandRunner("/bin/launchctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	err = quiescer.QuiesceHostProductServices(context.Background(), quiescenceManifest())
	if err == nil || !strings.Contains(err.Error(), "status 75") {
		t.Fatalf("err=%v", err)
	}
}
