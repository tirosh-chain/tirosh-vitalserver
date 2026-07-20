package nativeproviderbridge

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
		SchemaVersion: SchemaVersion,
		ProviderKind:  kind,
		RequestID:     "platform-request-1",
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

type nativeGuestProvisioningExecutor struct {
	configuration  NativeGuestMachineProvisioningConfiguration
	machinePresent bool
	calls          []Command
	domainXML      string
}

type recordingCommandExecutor struct{ calls []Command }

func (executor *recordingCommandExecutor) Run(_ context.Context, command Command) (string, error) {
	executor.calls = append(executor.calls, command)
	return "", nil
}

func (executor *nativeGuestProvisioningExecutor) Run(_ context.Context, command Command) (string, error) {
	executor.calls = append(executor.calls, command)
	if command.Name == executor.configuration.Native.LibvirtExecutablePath {
		switch strings.Join(command.Args, "\x00") {
		case "list\x00--all\x00--name":
			if executor.machinePresent {
				return executor.configuration.GuestMachine.MachineID + "\n", nil
			}
			return "", nil
		case "autostart\x00" + executor.configuration.GuestMachine.MachineID:
			return "", nil
		}
		if len(command.Args) == 2 && command.Args[0] == "define" {
			data, err := os.ReadFile(command.Args[1])
			if err != nil {
				return "", err
			}
			executor.domainXML = string(data)
			if err := os.WriteFile(executor.configuration.Native.UEFINvramPath, []byte("nvram"), 0o600); err != nil {
				return "", err
			}
			executor.machinePresent = true
			return "", nil
		}
	}
	if command.Name == executor.configuration.Native.ImageConverterExecutablePath && len(command.Args) == 7 && strings.Join(command.Args[:5], "\x00") == "convert\x00-f\x00raw\x00-O\x00qcow2" {
		return "", os.WriteFile(command.Args[6], []byte("converted "+filepath.Base(command.Args[5])), 0o600)
	}
	return "", fmt.Errorf("unexpected command: %s", commandKey(command))
}

func nativeGuestArtifact(t *testing.T, id string, path string, data []byte) NativeGuestArtifact {
	t.Helper()
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	return NativeGuestArtifact{ID: id, SourcePath: path, SizeBytes: int64(len(data)), SHA256: fmt.Sprintf("%x", sum), StorageImageFormat: "raw"}
}

func nativeGuestArtifactManifestSource(t *testing.T, path string, root NativeGuestArtifact, bootstrap NativeGuestArtifact) NativeGuestArtifactManifestSource {
	t.Helper()
	iso9660 := "iso9660"
	manifest := NativeGuestArtifactManifest{
		SchemaVersion: "v1", ArtifactSetID: "vitalserver-guest-amd64-dev", Architecture: "amd64",
		StorageDevices: []NativeGuestArtifactManifestDevice{
			{ID: root.ID, Role: "guest-root-storage", StorageImageFormat: "raw", SizeBytes: root.SizeBytes, SHA256: root.SHA256},
			{ID: bootstrap.ID, Role: "guest-product-bootstrap-volume", StorageImageFormat: "raw", GuestVolumeFileSystem: &iso9660, SizeBytes: bootstrap.SizeBytes, SHA256: bootstrap.SHA256},
		},
	}
	data, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	return NativeGuestArtifactManifestSource{SourcePath: path, SizeBytes: int64(len(data)), SHA256: fmt.Sprintf("%x", sum)}
}

func linuxNativeGuestProvisioningConfiguration(t *testing.T) (NativeGuestMachineProvisioningConfiguration, []byte) {
	t.Helper()
	directory := t.TempDir()
	root := nativeGuestArtifact(t, "guest-root", filepath.Join(directory, "release-root.raw"), []byte("bootable Guest disk"))
	bootstrap := nativeGuestArtifact(t, "guest-product-bootstrap", filepath.Join(directory, "release-bootstrap.raw"), []byte("Guest bootstrap volume"))
	manifest := nativeGuestArtifactManifestSource(t, filepath.Join(directory, "native-guest-artifact-manifest.json"), root, bootstrap)
	configuration := NativeGuestMachineProvisioningConfiguration{
		SchemaVersion: "v1", ConfigurationID: "vitalserver-linux-guest-machine", ProviderKind: LinuxKVMlibvirtSystemdProviderKind, ProviderID: "vitalserver-linux-provider", GuestArchitecture: "amd64",
		GuestMachine: NativeGuestMachine{MachineID: "vitalserver-guest", CPUCount: 2, MemoryMiB: 2048, MACAddress: "02:00:5e:10:00:21"},
		ReleaseArtifacts: NativeGuestReleaseArtifacts{
			NativeGuestArtifactManifest: manifest,
			BootableGuestDisk:           root,
			GuestProductBootstrapVolume: bootstrap,
		},
		RuntimeStorage:          NativeGuestRuntimeStorage{RootDiskPath: filepath.Join(directory, "runtime-root.qcow2"), BootstrapVolumePath: filepath.Join(directory, "runtime-bootstrap.qcow2"), ExistingRuntimeStoragePolicy: "retain-when-receipt-matches-release-artifacts"},
		Native:                  NativeGuestNativeProvider{Kind: "linux-kvm-libvirt", ImageConverterExecutablePath: "/usr/bin/qemu-img", LibvirtExecutablePath: "/usr/bin/virsh", EmulatorExecutablePath: "/usr/bin/qemu-system-x86_64", UEFILoaderPath: "/usr/share/OVMF/OVMF_CODE.fd", UEFINvramTemplatePath: "/usr/share/OVMF/OVMF_VARS.fd", UEFINvramPath: filepath.Join(directory, "runtime-vars.fd"), LibvirtNetworkName: "vitalserver-network", RuntimeImageFormat: "qcow2"},
		ProvisioningReceiptPath: filepath.Join(directory, "guest-provisioning.json"),
	}
	bytes, err := json.Marshal(configuration)
	if err != nil {
		t.Fatal(err)
	}
	return configuration, bytes
}

