// Package windowshostproductlifecycle owns Windows C50/C54 effects. It
// executes only C48-declared SCM registrations, directory-junction activation,
// immutable release locations, and mutable stores. It never calls msiexec or
// deletes an MSI registration; Windows Installer remains that receipt owner.
package windowshostproductlifecycle

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/windowshostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type CommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

type CommandRunner interface {
	RunWindowsHostProductLifecycleCommand(context.Context, string, ...string) (CommandResult, error)
}

type systemCommandRunner struct{}

func (systemCommandRunner) RunWindowsHostProductLifecycleCommand(context context.Context, executable string, arguments ...string) (CommandResult, error) {
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

type WindowsHostProductLifecycle struct {
	commandExecutablePath string
	scExecutablePath      string
	commandRunner         CommandRunner
	wait                  func(context.Context) error
}

func NewWindowsHostProductLifecycle(commandExecutablePath, scExecutablePath string) (*WindowsHostProductLifecycle, error) {
	return NewWindowsHostProductLifecycleWithCommandRunner(commandExecutablePath, scExecutablePath, systemCommandRunner{}, waitOneSecond)
}

func NewWindowsHostProductLifecycleWithCommandRunner(commandExecutablePath, scExecutablePath string, commandRunner CommandRunner, wait func(context.Context) error) (*WindowsHostProductLifecycle, error) {
	if commandExecutablePath == "" || scExecutablePath == "" || commandRunner == nil || wait == nil {
		return nil, fmt.Errorf("cmd, sc, command runner, and wait function are required")
	}
	return &WindowsHostProductLifecycle{commandExecutablePath: commandExecutablePath, scExecutablePath: scExecutablePath, commandRunner: commandRunner, wait: wait}, nil
}

func waitOneSecond(context context.Context) error {
	timer := time.NewTimer(time.Second)
	defer timer.Stop()
	select {
	case <-context.Done():
		return context.Err()
	case <-timer.C:
		return nil
	}
}

func (lifecycle *WindowsHostProductLifecycle) QuiesceHostProductServices(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	for _, service := range manifest.RequiredServices {
		result, err := lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "stop", service.Name)
		if err != nil {
			return fmt.Errorf("stop declared Windows service %s: %w", service.Name, err)
		}
		if result.ExitCode != 0 && result.ExitCode != 1062 && result.ExitCode != 1060 {
			return fmt.Errorf("sc.exe stop declared Windows service %s exited with status %d: %s", service.Name, result.ExitCode, result.Stderr)
		}
		if result.ExitCode == 1060 {
			continue
		}
		if err := lifecycle.waitForServiceState(context, service.Name, "stopped", true); err != nil {
			return fmt.Errorf("wait for declared Windows service %s to stop: %w", service.Name, err)
		}
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) ReconcileHostProductServices(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	for _, service := range manifest.RequiredServices {
		registration := *service.WindowsSCMRegistration
		commandLine := windowshostinstallationfootprint.WindowsSCMCommandLine(registration)
		result, err := lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "create", service.Name, "binPath=", commandLine, "start=", "auto", "obj=", "LocalSystem")
		if err != nil {
			return fmt.Errorf("create declared Windows service %s: %w", service.Name, err)
		}
		if result.ExitCode == 1073 {
			result, err = lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "config", service.Name, "binPath=", commandLine, "start=", "auto", "obj=", "LocalSystem")
			if err != nil {
				return fmt.Errorf("reconfigure declared Windows service %s: %w", service.Name, err)
			}
		}
		if result.ExitCode != 0 {
			return fmt.Errorf("register declared Windows service %s exited with status %d: %s", service.Name, result.ExitCode, result.Stderr)
		}
		result, err = lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "start", service.Name)
		if err != nil {
			return fmt.Errorf("start declared Windows service %s: %w", service.Name, err)
		}
		if result.ExitCode != 0 && result.ExitCode != 1056 {
			return fmt.Errorf("sc.exe start declared Windows service %s exited with status %d: %s", service.Name, result.ExitCode, result.Stderr)
		}
		if err := lifecycle.waitForServiceState(context, service.Name, "running", false); err != nil {
			return fmt.Errorf("wait for declared Windows service %s to start: %w", service.Name, err)
		}
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) ActivateHostProductRelease(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	currentPath := manifest.Activation.CurrentReleaseLinkPath
	if info, err := os.Lstat(currentPath); err == nil {
		if !info.IsDir() {
			return fmt.Errorf("C48 Windows activation path is not a directory junction")
		}
		resolvedCurrent, currentError := filepath.EvalSymlinks(currentPath)
		resolvedExpected, expectedError := filepath.EvalSymlinks(manifest.Activation.ExpectedReleaseRootPath)
		if currentError != nil || expectedError != nil || !strings.EqualFold(filepath.Clean(resolvedCurrent), filepath.Clean(resolvedExpected)) {
			return fmt.Errorf("C48 Windows activation path does not resolve to the declared release")
		}
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect C48 Windows activation path: %w", err)
	}
	return lifecycle.createWindowsDirectoryJunction(context, currentPath, manifest.Activation.ExpectedReleaseRootPath)
}

