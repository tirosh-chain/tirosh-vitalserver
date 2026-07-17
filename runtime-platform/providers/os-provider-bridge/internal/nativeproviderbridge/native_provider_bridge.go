package nativeproviderbridge

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

type Command struct {
	Name string
	Args []string
}

// Executor is the sole side-effect port. Tests supply explicit command
// outcomes; the domain-like mapping below never reads process output itself.
type Executor interface {
	Run(context.Context, Command) (string, error)
}

type SystemExecutor struct{}

func (SystemExecutor) Run(ctx context.Context, command Command) (string, error) {
	output, err := exec.CommandContext(ctx, command.Name, command.Args...).Output()
	if err != nil {
		return "", fmt.Errorf("execute %s: %w", command.Name, err)
	}
	return string(output), nil
}

type nativeAdapter interface {
	kind() string
	hostPlatform() string
	serviceManager() string
	vmState(Config) Command
	serviceState(Config) Command
	startVM(Config) Command
	stopVM(Config) Command
	rebootVM(Config) Command
	startService(Config) Command
	stopService(Config) Command
	restartService(Config) Command
	parseVMState(string) (string, bool)
	parseServiceState(string) (string, bool)
}

type linuxAdapter struct{}

func (linuxAdapter) kind() string           { return LinuxKVMlibvirtSystemdProviderKind }
func (linuxAdapter) hostPlatform() string   { return "linux" }
func (linuxAdapter) serviceManager() string { return "systemd" }
func (linuxAdapter) vmState(config Config) Command {
	return Command{Name: "virsh", Args: []string{"domstate", config.VirtualMachine}}
}
func (linuxAdapter) serviceState(config Config) Command {
	return Command{Name: "systemctl", Args: []string{"is-active", config.ServiceName}}
}
func (linuxAdapter) startVM(config Config) Command {
	return Command{Name: "virsh", Args: []string{"start", config.VirtualMachine}}
}
func (linuxAdapter) stopVM(config Config) Command {
	return Command{Name: "virsh", Args: []string{"shutdown", config.VirtualMachine}}
}
func (linuxAdapter) rebootVM(config Config) Command {
	return Command{Name: "virsh", Args: []string{"reboot", config.VirtualMachine}}
}
func (linuxAdapter) startService(config Config) Command {
	return Command{Name: "systemctl", Args: []string{"start", config.ServiceName}}
}
func (linuxAdapter) stopService(config Config) Command {
	return Command{Name: "systemctl", Args: []string{"stop", config.ServiceName}}
}
func (linuxAdapter) restartService(config Config) Command {
	return Command{Name: "systemctl", Args: []string{"restart", config.ServiceName}}
}
func (linuxAdapter) parseVMState(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "running":
		return "running", true
	case "shut off", "shutoff", "off":
		return "stopped", true
	default:
		return "", false
	}
}
func (linuxAdapter) parseServiceState(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "active":
		return "running", true
	case "inactive":
		return "stopped", true
	default:
		return "", false
	}
}

type windowsAdapter struct{}

func (windowsAdapter) kind() string           { return WindowsHyperVSCMProviderKind }
func (windowsAdapter) hostPlatform() string   { return "windows" }
func (windowsAdapter) serviceManager() string { return "windows-scm" }
func powershell(script string) Command {
	return Command{Name: "powershell.exe", Args: []string{"-NoProfile", "-NonInteractive", "-Command", script}}
}
func powershellQuoted(value string) string { return "'" + strings.ReplaceAll(value, "'", "''") + "'" }
func (windowsAdapter) vmState(config Config) Command {
	return powershell("$vm = Get-VM -Name " + powershellQuoted(config.VirtualMachine) + " -ErrorAction Stop; [Console]::Out.Write($vm.State.ToString())")
}
func (windowsAdapter) serviceState(config Config) Command {
	return powershell("$service = Get-Service -Name " + powershellQuoted(config.ServiceName) + " -ErrorAction Stop; [Console]::Out.Write($service.Status.ToString())")
}
func (windowsAdapter) startVM(config Config) Command {
	return powershell("Start-VM -Name " + powershellQuoted(config.VirtualMachine) + " -ErrorAction Stop")
}
func (windowsAdapter) stopVM(config Config) Command {
	return powershell("Stop-VM -Name " + powershellQuoted(config.VirtualMachine) + " -Force -ErrorAction Stop")
}
func (windowsAdapter) rebootVM(config Config) Command {
	return powershell("Restart-VM -Name " + powershellQuoted(config.VirtualMachine) + " -Force -ErrorAction Stop")
}
func (windowsAdapter) startService(config Config) Command {
	return powershell("Start-Service -Name " + powershellQuoted(config.ServiceName) + " -ErrorAction Stop")
}
func (windowsAdapter) stopService(config Config) Command {
	return powershell("Stop-Service -Name " + powershellQuoted(config.ServiceName) + " -ErrorAction Stop")
}
func (windowsAdapter) restartService(config Config) Command {
	return powershell("Restart-Service -Name " + powershellQuoted(config.ServiceName) + " -ErrorAction Stop")
}
func (windowsAdapter) parseVMState(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "running":
		return "running", true
	case "off":
		return "stopped", true
	default:
		return "", false
	}
}
func (windowsAdapter) parseServiceState(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "running":
		return "running", true
	case "stopped":
		return "stopped", true
	default:
		return "", false
	}
}