func TestLinuxNativeGuestProvisioningCreatesOnlyDeclaredRuntimeResourcesAndC63(t *testing.T) {
	configuration, configurationBytes := linuxNativeGuestProvisioningConfiguration(t)
	executor := &nativeGuestProvisioningExecutor{configuration: configuration}
	result, err := ProvisionNativeGuestMachine(context.Background(), LinuxKVMlibvirtSystemdProviderKind, configuration, configurationBytes, executor, testClock(), "linux")
	if err != nil {
		t.Fatal(err)
	}
	if result.Retained || result.Receipt.ConfigurationID != configuration.ConfigurationID || result.Receipt.RuntimeStorage.RuntimeImageFormat != "qcow2" {
		t.Fatalf("provision result = %+v", result)
	}
	if !strings.Contains(executor.domainXML, "<name>vitalserver-guest</name>") || !strings.Contains(executor.domainXML, configuration.RuntimeStorage.RootDiskPath) || !strings.Contains(executor.domainXML, configuration.RuntimeStorage.BootstrapVolumePath) || !strings.Contains(executor.domainXML, "network='vitalserver-network'") {
		t.Fatalf("libvirt definition does not retain C62 identity: %s", executor.domainXML)
	}
	stored, err := loadNativeGuestMachineProvisioningReceipt(configuration.ProvisioningReceiptPath)
	manifest, manifestErr := verifyNativeGuestArtifactManifest(configuration)
	if err != nil || manifestErr != nil || !matchesNativeGuestMachineReceipt(configuration, sha256Hex(configurationBytes), manifest, stored) {
		t.Fatalf("stored C63 = %+v err=%v manifestErr=%v", stored, err, manifestErr)
	}
	callCount := len(executor.calls)
	retained, err := ProvisionNativeGuestMachine(context.Background(), LinuxKVMlibvirtSystemdProviderKind, configuration, configurationBytes, executor, testClock(), "linux")
	if err != nil {
		t.Fatal(err)
	}
	if !retained.Retained || len(executor.calls) != callCount+1 {
		t.Fatalf("matching C63 did not retain native resources: result=%+v calls=%+v", retained, executor.calls)
	}
}

func TestNativeGuestProvisioningRejectsUnreceiptedRuntimeResidue(t *testing.T) {
	configuration, configurationBytes := linuxNativeGuestProvisioningConfiguration(t)
	if err := os.WriteFile(configuration.RuntimeStorage.RootDiskPath, []byte("old mutable disk"), 0o600); err != nil {
		t.Fatal(err)
	}
	executor := &nativeGuestProvisioningExecutor{configuration: configuration}
	_, err := ProvisionNativeGuestMachine(context.Background(), LinuxKVMlibvirtSystemdProviderKind, configuration, configurationBytes, executor, testClock(), "linux")
	if err == nil || !strings.Contains(err.Error(), "matching C63 receipt") {
		t.Fatalf("unreceipted native runtime residue error = %v", err)
	}
	for _, command := range executor.calls {
		if command.Name == configuration.Native.ImageConverterExecutablePath {
			t.Fatalf("unreceipted residue ran image conversion: %+v", executor.calls)
		}
	}
}