// ActivateStagedHostProductRelease is the Windows-specific C68 effect. It
// proves the current junction still selects the expected active release,
// creates the target junction before replacing current, and restores the old
// junction if the second rename cannot complete. The Host services are already
// quiesced by the application workflow; this method never stops or starts a
// process on its own.
func (lifecycle *WindowsHostProductLifecycle) ActivateStagedHostProductRelease(context context.Context, active, target hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(active); err != nil {
		return err
	}
	if err := requireWindowsManifest(target); err != nil {
		return err
	}
	if active.Activation.CurrentReleaseLinkPath != target.Activation.CurrentReleaseLinkPath {
		return fmt.Errorf("C68 Windows current junction differs between releases")
	}
	currentPath := active.Activation.CurrentReleaseLinkPath
	if !safeForWindowsCmd(currentPath) || !safeForWindowsCmd(active.Activation.ExpectedReleaseRootPath) || !safeForWindowsCmd(target.Activation.ExpectedReleaseRootPath) {
		return fmt.Errorf("C68 Windows activation path contains cmd.exe metacharacters")
	}
	info, err := os.Lstat(currentPath)
	if err != nil || !info.IsDir() {
		return fmt.Errorf("C68 Windows current activation is missing or not a directory junction")
	}
	resolvedCurrent, currentError := filepath.EvalSymlinks(currentPath)
	resolvedActive, activeError := filepath.EvalSymlinks(active.Activation.ExpectedReleaseRootPath)
	if currentError != nil || activeError != nil || !strings.EqualFold(filepath.Clean(resolvedCurrent), filepath.Clean(resolvedActive)) {
		return fmt.Errorf("C68 Windows current junction changed before activation")
	}
	targetInfo, err := os.Lstat(target.Activation.ExpectedReleaseRootPath)
	if err != nil || !targetInfo.IsDir() || targetInfo.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("C68 Windows target release root is missing, non-directory, or symbolic")
	}
	nonce := make([]byte, 16)
	if _, err := rand.Read(nonce); err != nil {
		return fmt.Errorf("create C68 Windows activation nonce: %w", err)
	}
	suffix := hex.EncodeToString(nonce)
	nextPath := currentPath + ".updating-" + suffix
	previousPath := currentPath + ".previous-" + suffix
	if err := lifecycle.createWindowsDirectoryJunction(context, nextPath, target.Activation.ExpectedReleaseRootPath); err != nil {
		return fmt.Errorf("create C68 Windows next junction: %w", err)
	}
	defer os.Remove(nextPath)
	if err := os.Rename(currentPath, previousPath); err != nil {
		return fmt.Errorf("move C68 Windows current junction aside: %w", err)
	}
	if err := os.Rename(nextPath, currentPath); err != nil {
		if restoreError := os.Rename(previousPath, currentPath); restoreError != nil {
			return fmt.Errorf("replace C68 Windows current junction: %w; restore previous junction: %v", err, restoreError)
		}
		return fmt.Errorf("replace C68 Windows current junction: %w", err)
	}
	if err := os.Remove(previousPath); err != nil {
		return fmt.Errorf("remove C68 Windows previous junction: %w", err)
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) createWindowsDirectoryJunction(context context.Context, currentPath, targetPath string) error {
	if !safeForWindowsCmd(currentPath) || !safeForWindowsCmd(targetPath) {
		return fmt.Errorf("C48 Windows activation path contains cmd.exe metacharacters")
	}
	if err := os.MkdirAll(filepath.Dir(currentPath), 0755); err != nil {
		return fmt.Errorf("create C48 Windows activation parent: %w", err)
	}
	command := `mklink /J "` + currentPath + `" "` + targetPath + `"`
	result, err := lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.commandExecutablePath, "/d", "/s", "/c", command)
	if err != nil {
		return fmt.Errorf("create C48 Windows directory junction: %w", err)
	}
	if result.ExitCode != 0 {
		return fmt.Errorf("cmd.exe mklink /J exited with status %d: %s", result.ExitCode, result.Stderr)
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) PrepareHostProductPackageManagerCompletionTransport(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, transport hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	managerSource := filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, "bin", "host-installation-manager.exe")
	if err := copyDeclaredRegularFileOnce(managerSource, transport.ManagerPath); err != nil {
		return fmt.Errorf("copy C54 Windows completion manager: %w", err)
	}
	if err := copyDeclaredRegularFileOnce(manifest.ImmutablePayload.ManifestPath, transport.ManifestPath); err != nil {
		return fmt.Errorf("copy C54 Windows completion manifest: %w", err)
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) RemoveHostProductServiceDefinitions(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	for _, service := range manifest.RequiredServices {
		if err := lifecycle.stopAndDeleteService(context, service.Name); err != nil {
			return err
		}
		if err := removeDeclaredRegularFile(service.DefinitionPath); err != nil {
			return fmt.Errorf("remove C48 Windows service definition %s: %w", service.Name, err)
		}
	}
	return nil
}