func selectedAdapter(kind string) (nativeAdapter, bool) {
	switch kind {
	case LinuxKVMlibvirtSystemdProviderKind:
		return linuxAdapter{}, true
	case WindowsHyperVSCMProviderKind:
		return windowsAdapter{}, true
	default:
		return nil, false
	}
}

type observation struct {
	state string
	issue *Issue
}

func (result observation) usable() bool { return result.issue == nil }

func ExecuteLifecycle(ctx context.Context, kind string, config Config, invocation PlatformProviderLifecycleInvocation, executor Executor, clock Clock) ProviderLifecycleResult {
	request := invocation.Lifecycle
	if issue := validateInvocation(kind, invocation); issue != nil {
		return failedResult(request, clock, *issue)
	}
	adapter, _ := selectedAdapter(kind)
	if issue := validateConfig(adapter, config); issue != nil {
		return unavailableResult(request, clock, *issue)
	}
	if request.ProviderID != config.ProviderID {
		return failedResult(request, clock, Issue{Code: "platform-provider-invocation-invalid", Message: "C21 lifecycle providerId does not match selected native Platform Provider configuration", Retryable: boolPointer(false), Dependency: kind})
	}

	initialVM := observeVM(ctx, adapter, config, executor)
	if !initialVM.usable() {
		return lifecycleObservationFailure(request, clock, *initialVM.issue)
	}

	var effect Command
	switch request.Action {
	case "start":
		if initialVM.state == "stopped" {
			effect = adapter.startVM(config)
			if issue := runEffect(ctx, adapter, executor, effect, "vm-start"); issue != nil {
				return lifecycleObservationFailure(request, clock, *issue)
			}
		}
		if issue := runEffect(ctx, adapter, executor, adapter.startService(config), "service-start"); issue != nil {
			return lifecycleObservationFailure(request, clock, *issue)
		}
	case "stop":
		if issue := runEffect(ctx, adapter, executor, adapter.stopService(config), "service-stop"); issue != nil {
			return lifecycleObservationFailure(request, clock, *issue)
		}
		if initialVM.state == "running" {
			if issue := runEffect(ctx, adapter, executor, adapter.stopVM(config), "vm-stop"); issue != nil {
				return lifecycleObservationFailure(request, clock, *issue)
			}
		}
	case "reboot":
		if issue := runEffect(ctx, adapter, executor, adapter.rebootVM(config), "vm-reboot"); issue != nil {
			return lifecycleObservationFailure(request, clock, *issue)
		}
		if issue := runEffect(ctx, adapter, executor, adapter.restartService(config), "service-restart"); issue != nil {
			return lifecycleObservationFailure(request, clock, *issue)
		}
	}

	vm := observeVM(ctx, adapter, config, executor)
	if !vm.usable() {
		return lifecycleObservationFailure(request, clock, *vm.issue)
	}
	service := observeService(ctx, adapter, config, executor)
	if !service.usable() {
		return lifecycleObservationFailure(request, clock, *service.issue)
	}
	if vm.state == "running" && service.state == "running" {
		return observedResult(request, clock, "running")
	}
	if vm.state == "stopped" && service.state == "stopped" {
		return observedResult(request, clock, "stopped")
	}
	return unavailableResult(request, clock, Issue{
		Code:       kind + "-component-state-inconsistent",
		Message:    "selected provider observed VM and Host service in different lifecycle states",
		Retryable:  boolPointer(true),
		Dependency: kind,
	})
}

