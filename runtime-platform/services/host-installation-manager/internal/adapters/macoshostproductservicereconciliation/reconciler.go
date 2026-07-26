// Package macoshostproductservicereconciliation owns the macOS launchd
// reconciliation effect for the exact Host services declared by C48. It does
// not decide whether reconciliation is safe or select a release.
package macoshostproductservicereconciliation

import (
	"context"
	"errors"
	"fmt"
	"os/exec"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoslaunchctlprotocol"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

// HostServiceReconciliationCommandResult keeps a launchctl exit status
// distinct from failure to start the launchctl process.
type HostServiceReconciliationCommandResult struct {
	ExitCode int
	Stderr   string
}

type HostServiceReconciliationCommandRunner interface {
	RunHostServiceReconciliationCommand(context.Context, string, ...string) (HostServiceReconciliationCommandResult, error)
}

type macOSHostServiceReconciliationSystemCommandRunner struct{}

func (macOSHostServiceReconciliationSystemCommandRunner) RunHostServiceReconciliationCommand(context context.Context, executable string, arguments ...string) (HostServiceReconciliationCommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.CombinedOutput()
	if err == nil {
		return HostServiceReconciliationCommandResult{Stderr: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return HostServiceReconciliationCommandResult{ExitCode: exitError.ExitCode(), Stderr: string(output)}, nil
	}
	return HostServiceReconciliationCommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

// MacOSHostProductServiceReconciler implements the application reconciliation
// port. It first unloads any existing declared registration, then loads the
// exact C48 definition path. An absent registration is an expected explicit
// launchd result, while every other bootout/bootstrap failure remains visible.
type MacOSHostProductServiceReconciler struct {
	launchctlExecutablePath string
	commandRunner           HostServiceReconciliationCommandRunner
}

func NewMacOSHostProductServiceReconciler(launchctlExecutablePath string) (*MacOSHostProductServiceReconciler, error) {
	return NewMacOSHostProductServiceReconcilerWithCommandRunner(launchctlExecutablePath, macOSHostServiceReconciliationSystemCommandRunner{})
}

func NewMacOSHostProductServiceReconcilerWithCommandRunner(launchctlExecutablePath string, commandRunner HostServiceReconciliationCommandRunner) (*MacOSHostProductServiceReconciler, error) {
	if launchctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("launchctl path and command runner are required")
	}
	return &MacOSHostProductServiceReconciler{launchctlExecutablePath: launchctlExecutablePath, commandRunner: commandRunner}, nil
}

func (reconciler *MacOSHostProductServiceReconciler) ReconcileHostProductServices(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "macos" {
		return fmt.Errorf("macOS Host service reconciler cannot reconcile platform %q", manifest.Platform)
	}
	for _, service := range manifest.RequiredServices {
		if service.Manager != "launchd" {
			return fmt.Errorf("declared Host service %s is not managed by launchd", service.Role)
		}
		bootout, err := reconciler.commandRunner.RunHostServiceReconciliationCommand(context, reconciler.launchctlExecutablePath, "bootout", "system/"+service.Name)
		if err != nil {
			return fmt.Errorf("bootout declared Host service %s: %w", service.Name, err)
		}
		if bootout.ExitCode != 0 && !macoslaunchctlprotocol.IsExplicitlyAbsentSystemService(bootout.ExitCode, bootout.Stderr, service.Name) {
			return fmt.Errorf("bootout declared Host service %s exited with status %d: %s", service.Name, bootout.ExitCode, bootout.Stderr)
		}
		bootstrap, err := reconciler.commandRunner.RunHostServiceReconciliationCommand(context, reconciler.launchctlExecutablePath, "bootstrap", "system", service.DefinitionPath)
		if err != nil {
			return fmt.Errorf("bootstrap declared Host service %s: %w", service.Name, err)
		}
		if bootstrap.ExitCode != 0 {
			return fmt.Errorf("bootstrap declared Host service %s exited with status %d: %s", service.Name, bootstrap.ExitCode, bootstrap.Stderr)
		}
	}
	return nil
}
