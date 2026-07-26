package systemdhostproductservicequiescence

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

func linuxServiceManifest() hostinstallationmanagerdomain.HostProductInstallationManifest {
	return hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "linux", RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{{Role: "host-agent", Manager: "systemd", Name: "vitalserver-host-agent.service"}}}
}

func TestQuiesceAllowsOnlyExplicitlyAbsentSystemdUnit(t *testing.T) {
	quiescer, err := NewSystemdHostProductServiceQuiescerWithCommandRunner("systemctl", commandRunnerFake{results: map[string]CommandResult{
		"systemctl|stop|vitalserver-host-agent.service":                              {ExitCode: 5, Stderr: "Unit not found"},
		"systemctl|show|--property=LoadState|--value|vitalserver-host-agent.service": {Stdout: "not-found\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := quiescer.QuiesceHostProductServices(context.Background(), linuxServiceManifest()); err != nil {
		t.Fatal(err)
	}
}

func TestQuiesceDoesNotTurnSystemdTransportFailureIntoAbsence(t *testing.T) {
	quiescer, err := NewSystemdHostProductServiceQuiescerWithCommandRunner("systemctl", commandRunnerFake{errors: map[string]error{
		"systemctl|stop|vitalserver-host-agent.service": errors.New("permission denied"),
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := quiescer.QuiesceHostProductServices(context.Background(), linuxServiceManifest()); err == nil {
		t.Fatal("expected systemctl transport failure to remain explicit")
	}
}

func TestQuiesceRejectsFailedSystemdUnitThatIsStillKnown(t *testing.T) {
	quiescer, err := NewSystemdHostProductServiceQuiescerWithCommandRunner("systemctl", commandRunnerFake{results: map[string]CommandResult{
		"systemctl|stop|vitalserver-host-agent.service":                              {ExitCode: 1, Stderr: "access denied"},
		"systemctl|show|--property=LoadState|--value|vitalserver-host-agent.service": {Stdout: "loaded\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := quiescer.QuiesceHostProductServices(context.Background(), linuxServiceManifest()); err == nil {
		t.Fatal("expected known service stop failure")
	}
}