func InspectInstallation(ctx context.Context, kind string, config Config, executor Executor, clock Clock) ProviderInstallationEvidence {
	observedAt := timestamp(clock)
	evidence := ProviderInstallationEvidence{
		SchemaVersion: SchemaVersion,
		ProviderKind:  kind,
		ProviderID:    config.ProviderID,
		HostPlatform:  config.HostPlatform,
		ObservedAt:    observedAt,
	}
	adapter, selected := selectedAdapter(kind)
	if !selected {
		issue := Issue{Code: "provider-kind-unsupported", Message: "provider kind is not implemented by this bridge executable", Retryable: boolPointer(false), Dependency: "platform-provider"}
		return unavailableEvidence(evidence, "unknown", issue)
	}
	if issue := validateConfig(adapter, config); issue != nil {
		return unavailableEvidence(evidence, adapter.serviceManager(), *issue)
	}
	vm := observeVM(ctx, adapter, config, executor)
	service := observeService(ctx, adapter, config, executor)
	evidence.VirtualMachine = ComponentObservation{State: vm.state, ObservedAt: observedAt, Issue: vm.issue}
	evidence.Service = ServiceObservation{Manager: adapter.serviceManager(), State: service.state, ObservedAt: observedAt, Issue: service.issue}
	evidence.Capabilities = []CapabilityObservation{
		capability("guest-vm-lifecycle", vm, observedAt),
		capability("host-service-lifecycle", service, observedAt),
	}
	if vm.usable() && service.usable() {
		evidence.Installation = InstallationObservation{State: "installed", ObservedAt: observedAt}
		return evidence
	}
	issue := firstIssue(vm.issue, service.issue)
	evidence.Installation = InstallationObservation{State: installationFailureState(issue), ObservedAt: observedAt, Issue: issue}
	return evidence
}

func validateInvocation(kind string, invocation PlatformProviderLifecycleInvocation) *Issue {
	request := invocation.Lifecycle
	if invocation.SchemaVersion != SchemaVersion || invocation.ProviderKind != kind || invocation.RequestID == "" || invocation.ExpectedGuestRuntimeControlEndpointRevision < 1 || request.SchemaVersion != SchemaVersion || request.RequestID != invocation.RequestID || request.ProviderID == "" {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "C21 invocation identity, selected provider, requestId, revision, and lifecycle providerId must be explicit", Retryable: boolPointer(false), Dependency: kind}
	}
	if request.Action != "start" && request.Action != "stop" && request.Action != "reboot" {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "C10 lifecycle action must be start, stop, or reboot", Retryable: boolPointer(false), Dependency: kind}
	}
	return nil
}

func validateConfig(adapter nativeAdapter, config Config) *Issue {
	if config.ProviderID == "" || config.VirtualMachine == "" || config.ServiceName == "" {
		return &Issue{Code: adapter.kind() + "-not-configured", Message: "providerId, VM name, and Host service name must be explicitly configured", Retryable: boolPointer(false), Dependency: adapter.kind()}
	}
	if config.HostPlatform != adapter.hostPlatform() {
		return &Issue{Code: adapter.kind() + "-host-platform-mismatch", Message: "selected provider cannot execute on the configured Host platform", Retryable: boolPointer(false), Dependency: adapter.kind()}
	}
	return nil
}

func observeVM(ctx context.Context, adapter nativeAdapter, config Config, executor Executor) observation {
	output, err := executor.Run(ctx, adapter.vmState(config))
	if err != nil {
		return observation{state: failureState(err), issue: commandIssue(adapter.kind(), "vm-observation", err)}
	}
	state, known := adapter.parseVMState(output)
	if !known {
		return observation{state: "failed", issue: &Issue{Code: adapter.kind() + "-vm-state-unrecognized", Message: "provider returned a VM state outside its explicit contract", Retryable: boolPointer(false), Dependency: adapter.kind()}}
	}
	return observation{state: state}
}

func observeService(ctx context.Context, adapter nativeAdapter, config Config, executor Executor) observation {
	output, err := executor.Run(ctx, adapter.serviceState(config))
	if err != nil {
		return observation{state: failureState(err), issue: commandIssue(adapter.kind(), "service-observation", err)}
	}
	state, known := adapter.parseServiceState(output)
	if !known {
		return observation{state: "failed", issue: &Issue{Code: adapter.kind() + "-service-state-unrecognized", Message: "provider returned a Host service state outside its explicit contract", Retryable: boolPointer(false), Dependency: adapter.kind()}}
	}
	return observation{state: state}
}

