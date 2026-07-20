// Package windowshostinstallationfootprint owns the Windows-native portion of
// C49. It observes MSI registration in the uninstall registry and the exact
// C48-declared SCM registration. It does not infer either from a file name,
// a running process, or a successful package command.
package windowshostinstallationfootprint

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
	RunWindowsHostInstallationCommand(context.Context, string, ...string) (CommandResult, error)
}

type systemCommandRunner struct{}

func (systemCommandRunner) RunWindowsHostInstallationCommand(context context.Context, executable string, arguments ...string) (CommandResult, error) {
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

// WindowsHostInstallationFootprintObserver composes shared C49 filesystem
// observations with Windows MSI/SCM/junction observations. The caller names
// all three native executables; no host-dependent executable lookup occurs.
type WindowsHostInstallationFootprintObserver struct {
	shared                 *hostinstallationfootprint.Observer
	registryExecutablePath string
	scExecutablePath       string
	fsutilExecutablePath   string
	commandRunner          CommandRunner
}

func NewWindowsHostInstallationFootprintObserver(registryExecutablePath, scExecutablePath, fsutilExecutablePath string) (*WindowsHostInstallationFootprintObserver, error) {
	return NewWindowsHostInstallationFootprintObserverWithCommandRunner(registryExecutablePath, scExecutablePath, fsutilExecutablePath, systemCommandRunner{})
}

func NewWindowsHostInstallationFootprintObserverWithCommandRunner(registryExecutablePath, scExecutablePath, fsutilExecutablePath string, commandRunner CommandRunner) (*WindowsHostInstallationFootprintObserver, error) {
	if registryExecutablePath == "" || scExecutablePath == "" || fsutilExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("reg, sc, fsutil paths and command runner are required")
	}
	observer := &WindowsHostInstallationFootprintObserver{
		registryExecutablePath: registryExecutablePath,
		scExecutablePath:       scExecutablePath,
		fsutilExecutablePath:   fsutilExecutablePath,
		commandRunner:          commandRunner,
	}
	shared, err := hostinstallationfootprint.New("windows", observer, observer, observer)
	if err != nil {
		return nil, err
	}
	observer.shared = shared
	return observer, nil
}

func (observer *WindowsHostInstallationFootprintObserver) ObserveHostInstallationFootprint(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	return observer.shared.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
}

