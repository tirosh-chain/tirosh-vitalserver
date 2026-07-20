// Package systemdhostproductservicequiescence owns the Linux systemd effect of
// stopping the exact C48-declared Host services. A failed systemctl command is
// not treated as service absence; only an explicit not-found load state is.
package systemdhostproductservicequiescence

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type CommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

type CommandRunner interface {
	RunSystemdHostServiceCommand(context.Context, string, ...string) (CommandResult, error)
}

type systemCommandRunner struct{}

func (systemCommandRunner) RunSystemdHostServiceCommand(context context.Context, executable string, arguments ...string) (CommandResult, error) {
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

// SystemdHostProductServiceQuiescer implements the application port without
// selecting service names or interpreting a generic error as an absent unit.
type SystemdHostProductServiceQuiescer struct {
	systemctlExecutablePath string
	commandRunner           CommandRunner
}

func NewSystemdHostProductServiceQuiescer(systemctlExecutablePath string) (*SystemdHostProductServiceQuiescer, error) {
	return NewSystemdHostProductServiceQuiescerWithCommandRunner(systemctlExecutablePath, systemCommandRunner{})
}

func NewSystemdHostProductServiceQuiescerWithCommandRunner(systemctlExecutablePath string, commandRunner CommandRunner) (*SystemdHostProductServiceQuiescer, error) {
	if systemctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("systemctl path and command runner are required")
	}
	return &SystemdHostProductServiceQuiescer{systemctlExecutablePath: systemctlExecutablePath, commandRunner: commandRunner}, nil
}

func (quiescer *SystemdHostProductServiceQuiescer) QuiesceHostProductServices(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "linux" {
		return fmt.Errorf("systemd Host service quiescer cannot quiesce platform %q", manifest.Platform)
	}
	for _, service := range manifest.RequiredServices {
		if service.Manager != "systemd" {
			return fmt.Errorf("declared Host service %s is not managed by systemd", service.Role)
		}
		result, err := quiescer.commandRunner.RunSystemdHostServiceCommand(context, quiescer.systemctlExecutablePath, "stop", service.Name)
		if err != nil {
			return fmt.Errorf("stop declared Host service %s: %w", service.Name, err)
		}
		if result.ExitCode == 0 {
			continue
		}
		if absent, absenceError := quiescer.isExplicitlyAbsent(context, service.Name); absenceError != nil {
			return fmt.Errorf("observe declared Host service %s after stop failure: %w", service.Name, absenceError)
		} else if absent {
			continue
		}
		return fmt.Errorf("stop declared Host service %s exited with status %d: %s", service.Name, result.ExitCode, result.Stderr)
	}
	return nil
}

func (quiescer *SystemdHostProductServiceQuiescer) isExplicitlyAbsent(context context.Context, serviceName string) (bool, error) {
	result, err := quiescer.commandRunner.RunSystemdHostServiceCommand(context, quiescer.systemctlExecutablePath, "show", "--property=LoadState", "--value", serviceName)
	if err != nil {
		return false, err
	}
	if result.ExitCode != 0 {
		return false, fmt.Errorf("systemctl show exited with status %d: %s", result.ExitCode, result.Stderr)
	}
	return strings.TrimSpace(result.Stdout) == "not-found", nil
}