func runEffect(ctx context.Context, adapter nativeAdapter, executor Executor, command Command, operationContext string) *Issue {
	if _, err := executor.Run(ctx, command); err != nil {
		return commandIssue(adapter.kind(), operationContext, err)
	}
	return nil
}

func failureState(err error) string {
	if errors.Is(err, exec.ErrNotFound) {
		return "unavailable"
	}
	return "failed"
}

func commandIssue(kind string, operationContext string, err error) *Issue {
	if errors.Is(err, exec.ErrNotFound) {
		return &Issue{Code: kind + "-command-unavailable", Message: "selected provider command is unavailable during " + operationContext, Retryable: boolPointer(true), Dependency: kind}
	}
	return &Issue{Code: kind + "-command-failed", Message: "selected provider command failed during " + operationContext, Retryable: boolPointer(true), Dependency: kind}
}

func lifecycleObservationFailure(request ProviderLifecycleRequest, clock Clock, issue Issue) ProviderLifecycleResult {
	if issue.Code == "" {
		issue = Issue{Code: "provider-observation-failed", Message: "selected provider could not observe its result", Retryable: boolPointer(true)}
	}
	if strings.Contains(issue.Code, "command-unavailable") || strings.Contains(issue.Code, "not-configured") || strings.Contains(issue.Code, "platform-mismatch") {
		return unavailableResult(request, clock, issue)
	}
	return failedResult(request, clock, issue)
}

func observedResult(request ProviderLifecycleRequest, clock Clock, state string) ProviderLifecycleResult {
	return ProviderLifecycleResult{SchemaVersion: SchemaVersion, RequestID: request.RequestID, ProviderID: request.ProviderID, ObservedState: state, ObservedAt: timestamp(clock)}
}

func unavailableResult(request ProviderLifecycleRequest, clock Clock, issue Issue) ProviderLifecycleResult {
	return ProviderLifecycleResult{SchemaVersion: SchemaVersion, RequestID: request.RequestID, ProviderID: request.ProviderID, ObservedState: "unavailable", ObservedAt: timestamp(clock), Issue: &issue}
}

func failedResult(request ProviderLifecycleRequest, clock Clock, issue Issue) ProviderLifecycleResult {
	return ProviderLifecycleResult{SchemaVersion: SchemaVersion, RequestID: request.RequestID, ProviderID: request.ProviderID, ObservedState: "failed", ObservedAt: timestamp(clock), Issue: &issue}
}

func capability(id string, value observation, observedAt string) CapabilityObservation {
	if value.usable() {
		return CapabilityObservation{ID: id, State: "available", ObservedAt: observedAt}
	}
	state := "failed"
	if value.state == "unavailable" {
		state = "unavailable"
	}
	return CapabilityObservation{ID: id, State: state, ObservedAt: observedAt, Issue: value.issue}
}

func unavailableEvidence(evidence ProviderInstallationEvidence, manager string, issue Issue) ProviderInstallationEvidence {
	observedAt := evidence.ObservedAt
	evidence.Installation = InstallationObservation{State: "unavailable", ObservedAt: observedAt, Issue: &issue}
	evidence.VirtualMachine = ComponentObservation{State: "unavailable", ObservedAt: observedAt, Issue: &issue}
	evidence.Service = ServiceObservation{Manager: manager, State: "unavailable", ObservedAt: observedAt, Issue: &issue}
	evidence.Capabilities = []CapabilityObservation{
		{ID: "guest-vm-lifecycle", State: "unavailable", ObservedAt: observedAt, Issue: &issue},
		{ID: "host-service-lifecycle", State: "unavailable", ObservedAt: observedAt, Issue: &issue},
	}
	return evidence
}

func firstIssue(values ...*Issue) *Issue {
	for _, value := range values {
		if value != nil {
			return value
		}
	}
	return &Issue{Code: "provider-installation-observation-failed", Message: "selected provider installation observation has no usable evidence", Retryable: boolPointer(true)}
}

func installationFailureState(issue *Issue) string {
	if issue != nil && strings.Contains(issue.Code, "command-unavailable") {
		return "unavailable"
	}
	return "failed"
}