func (observer *WindowsHostInstallationFootprintObserver) ObserveHostPackageReceipt(context context.Context, identity hostinstallationmanagerdomain.HostProductPackageIdentity) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation {
	if identity.PackageManagerIdentifier == "" {
		return receiptIssue(identity.Identifier, "windows-msi-product-code-missing", "C48 Windows package identity does not declare an MSI ProductCode", "registry")
	}
	for _, root := range []string{
		`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` + identity.PackageManagerIdentifier,
		`HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\` + identity.PackageManagerIdentifier,
	} {
		result, err := observer.commandRunner.RunWindowsHostInstallationCommand(context, observer.registryExecutablePath, "query", root, "/v", "DisplayVersion")
		if err != nil {
			return receiptIssue(identity.Identifier, "windows-msi-receipt-observation-failed", err.Error(), "registry")
		}
		if result.ExitCode == 1 {
			continue
		}
		if result.ExitCode != 0 {
			return receiptIssue(identity.Identifier, "windows-msi-receipt-observation-failed", fmt.Sprintf("reg.exe query exited with status %d", result.ExitCode), "registry")
		}
		version, found := displayVersion(result.Stdout)
		if !found || version == "" {
			return receiptIssue(identity.Identifier, "windows-msi-receipt-decode-failed", "MSI uninstall registration did not provide DisplayVersion", "registry")
		}
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: identity.Identifier, ProductVersion: version, PackageManagerReceiptState: "installed"}
	}
	return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "absent", Identifier: identity.Identifier}
}

func (observer *WindowsHostInstallationFootprintObserver) ObserveHostServiceRegistration(context context.Context, service hostinstallationmanagerdomain.HostProductRequiredService) hostinstallationmanagerdomain.HostInstallationServiceObservation {
	if service.Manager != "windows-scm" || service.WindowsSCMRegistration == nil {
		return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "failed", Issue: issue("windows-scm-service-declaration-invalid", "C48 Windows SCM registration is missing", "sc.exe")}
	}
	result, err := observer.commandRunner.RunWindowsHostInstallationCommand(context, observer.scExecutablePath, "qc", service.Name)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "failed", Issue: issue("windows-scm-service-observation-failed", err.Error(), "sc.exe")}
	}
	if result.ExitCode == 1060 {
		return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "absent"}
	}
	if result.ExitCode != 0 {
		return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "failed", Issue: issue("windows-scm-service-observation-failed", fmt.Sprintf("sc.exe qc exited with status %d", result.ExitCode), "sc.exe")}
	}
	configuration, parseIssue := parseSCMConfiguration(result.Stdout)
	if parseIssue != "" {
		return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "failed", Issue: issue("windows-scm-service-decode-failed", parseIssue, "sc.exe")}
	}
	expectedCommandLine := WindowsSCMCommandLine(*service.WindowsSCMRegistration)
	if normalizeSCMValue(configuration.binaryPath) != normalizeSCMValue(expectedCommandLine) || configuration.startMode != "automatic" || configuration.account != "LocalSystem" {
		return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "failed", Issue: issue("windows-scm-service-registration-diverged", "SCM registration does not match the declared executable, arguments, start mode, and account", "sc.exe")}
	}
	return hostinstallationmanagerdomain.HostInstallationServiceObservation{Role: service.Role, Name: service.Name, State: "registered"}
}

// ObserveHostReleaseActivation proves a C48 directory junction and its exact
// target. A Windows symbolic link or ordinary directory is divergence, never
// a substitute for the declared junction mechanism.
func (observer *WindowsHostInstallationFootprintObserver) ObserveHostReleaseActivation(activation hostinstallationmanagerdomain.HostProductReleaseActivation) hostinstallationmanagerdomain.HostInstallationActivationObservation {
	info, err := os.Lstat(activation.CurrentReleaseLinkPath)
	if errors.Is(err, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "absent", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath}
	}
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("windows-activation-read-failed", err.Error(), "filesystem")}
	}
	if !info.IsDir() {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("windows-activation-not-directory-junction", "C48 activation path is not a directory", "filesystem")}
	}
	result, commandError := observer.commandRunner.RunWindowsHostInstallationCommand(context.Background(), observer.fsutilExecutablePath, "reparsepoint", "query", activation.CurrentReleaseLinkPath)
	if commandError != nil || result.ExitCode != 0 || !strings.Contains(strings.ToLower(result.Stdout+result.Stderr), "0xa0000003") {
		message := "C48 activation path is not an NTFS directory junction"
		if commandError != nil {
			message = commandError.Error()
		}
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("windows-activation-not-directory-junction", message, "fsutil")}
	}
	resolvedCurrent, resolveError := filepath.EvalSymlinks(activation.CurrentReleaseLinkPath)
	if resolveError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("windows-activation-target-read-failed", resolveError.Error(), "filesystem")}
	}
	resolvedExpected, expectedError := filepath.EvalSymlinks(activation.ExpectedReleaseRootPath)
	if expectedError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("windows-expected-release-read-failed", expectedError.Error(), "filesystem")}
	}
	if strings.EqualFold(filepath.Clean(resolvedCurrent), filepath.Clean(resolvedExpected)) {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, ObservedTargetPath: resolvedCurrent}
	}
	return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, ObservedTargetPath: resolvedCurrent}
}

// WindowsSCMCommandLine renders the explicit C48 registration without a shell.
func WindowsSCMCommandLine(registration hostinstallationmanagerdomain.HostProductWindowsSCMRegistration) string {
	parts := make([]string, 0, 1+len(registration.Arguments))
	parts = append(parts, quoteWindowsCommandArgument(registration.ExecutablePath))
	for _, argument := range registration.Arguments {
		parts = append(parts, quoteWindowsCommandArgument(argument))
	}
	return strings.Join(parts, " ")
}

func quoteWindowsCommandArgument(value string) string {
	if value != "" && !strings.ContainsAny(value, " \t\"") {
		return value
	}
	var builder strings.Builder
	builder.WriteByte('"')
	backslashes := 0
	for _, character := range value {
		if character == '\\' {
			backslashes++
			continue
		}
		if character == '"' {
			builder.WriteString(strings.Repeat("\\", backslashes*2+1))
			builder.WriteRune(character)
			backslashes = 0
			continue
		}
		builder.WriteString(strings.Repeat("\\", backslashes))
		backslashes = 0
		builder.WriteRune(character)
	}
	builder.WriteString(strings.Repeat("\\", backslashes*2))
	builder.WriteByte('"')
	return builder.String()
}

type scmConfiguration struct {
	binaryPath string
	startMode  string
	account    string
}

func parseSCMConfiguration(output string) (scmConfiguration, string) {
	configuration := scmConfiguration{}
	for _, line := range strings.Split(output, "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(trimmed, "BINARY_PATH_NAME"):
			configuration.binaryPath = fieldValue(trimmed)
		case strings.HasPrefix(trimmed, "START_TYPE"):
			if strings.Contains(trimmed, "AUTO_START") {
				configuration.startMode = "automatic"
			}
		case strings.HasPrefix(trimmed, "SERVICE_START_NAME"):
			configuration.account = fieldValue(trimmed)
		}
	}
	if configuration.binaryPath == "" || configuration.startMode == "" || configuration.account == "" {
		return scmConfiguration{}, "sc.exe qc output is missing BINARY_PATH_NAME, START_TYPE, or SERVICE_START_NAME"
	}
	return configuration, ""
}

func fieldValue(line string) string {
	if index := strings.Index(line, ":"); index >= 0 {
		return strings.TrimSpace(line[index+1:])
	}
	return ""
}

func displayVersion(output string) (string, bool) {
	for _, line := range strings.Split(output, "\n") {
		if index := strings.Index(line, "REG_SZ"); index >= 0 && strings.Contains(line[:index], "DisplayVersion") {
			return strings.TrimSpace(line[index+len("REG_SZ"):]), true
		}
	}
	return "", false
}

func normalizeSCMValue(value string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(value)), " ")
}

func receiptIssue(identifier, code, message, dependency string) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation {
	return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: identifier, Issue: issue(code, message, dependency)}
}

func issue(code, message, dependency string) *hostinstallationmanagerdomain.HostInstallationIssue {
	return &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: message, Dependency: dependency}
}