// RemoveHostProductOperatorApplication is intentionally unavailable on
// Windows. A macOS operator bundle must be rejected as a contract error rather
// than silently becoming an unowned or guessed deletion target.
func (lifecycle *WindowsHostProductLifecycle) RemoveHostProductOperatorApplication(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	if manifest.OperatorInterface.ApplicationBundlePath != "" || manifest.OperatorInterface.ApplicationBundleTreeSHA256 != "" || manifest.OperatorInterface.ApplicationBundleEntrypointRelativePath != "" {
		return fmt.Errorf("Windows Host product removal cannot remove a macOS operator application")
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) RemoveHostProductActivationLink(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	currentPath := manifest.Activation.CurrentReleaseLinkPath
	info, err := os.Lstat(currentPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect C48 Windows activation: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("C48 Windows activation is not a directory junction")
	}
	resolvedCurrent, currentError := filepath.EvalSymlinks(currentPath)
	resolvedExpected, expectedError := filepath.EvalSymlinks(manifest.Activation.ExpectedReleaseRootPath)
	if currentError != nil || expectedError != nil || !strings.EqualFold(filepath.Clean(resolvedCurrent), filepath.Clean(resolvedExpected)) {
		return fmt.Errorf("C48 Windows activation does not resolve to the declared release")
	}
	if err := os.Remove(currentPath); err != nil {
		return fmt.Errorf("remove C48 Windows directory junction: %w", err)
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) RemoveHostProductReleaseCatalog(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	return removeDeclaredDirectory(manifest.ImmutablePayload.ReleaseCatalogPath)
}

func (lifecycle *WindowsHostProductLifecycle) RemoveHostProductMutableStores(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, stores []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) error {
	if err := requireWindowsManifest(manifest); err != nil {
		return err
	}
	for _, store := range stores {
		if err := removeDeclaredDirectory(store.Path); err != nil {
			return fmt.Errorf("remove C48 Windows mutable store %s: %w", store.ID, err)
		}
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) RemoveHostProductPackageReceipt(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) (hostinstallationmanagerdomain.HostProductPackageReceiptRemoval, error) {
	if err := requireWindowsManifest(manifest); err != nil {
		return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{}, err
	}
	return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{State: hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager}, nil
}

func (lifecycle *WindowsHostProductLifecycle) stopAndDeleteService(context context.Context, name string) error {
	result, err := lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "stop", name)
	if err != nil {
		return fmt.Errorf("stop C48 Windows service %s: %w", name, err)
	}
	if result.ExitCode != 0 && result.ExitCode != 1060 && result.ExitCode != 1062 {
		return fmt.Errorf("sc.exe stop C48 Windows service %s exited with status %d", name, result.ExitCode)
	}
	if result.ExitCode != 1060 {
		if err := lifecycle.waitForServiceState(context, name, "stopped", true); err != nil {
			return fmt.Errorf("wait for C48 Windows service %s to stop: %w", name, err)
		}
	}
	result, err = lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "delete", name)
	if err != nil {
		return fmt.Errorf("delete C48 Windows service %s: %w", name, err)
	}
	if result.ExitCode != 0 && result.ExitCode != 1060 {
		return fmt.Errorf("sc.exe delete C48 Windows service %s exited with status %d", name, result.ExitCode)
	}
	if result.ExitCode != 1060 {
		if err := lifecycle.waitForServiceState(context, name, "absent", true); err != nil {
			return fmt.Errorf("wait for C48 Windows service %s deletion: %w", name, err)
		}
	}
	return nil
}

func (lifecycle *WindowsHostProductLifecycle) waitForServiceState(context context.Context, name, desired string, absenceAllowed bool) error {
	for attempt := 0; attempt < 30; attempt++ {
		result, err := lifecycle.commandRunner.RunWindowsHostProductLifecycleCommand(context, lifecycle.scExecutablePath, "query", name)
		if err != nil {
			return err
		}
		if result.ExitCode == 1060 {
			if desired == "absent" || absenceAllowed {
				return nil
			}
			return fmt.Errorf("service is absent")
		}
		if result.ExitCode != 0 {
			return fmt.Errorf("sc.exe query exited with status %d: %s", result.ExitCode, result.Stderr)
		}
		state := windowsServiceState(result.Stdout)
		if state == desired {
			return nil
		}
		if attempt == 29 {
			return fmt.Errorf("service state is %q rather than %q", state, desired)
		}
		if err := lifecycle.wait(context); err != nil {
			return err
		}
	}
	return fmt.Errorf("service state wait exhausted")
}

func windowsServiceState(output string) string {
	upper := strings.ToUpper(output)
	switch {
	case strings.Contains(upper, "STOPPED"):
		return "stopped"
	case strings.Contains(upper, "RUNNING"):
		return "running"
	default:
		return "transitioning"
	}
}

func requireWindowsManifest(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "windows" || manifest.Activation.ReferenceKind != "directory-junction" {
		return fmt.Errorf("Windows Host product lifecycle requires a Windows directory-junction C48 declaration")
	}
	for _, service := range manifest.RequiredServices {
		if service.Manager != "windows-scm" || service.WindowsSCMRegistration == nil {
			return fmt.Errorf("C48 service %s is not an explicit Windows SCM registration", service.Role)
		}
	}
	return nil
}

func safeForWindowsCmd(value string) bool {
	return value != "" && !strings.ContainsAny(value, `&|<>^%"`) && !strings.ContainsRune(value, '\x00')
}

func removeDeclaredRegularFile(path string) error {
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(path); err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return fmt.Errorf("declared path is not a regular file")
	}
	return os.Remove(path)
}

