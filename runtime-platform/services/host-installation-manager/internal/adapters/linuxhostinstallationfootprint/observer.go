// Package linuxhostinstallationfootprint owns Linux dpkg and systemd C49
// observations. Filesystem, immutable-byte, and transaction observation stays
// in the platform-neutral hostinstallationfootprint adapter.
package linuxhostinstallationfootprint

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type CommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}
type CommandRunner interface {
	RunLinuxHostInstallationCommand(context.Context, string, ...string) (CommandResult, error)
}
type systemCommandRunner struct{}

func (systemCommandRunner) RunLinuxHostInstallationCommand(context context.Context, executable string, arguments ...string) (CommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	stdout, err := command.Output()
	if err == nil {
		return CommandResult{Stdout: string(stdout)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return CommandResult{ExitCode: exitError.ExitCode(), Stdout: string(stdout), Stderr: string(exitError.Stderr)}, nil
	}
	return CommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

type LinuxHostInstallationFootprintObserver struct {
	dpkgQueryExecutablePath string
	systemctlExecutablePath string
	commandRunner           CommandRunner
	shared                  *hostinstallationfootprint.Observer
}

func NewLinuxHostInstallationFootprintObserver(dpkgQueryExecutablePath string, systemctlExecutablePath string) (*LinuxHostInstallationFootprintObserver, error) {
	return NewLinuxHostInstallationFootprintObserverWithCommandRunner(dpkgQueryExecutablePath, systemctlExecutablePath, systemCommandRunner{})
}

func NewLinuxHostInstallationFootprintObserverWithCommandRunner(dpkgQueryExecutablePath string, systemctlExecutablePath string, commandRunner CommandRunner) (*LinuxHostInstallationFootprintObserver, error) {
	if dpkgQueryExecutablePath == "" || systemctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("dpkg-query path, systemctl path, and command runner are required")
	}
	observer := &LinuxHostInstallationFootprintObserver{dpkgQueryExecutablePath: dpkgQueryExecutablePath, systemctlExecutablePath: systemctlExecutablePath, commandRunner: commandRunner}
	shared, err := hostinstallationfootprint.New("linux", observer, observer, hostinstallationfootprint.SymbolicLinkReleaseActivationObserver{})
	if err != nil {
		return nil, err
	}
	observer.shared = shared
	return observer, nil
}

func (observer *LinuxHostInstallationFootprintObserver) ObserveHostInstallationFootprint(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	return observer.shared.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
}

func (observer *LinuxHostInstallationFootprintObserver) ObserveHostPackageReceipt(context context.Context, packageIdentity hostinstallationmanagerdomain.HostProductPackageIdentity) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation {
	result, err := observer.commandRunner.RunLinuxHostInstallationCommand(context, observer.dpkgQueryExecutablePath, "-W", "-f=${Status}\\n${Version}\\n", packageIdentity.Identifier)
	if err != nil {
		return receiptIssue(packageIdentity.Identifier, "linux-package-receipt-observation-failed", err.Error())
	}
	if result.ExitCode == 1 {
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "absent", Identifier: packageIdentity.Identifier}
	}
	if result.ExitCode != 0 {
		return receiptIssue(packageIdentity.Identifier, "linux-package-receipt-observation-failed", fmt.Sprintf("dpkg-query exited with status %d", result.ExitCode))
	}
	lines := strings.Split(strings.TrimSpace(result.Stdout), "\n")
	if len(lines) != 2 {
		return receiptIssue(packageIdentity.Identifier, "linux-package-receipt-decode-failed", "dpkg-query success output does not contain status and version")
	}
	status := strings.TrimSpace(lines[0])
	version := strings.TrimSpace(lines[1])
	if status == "deinstall ok config-files" && version != "" {
		// dpkg invokes postrm after its installed payload is gone but retains
		// configuration metadata until a later purge. C49's package receipt
		// means an installed product, not every dpkg historical record; this is
		// the explicit terminal state consumed by the C54 postrm verifier.
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "absent", Identifier: packageIdentity.Identifier, PackageManagerReceiptState: "configuration-retained"}
	}
	if status == "install ok unpacked" && version != "" {
		// postinst runs after dpkg has delivered data.tar but before the package
		// receipt becomes installed. This is a real, typed package state, not an
		// absent receipt and not an installation success.
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: version, PackageManagerReceiptState: "unpacked"}
	}
	if status == "install ok half-configured" && version != "" {
		// dpkg changes the package state from unpacked to half-configured before
		// invoking postinst. This is still a package operation in progress, so
		// C49 keeps it distinct from both unpacked delivery and installed.
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: version, PackageManagerReceiptState: "configuring"}
	}
	if (status == "deinstall ok installed" || status == "deinstall ok half-configured") && version != "" {
		// dpkg invokes prerm after it marks the desired state deinstall but
		// before it deletes data.tar. C54 must see that removal transition
		// explicitly, not mislabel it as an installed or absent receipt.
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: version, PackageManagerReceiptState: "removing"}
	}
	if status == "deinstall ok half-installed" && version != "" {
		// dpkg has removed data.tar immediately before postrm, but retains an
		// in-progress database record until that hook returns. `removed` names
		// this exact payload-deletion proof; it is not absence and is consumed
		// only by C54's OS-package-manager completion transition.
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: version, PackageManagerReceiptState: "removed"}
	}
	if status != "install ok installed" || version == "" {
		return receiptIssue(packageIdentity.Identifier, "linux-package-receipt-decode-failed", fmt.Sprintf("dpkg-query returned unsupported status %q or an empty version", status))
	}
	return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: version, PackageManagerReceiptState: "installed"}
}

func (observer *LinuxHostInstallationFootprintObserver) ObserveHostServiceRegistration(context context.Context, service hostinstallationmanagerdomain.HostProductRequiredService) hostinstallationmanagerdomain.HostInstallationServiceObservation {
	definitionState, definitionIssue := hostinstallationfootprint.ObserveRequiredServiceDefinition(service)
	observation := hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, DefinitionState: definitionState, DefinitionIssue: definitionIssue}
	if service.Manager != "systemd" {
		observation.State = "failed"
		observation.Issue = issue("linux-service-manager-incompatible", service.Manager, "systemd")
		return observation
	}
	result, err := observer.commandRunner.RunLinuxHostInstallationCommand(context, observer.systemctlExecutablePath, "show", "--property=LoadState", "--value", service.Name)
	if err != nil {
		observation.State = "failed"
		observation.Issue = issue("linux-service-observation-failed", err.Error(), "systemd")
		return observation
	}
	if result.ExitCode != 0 {
		observation.State = "failed"
		observation.Issue = issue("linux-service-observation-failed", fmt.Sprintf("systemctl exited with status %d", result.ExitCode), "systemd")
		return observation
	}
	switch strings.TrimSpace(result.Stdout) {
	case "loaded":
		observation.State = "registered"
	case "not-found":
		observation.State = "absent"
	default:
		observation.State = "failed"
		observation.Issue = issue("linux-service-observation-decode-failed", "systemctl returned an unsupported LoadState", "systemd")
	}
	return observation
}

func receiptIssue(identifier, code, message string) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation {
	return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: identifier, Issue: issue(code, message, "dpkg-query")}
}
func issue(code, message, dependency string) *hostinstallationmanagerdomain.HostInstallationIssue {
	return &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: message, Dependency: dependency}
}
