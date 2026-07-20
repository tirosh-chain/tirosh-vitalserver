// Package systemdhostproductservicereconciliation owns the Linux systemd
// reconciliation effect for only the C48-declared Host service definitions.
package systemdhostproductservicereconciliation

import (
	"context"
	"errors"
	"fmt"
	"os/exec"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type CommandResult struct {
	ExitCode int
	Stderr   string
}

type CommandRunner interface {
	RunSystemdHostServiceCommand(context.Context, string, ...string) (CommandResult, error)
}

type systemCommandRunner struct{}

func (systemCommandRunner) RunSystemdHostServiceCommand(context context.Context, executable string, arguments ...string) (CommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.CombinedOutput()
	if err == nil {
		return CommandResult{Stderr: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return CommandResult{ExitCode: exitError.ExitCode(), Stderr: string(output)}, nil
	}
	return CommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

type SystemdHostProductServiceReconciler struct {
	systemctlExecutablePath string
	commandRunner           CommandRunner
}

func NewSystemdHostProductServiceReconciler(systemctlExecutablePath string) (*SystemdHostProductServiceReconciler, error) {
	return NewSystemdHostProductServiceReconcilerWithCommandRunner(systemctlExecutablePath, systemCommandRunner{})
}

func NewSystemdHostProductServiceReconcilerWithCommandRunner(systemctlExecutablePath string, commandRunner CommandRunner) (*SystemdHostProductServiceReconciler, error) {
	if systemctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("systemctl path and command runner are required")
	}
	return &SystemdHostProductServiceReconciler{systemctlExecutablePath: systemctlExecutablePath, commandRunner: commandRunner}, nil
}

func (reconciler *SystemdHostProductServiceReconciler) ReconcileHostProductServices(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "linux" {
		return fmt.Errorf("systemd Host service reconciler cannot reconcile platform %q", manifest.Platform)
	}
	if err := reconciler.run(context, "daemon-reload"); err != nil {
		return fmt.Errorf("reload declared Host service definitions: %w", err)
	}
	for _, service := range manifest.RequiredServices {
		if service.Manager != "systemd" {
			return fmt.Errorf("declared Host service %s is not managed by systemd", service.Role)
		}
		if err := reconciler.run(context, "enable", "--now", service.Name); err != nil {
			return fmt.Errorf("enable and start declared Host service %s: %w", service.Name, err)
		}
	}
	return nil
}

func (reconciler *SystemdHostProductServiceReconciler) run(context context.Context, arguments ...string) error {
	result, err := reconciler.commandRunner.RunSystemdHostServiceCommand(context, reconciler.systemctlExecutablePath, arguments...)
	if err != nil {
		return err
	}
	if result.ExitCode != 0 {
		return fmt.Errorf("systemctl %v exited with status %d: %s", arguments, result.ExitCode, result.Stderr)
	}
	return nil
}
