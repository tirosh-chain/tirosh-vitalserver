// Package macoshostproductservicequiescence owns the macOS launchd effect of
// quiescing the exact services declared by C48. It does not infer labels,
// decide transaction state, or silently accept launchctl failures.
package macoshostproductservicequiescence

import (
	"context"
	"errors"
	"fmt"
	"os/exec"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

// HostServiceQuiescenceCommandResult is the complete observable result of one
// launchctl invocation. An adapter failure is kept distinct from an exit code.
type HostServiceQuiescenceCommandResult struct {
	ExitCode int
	Stderr   string
}

type HostServiceQuiescenceCommandRunner interface {
	RunHostServiceQuiescenceCommand(context.Context, string, ...string) (HostServiceQuiescenceCommandResult, error)
}

type macOSHostServiceQuiescenceSystemCommandRunner struct{}

func (macOSHostServiceQuiescenceSystemCommandRunner) RunHostServiceQuiescenceCommand(context context.Context, executable string, arguments ...string) (HostServiceQuiescenceCommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.CombinedOutput()
	if err == nil {
		return HostServiceQuiescenceCommandResult{Stderr: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return HostServiceQuiescenceCommandResult{ExitCode: exitError.ExitCode(), Stderr: string(output)}, nil
	}
	return HostServiceQuiescenceCommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

// MacOSHostProductServiceQuiescer implements the HostProductServiceQuiescer
// application port with macOS launchd.
type MacOSHostProductServiceQuiescer struct {
	launchctlExecutablePath string
	commandRunner           HostServiceQuiescenceCommandRunner
}

func NewMacOSHostProductServiceQuiescer(launchctlExecutablePath string) (*MacOSHostProductServiceQuiescer, error) {
	return NewMacOSHostProductServiceQuiescerWithCommandRunner(launchctlExecutablePath, macOSHostServiceQuiescenceSystemCommandRunner{})
}

func NewMacOSHostProductServiceQuiescerWithCommandRunner(launchctlExecutablePath string, commandRunner HostServiceQuiescenceCommandRunner) (*MacOSHostProductServiceQuiescer, error) {
	if launchctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("launchctl path and command runner are required")
	}
	return &MacOSHostProductServiceQuiescer{launchctlExecutablePath: launchctlExecutablePath, commandRunner: commandRunner}, nil
}

func (quiescer *MacOSHostProductServiceQuiescer) QuiesceHostProductServices(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "macos" {
		return fmt.Errorf("macOS Host service quiescer cannot quiesce platform %q", manifest.Platform)
	}
	for _, service := range manifest.RequiredServices {
		if service.Manager != "launchd" {
			return fmt.Errorf("declared Host service %s is not managed by launchd", service.Role)
		}
		result, err := quiescer.commandRunner.RunHostServiceQuiescenceCommand(context, quiescer.launchctlExecutablePath, "bootout", "system/"+service.Name)
		if err != nil {
			return fmt.Errorf("bootout declared Host service %s: %w", service.Name, err)
		}
		if result.ExitCode != 0 && result.ExitCode != 3 {
			return fmt.Errorf("bootout declared Host service %s exited with status %d: %s", service.Name, result.ExitCode, result.Stderr)
		}
	}
	return nil
}