func TestNativeGuestProvisioningRejectsC65ManifestMismatchBeforeNativeEffects(t *testing.T) {
	configuration, configurationBytes := linuxNativeGuestProvisioningConfiguration(t)
	if err := os.WriteFile(configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SourcePath, []byte(`{"schemaVersion":"v1","artifactSetId":"different-release","architecture":"amd64","storageDevices":[]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	executor := &nativeGuestProvisioningExecutor{configuration: configuration}
	_, err := ProvisionNativeGuestMachine(context.Background(), LinuxKVMlibvirtSystemdProviderKind, configuration, configurationBytes, executor, testClock(), "linux")
	if err == nil || !strings.Contains(err.Error(), "C65 native Guest artifact manifest") {
		t.Fatalf("C65 manifest mismatch error = %v", err)
	}
	if len(executor.calls) != 0 {
		t.Fatalf("invalid C65 manifest executed native effects: %+v", executor.calls)
	}
}

func TestNativeGuestProvisioningRejectsC65ReleaseIdentityMismatchBeforeNativeEffects(t *testing.T) {
	configuration, _ := linuxNativeGuestProvisioningConfiguration(t)
	manifestData, err := os.ReadFile(configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SourcePath)
	if err != nil {
		t.Fatal(err)
	}
	var manifest NativeGuestArtifactManifest
	if err := json.Unmarshal(manifestData, &manifest); err != nil {
		t.Fatal(err)
	}
	manifest.StorageDevices[0].SHA256 = strings.Repeat("f", 64)
	rewrittenManifest, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SourcePath, rewrittenManifest, 0o600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(rewrittenManifest)
	configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SizeBytes = int64(len(rewrittenManifest))
	configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SHA256 = fmt.Sprintf("%x", sum)
	configurationBytes, err := json.Marshal(configuration)
	if err != nil {
		t.Fatal(err)
	}
	executor := &nativeGuestProvisioningExecutor{configuration: configuration}
	_, err = ProvisionNativeGuestMachine(context.Background(), LinuxKVMlibvirtSystemdProviderKind, configuration, configurationBytes, executor, testClock(), "linux")
	if err == nil || !strings.Contains(err.Error(), "does not match C62 release artifact guest-root") {
		t.Fatalf("C65 release identity mismatch error = %v", err)
	}
	if len(executor.calls) != 0 {
		t.Fatalf("C65-to-C62 identity mismatch executed native effects: %+v", executor.calls)
	}
}

func TestConfiguredNativeGuestMachineSelectionKeepsUnavailableAndMismatchDistinct(t *testing.T) {
	configuration, encoded := linuxNativeGuestProvisioningConfiguration(t)
	bridgeConfiguration := Config{ProviderID: configuration.ProviderID, VirtualMachine: configuration.GuestMachine.MachineID, ServiceName: "vitalserver-host-agent", HostPlatform: "linux"}
	if issue := ValidateConfiguredNativeGuestMachineSelection(LinuxKVMlibvirtSystemdProviderKind, filepath.Join(t.TempDir(), "missing-c62.json"), bridgeConfiguration); issue == nil || issue.Code != "linux-kvm-libvirt-systemd-native-guest-machine-configuration-unavailable" {
		t.Fatalf("missing C62 issue = %+v", issue)
	}
	configurationPath := filepath.Join(t.TempDir(), "native-guest-machine.json")
	if err := os.WriteFile(configurationPath, encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	bridgeConfiguration.VirtualMachine = "other-machine"
	if issue := ValidateConfiguredNativeGuestMachineSelection(LinuxKVMlibvirtSystemdProviderKind, configurationPath, bridgeConfiguration); issue == nil || issue.Code != "linux-kvm-libvirt-systemd-native-guest-machine-configuration-mismatch" {
		t.Fatalf("mismatched C62 issue = %+v", issue)
	}
}

func TestWindowsHyperVDefinitionUsesOnlyDeclaredMachineNetworkAndResources(t *testing.T) {
	configuration := NativeGuestMachineProvisioningConfiguration{
		GuestMachine:   NativeGuestMachine{MachineID: "vitalserver-guest", CPUCount: 4, MemoryMiB: 4096, MACAddress: "02:00:5e:10:00:21"},
		RuntimeStorage: NativeGuestRuntimeStorage{RootDiskPath: `C:\\ProgramData\\VitalServer\\guest\\root.vhdx`, BootstrapVolumePath: `C:\\ProgramData\\VitalServer\\guest\\bootstrap.vhdx`},
		Native:         NativeGuestNativeProvider{HyperVPowerShellExecutablePath: `C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe`, VirtualSwitchName: "vitalserver-switch"},
	}
	executor := &recordingCommandExecutor{}
	if err := defineWindowsHyperVGuestMachine(context.Background(), configuration, executor); err != nil {
		t.Fatal(err)
	}
	if len(executor.calls) != 1 || executor.calls[0].Name != configuration.Native.HyperVPowerShellExecutablePath || len(executor.calls[0].Args) != 4 {
		t.Fatalf("Hyper-V definition command = %+v", executor.calls)
	}
	script := executor.calls[0].Args[3]
	for _, required := range []string{"New-VM -Name 'vitalserver-guest'", "-Generation 2", "-MemoryStartupBytes 4096MB", "-SwitchName 'vitalserver-switch'", "Set-VMProcessor -VMName 'vitalserver-guest' -Count 4", "Set-VMFirmware -VMName 'vitalserver-guest' -EnableSecureBoot Off", "Add-VMHardDiskDrive -VMName 'vitalserver-guest'", "Set-VMNetworkAdapter -VMName 'vitalserver-guest' -StaticMacAddress '02005e100021'", "Set-VM -VMName 'vitalserver-guest' -AutomaticStartAction Nothing -AutomaticStopAction ShutDown"} {
		if !strings.Contains(script, required) {
			t.Fatalf("Hyper-V definition omits %q: %s", required, script)
		}
	}
}
