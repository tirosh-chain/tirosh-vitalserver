// Package macoshostinstallationfootprint owns macOS-native C49 protocol
// observations. Shared filesystem and transaction observations live in
// hostinstallationfootprint so Linux and Windows do not depend on macOS code.
package macoshostinstallationfootprint

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoslaunchctlprotocol"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type HostInstallationCommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}
type HostInstallationCommandRunner interface {
	RunHostInstallationCommand(context.Context, string, ...string) (HostInstallationCommandResult, error)
}
type macOSHostInstallationSystemCommandRunner struct{}

func (macOSHostInstallationSystemCommandRunner) RunHostInstallationCommand(context context.Context, executable string, arguments ...string) (HostInstallationCommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.Output()
	if err == nil {
		return HostInstallationCommandResult{Stdout: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return HostInstallationCommandResult{ExitCode: exitError.ExitCode(), Stdout: string(output), Stderr: string(exitError.Stderr)}, nil
	}
	return HostInstallationCommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

type MacOSHostInstallationFootprintObserver struct {
	pkgutilExecutablePath   string
	launchctlExecutablePath string
	commandRunner           HostInstallationCommandRunner
	shared                  *hostinstallationfootprint.Observer
}

func NewMacOSHostInstallationFootprintObserver(pkgutilExecutablePath string, launchctlExecutablePath string) (*MacOSHostInstallationFootprintObserver, error) {
	return NewMacOSHostInstallationFootprintObserverWithCommandRunner(pkgutilExecutablePath, launchctlExecutablePath, macOSHostInstallationSystemCommandRunner{})
}

func NewMacOSHostInstallationFootprintObserverWithCommandRunner(pkgutilExecutablePath string, launchctlExecutablePath string, commandRunner HostInstallationCommandRunner) (*MacOSHostInstallationFootprintObserver, error) {
	if pkgutilExecutablePath == "" || launchctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("pkgutil path, launchctl path, and command runner are required")
	}
	observer := &MacOSHostInstallationFootprintObserver{pkgutilExecutablePath: pkgutilExecutablePath, launchctlExecutablePath: launchctlExecutablePath, commandRunner: commandRunner}
	shared, err := hostinstallationfootprint.New("macos", observer, observer, hostinstallationfootprint.SymbolicLinkReleaseActivationObserver{})
	if err != nil {
		return nil, err
	}
	observer.shared = shared
	return observer, nil
}

func (observer *MacOSHostInstallationFootprintObserver) ObserveHostInstallationFootprint(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	return observer.shared.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
}

func (observer *MacOSHostInstallationFootprintObserver) ObserveHostPackageReceipt(context context.Context, packageIdentity hostinstallationmanagerdomain.HostProductPackageIdentity) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation {
	result, err := observer.commandRunner.RunHostInstallationCommand(context, observer.pkgutilExecutablePath, "--pkg-info", packageIdentity.Identifier)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: packageIdentity.Identifier, Issue: issue("macos-package-receipt-observation-failed", err.Error(), "pkgutil")}
	}
	switch result.ExitCode {
	case 0:
		productVersion, found := packageInfoValue(result.Stdout, "version")
		if !found || productVersion == "" {
			return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: packageIdentity.Identifier, Issue: issue("macos-package-receipt-decode-failed", "pkgutil returned success without a package version", "pkgutil")}
		}
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: productVersion}
	case 1:
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "absent", Identifier: packageIdentity.Identifier}
	default:
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: packageIdentity.Identifier, Issue: issue("macos-package-receipt-observation-failed", fmt.Sprintf("pkgutil exited with status %d", result.ExitCode), "pkgutil")}
	}
}

func (observer *MacOSHostInstallationFootprintObserver) ObserveHostServiceRegistration(context context.Context, service hostinstallationmanagerdomain.HostProductRequiredService) hostinstallationmanagerdomain.HostInstallationServiceObservation {
	definitionState, definitionIssue := hostinstallationfootprint.ObserveRequiredServiceDefinition(service)
	observation := hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, DefinitionState: definitionState, DefinitionIssue: definitionIssue}
	result, err := observer.commandRunner.RunHostInstallationCommand(context, observer.launchctlExecutablePath, "print", "system/"+service.Name)
	if err != nil {
		observation.State = "failed"
		observation.Issue = issue("macos-service-observation-failed", err.Error(), "launchctl")
		return observation
	}
	if result.ExitCode == 0 {
		observation.State = "registered"
	} else if macoslaunchctlprotocol.IsExplicitlyAbsentSystemService(result.ExitCode, result.Stderr, service.Name) {
		observation.State = "absent"
	} else {
		observation.State = "failed"
		observation.Issue = issue("macos-service-observation-failed", fmt.Sprintf("launchctl exited with status %d", result.ExitCode), "launchctl")
	}
	return observation
}

func (observer *MacOSHostInstallationFootprintObserver) observeRequiredService(context context.Context, service hostinstallationmanagerdomain.HostProductRequiredService) hostinstallationmanagerdomain.HostInstallationServiceObservation {
	return observer.ObserveHostServiceRegistration(context, service)
}
func observeMutableStore(store hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) hostinstallationmanagerdomain.HostInstallationMutableStoreObservation {
	return hostinstallationfootprint.ObserveMutableStore(store)
}
func observeReleaseActivation(activation hostinstallationmanagerdomain.HostProductReleaseActivation) hostinstallationmanagerdomain.HostInstallationActivationObservation {
	return hostinstallationfootprint.ObserveSymbolicLinkReleaseActivation(activation)
}
func observeImmutableRelease(payload hostinstallationmanagerdomain.HostImmutableProductPayload) hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation {
	return hostinstallationfootprint.ObserveImmutableRelease(payload)
}
func observeInstallationTransaction(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) hostinstallationmanagerdomain.HostInstallationTransactionObservation {
	return hostinstallationfootprint.ObserveInstallationTransaction(manifest, journalPath, receiptPath)
}
func issue(code, message, dependency string) *hostinstallationmanagerdomain.HostInstallationIssue {
	return &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: message, Dependency: dependency}
}
func packageInfoValue(output, key string) (string, bool) {
	prefix := key + ":"
	for _, line := range strings.Split(output, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, prefix)), true
		}
	}
	return "", false
}