func removeDeclaredDirectory(path string) error {
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(path); err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return fmt.Errorf("declared path is not a directory")
	}
	return os.RemoveAll(path)
}

func copyDeclaredRegularFileOnce(source, destination string) error {
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(source); err != nil {
		return fmt.Errorf("inspect source: %w", err)
	}
	info, err := os.Lstat(source)
	if err != nil {
		return fmt.Errorf("inspect source: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return fmt.Errorf("source is not a regular file")
	}
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(filepath.Dir(destination)); err != nil {
		return fmt.Errorf("inspect destination parent: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0755); err != nil {
		return fmt.Errorf("create destination parent: %w", err)
	}
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(filepath.Dir(destination)); err != nil {
		return fmt.Errorf("reinspect destination parent: %w", err)
	}
	sourceFile, err := os.Open(source)
	if err != nil {
		return fmt.Errorf("open source: %w", err)
	}
	defer sourceFile.Close()
	destinationFile, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, info.Mode().Perm())
	if err != nil {
		return fmt.Errorf("create destination: %w", err)
	}
	if _, err := destinationFile.ReadFrom(sourceFile); err != nil {
		_ = destinationFile.Close()
		return fmt.Errorf("copy source: %w", err)
	}
	if err := destinationFile.Close(); err != nil {
		return fmt.Errorf("close destination: %w", err)
	}
	return nil
}
