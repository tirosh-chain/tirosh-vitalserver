package nativeproviderbridge

import (
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"strings"
	"testing"
	"time"
)

type fixedClock struct{ value time.Time }

func (clock fixedClock) Now() time.Time { return clock.value }

type commandOutcome struct {
	output string
	err    error
}

type scriptedExecutor struct {
	outcomes map[string][]commandOutcome
	calls    []Command
}

func (executor *scriptedExecutor) Run(_ context.Context, command Command) (string, error) {
	executor.calls = append(executor.calls, command)
	key := commandKey(command)
	outcomes := executor.outcomes[key]
	if len(outcomes) == 0 {
		return "", errors.New("unexpected command: " + key)
	}
	next := outcomes[0]
	executor.outcomes[key] = outcomes[1:]
	return next.output, next.err
}

func commandKey(command Command) string {
	return command.Name + "\x00" + strings.Join(command.Args, "\x00")
}

func put(executor *scriptedExecutor, command Command, outcomes ...commandOutcome) {
	executor.outcomes[commandKey(command)] = outcomes
}

func testClock() fixedClock {
	return fixedClock{value: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
}

func invocation(kind string, action string) PlatformProviderLifecycleInvocation {
	return PlatformProviderLifecycleInvocation{
		SchemaVersion:                 SchemaVersion,
		ProviderKind:                  kind,
		RequestID:                     "platform-request-1",
		ExpectedGuestRuntimeControlEndpointRevision: 7,
		Lifecycle: ProviderLifecycleRequest{
			SchemaVersion: SchemaVersion,
			RequestID:     "platform-request-1",
			ProviderID:    "guest-vm",
			Action:        action,
		},
	}
}

func TestLinuxStartUsesOnlySelectedProviderCommandsAndReturnsObservedRunning(t *testing.T) {
	adapter := linuxAdapter{}
	config := Config{ProviderID: "guest-vm", VirtualMachine: "guest-a", ServiceName: "vitalserver-host-agent", HostPlatform: "linux"}
	executor := &scriptedExecutor{outcomes: map[string][]commandOutcome{}}
	put(executor, adapter.vmState(config), commandOutcome{output: "shut off\n"}, commandOutcome{output: "running\n"})
	put(executor, adapter.startVM(config), commandOutcome{})
	put(executor, adapter.startService(config), commandOutcome{})
	put(executor, adapter.serviceState(config), commandOutcome{output: "active\n"})

	result := ExecuteLifecycle(context.Background(), LinuxKVMlibvirtSystemdProviderKind, config, invocation(LinuxKVMlibvirtSystemdProviderKind, "start"), executor, testClock())
	if result.ObservedState != "running" || result.Issue != nil {
		t.Fatalf("lifecycle result = %+v", result)
	}
	for _, call := range executor.calls {
		if call.Name == "powershell.exe" {
			t.Fatalf("linux provider attempted a Windows fallback: %+v", call)
		}
	}
}

func TestWindowsStartUsesEscapedHyperVAndSCMCommands(t *testing.T) {
	adapter := windowsAdapter{}
	config := Config{ProviderID: "guest-vm", VirtualMachine: "guest'vm", ServiceName: "VitalServerHostAgent", HostPlatform: "windows"}
	executor := &scriptedExecutor{outcomes: map[string][]commandOutcome{}}
	put(executor, adapter.vmState(config), commandOutcome{output: "Off"}, commandOutcome{output: "Running"})
	put(executor, adapter.startVM(config), commandOutcome{})
	put(executor, adapter.startService(config), commandOutcome{})
	put(executor, adapter.serviceState(config), commandOutcome{output: "Running"})

	result := ExecuteLifecycle(context.Background(), WindowsHyperVSCMProviderKind, config, invocation(WindowsHyperVSCMProviderKind, "start"), executor, testClock())
	if result.ObservedState != "running" || result.Issue != nil {
		t.Fatalf("lifecycle result = %+v", result)
	}
	if len(executor.calls) == 0 || executor.calls[0].Name != "powershell.exe" || !strings.Contains(strings.Join(executor.calls[0].Args, " "), "guest''vm") {
		t.Fatalf("Windows command did not safely quote VM name: %+v", executor.calls)
	}
	for _, call := range executor.calls {
		if call.Name == "virsh" || call.Name == "systemctl" {
			t.Fatalf("Windows provider attempted a Linux fallback: %+v", call)
		}
	}
}

func TestSelectedProviderFailureDoesNotTryAnotherProvider(t *testing.T) {
	adapter := linuxAdapter{}
	config := Config{ProviderID: "guest-vm", VirtualMachine: "guest-a", ServiceName: "vitalserver-host-agent", HostPlatform: "linux"}
	executor := &scriptedExecutor{outcomes: map[string][]commandOutcome{}}
	put(executor, adapter.vmState(config), commandOutcome{output: "shut off"})
	put(executor, adapter.startVM(config), commandOutcome{err: errors.New("libvirt rejected start")})

	result := ExecuteLifecycle(context.Background(), LinuxKVMlibvirtSystemdProviderKind, config, invocation(LinuxKVMlibvirtSystemdProviderKind, "start"), executor, testClock())
	if result.ObservedState != "failed" || result.Issue == nil || result.Issue.Code != "linux-kvm-libvirt-systemd-command-failed" {
		t.Fatalf("lifecycle result = %+v", result)
	}
	for _, call := range executor.calls {
		if call.Name == "powershell.exe" {
			t.Fatalf("failed Linux provider attempted Windows fallback: %+v", call)
		}
	}
}

func TestWrongHostPlatformIsTypedUnavailableWithoutCommandExecution(t *testing.T) {
	config := Config{ProviderID: "guest-vm", VirtualMachine: "guest-a", ServiceName: "vitalserver-host-agent", HostPlatform: "macos"}
	executor := &scriptedExecutor{outcomes: map[string][]commandOutcome{}}
	result := ExecuteLifecycle(context.Background(), LinuxKVMlibvirtSystemdProviderKind, config, invocation(LinuxKVMlibvirtSystemdProviderKind, "start"), executor, testClock())
	if result.ObservedState != "unavailable" || result.Issue == nil || result.Issue.Code != "linux-kvm-libvirt-systemd-host-platform-mismatch" {
		t.Fatalf("lifecycle result = %+v", result)
	}
	if len(executor.calls) != 0 {
		t.Fatalf("wrong-platform provider executed commands: %+v", executor.calls)
	}
}

func TestRequestAndRevisionMismatchDoesNotExecuteEffect(t *testing.T) {
	config := Config{ProviderID: "guest-vm", VirtualMachine: "guest-a", ServiceName: "vitalserver-host-agent", HostPlatform: "linux"}
	command := invocation(LinuxKVMlibvirtSystemdProviderKind, "start")
	command.Lifecycle.RequestID = "different-request"
	executor := &scriptedExecutor{outcomes: map[string][]commandOutcome{}}
	result := ExecuteLifecycle(context.Background(), LinuxKVMlibvirtSystemdProviderKind, config, command, executor, testClock())
	if result.ObservedState != "failed" || result.Issue == nil || result.Issue.Code != "platform-provider-invocation-invalid" {
		t.Fatalf("lifecycle result = %+v", result)
	}
	if len(executor.calls) != 0 {
		t.Fatalf("invalid invocation executed commands: %+v", executor.calls)
	}
}

func TestInstallationEvidenceReportsComponentsAndNeverCollapsesCommandUnavailable(t *testing.T) {
	adapter := linuxAdapter{}
	config := Config{ProviderID: "guest-vm", VirtualMachine: "guest-a", ServiceName: "vitalserver-host-agent", HostPlatform: "linux"}
	executor := &scriptedExecutor{outcomes: map[string][]commandOutcome{}}
	put(executor, adapter.vmState(config), commandOutcome{output: "running"})
	put(executor, adapter.serviceState(config), commandOutcome{err: exec.ErrNotFound})

	evidence := InspectInstallation(context.Background(), LinuxKVMlibvirtSystemdProviderKind, config, executor, testClock())
	if evidence.Installation.State != "unavailable" || evidence.VirtualMachine.State != "running" || evidence.Service.State != "unavailable" || evidence.Service.Issue == nil {
		t.Fatalf("installation evidence = %+v", evidence)
	}
	encoded, err := json.Marshal(evidence)
	if err != nil || len(encoded) == 0 {
		t.Fatalf("C22 evidence does not encode: bytes=%q err=%v", encoded, err)
	}
}
