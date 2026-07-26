// Package linuxhostproductremoval owns the Linux effects of an admitted C54
// plan. Debian's package database is not a product-owned file: this adapter
// removes only C48-declared Host resources, reloads systemd after the declared
// unit files disappear, and returns an explicit hand-off outcome for dpkg.
package linuxhostproductremoval

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type SystemdCommandResult struct {
	ExitCode int
	Stderr   string
}

type SystemdCommandRunner interface {
	RunLinuxHostProductRemovalCommand(context.Context, string, ...string) (SystemdCommandResult, error)
}

type systemCommandRunner struct{}

func (systemCommandRunner) RunLinuxHostProductRemovalCommand(context context.Context, executable string, arguments ...string) (SystemdCommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.CombinedOutput()
	if err == nil {
		return SystemdCommandResult{Stderr: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return SystemdCommandResult{ExitCode: exitError.ExitCode(), Stderr: string(output)}, nil
	}
	return SystemdCommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

// LinuxHostProductRemover never invokes dpkg. Its package-receipt method
// instead reports the ownership hand-off that lets the package manager finish
// its own operation after the maintainer script returns.
type LinuxHostProductRemover struct {
	systemctlExecutablePath string
	commandRunner           SystemdCommandRunner
}

func NewLinuxHostProductRemover(systemctlExecutablePath string) (*LinuxHostProductRemover, error) {
	return NewLinuxHostProductRemoverWithCommandRunner(systemctlExecutablePath, systemCommandRunner{})
}

func NewLinuxHostProductRemoverWithCommandRunner(systemctlExecutablePath string, commandRunner SystemdCommandRunner) (*LinuxHostProductRemover, error) {
	if systemctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("systemctl path and command runner are required")
	}
	return &LinuxHostProductRemover{systemctlExecutablePath: systemctlExecutablePath, commandRunner: commandRunner}, nil
}

// PrepareHostProductPackageManagerCompletionTransport copies the exact C54
// verifier inputs before the immutable release is removed. dpkg runs postrm
// after data.tar payload deletion, so its hook must use this explicitly named
// manager-owned transport rather than a transient dpkg control-file location.
func (remover *LinuxHostProductRemover) PrepareHostProductPackageManagerCompletionTransport(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, transport hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport) error {
	if err := requireLinuxManifest(manifest); err != nil {
		return err
	}
	managerSource := filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, "bin", "host-installation-manager")
	if err := copyDeclaredRegularFileOnce(managerSource, transport.ManagerPath); err != nil {
		return fmt.Errorf("copy C54 package-manager completion manager: %w", err)
	}
	if err := copyDeclaredRegularFileOnce(manifest.ImmutablePayload.ManifestPath, transport.ManifestPath); err != nil {
		return fmt.Errorf("copy C54 package-manager completion manifest: %w", err)
	}
	return nil
}

func (remover *LinuxHostProductRemover) RemoveHostProductServiceDefinitions(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireLinuxManifest(manifest); err != nil {
		return err
	}
	for _, service := range manifest.RequiredServices {
		if err := removeDeclaredRegularFile(service.DefinitionPath); err != nil {
			return fmt.Errorf("remove declared systemd unit %s: %w", service.Name, err)
		}
	}
	result, err := remover.commandRunner.RunLinuxHostProductRemovalCommand(context, remover.systemctlExecutablePath, "daemon-reload")
	if err != nil {
		return fmt.Errorf("reload systemd after declared unit removal: %w", err)
	}
	if result.ExitCode != 0 {
		return fmt.Errorf("systemctl daemon-reload exited with status %d: %s", result.ExitCode, result.Stderr)
	}
	return nil
}

// RemoveHostProductOperatorApplication is intentionally unavailable on Linux:
// a macOS .app bundle is not a Linux C48 resource and must never become an
// implicit deletion target in a Debian lifecycle.
func (remover *LinuxHostProductRemover) RemoveHostProductOperatorApplication(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireLinuxManifest(manifest); err != nil {
		return err
	}
	if manifest.OperatorInterface.ApplicationBundlePath != "" || manifest.OperatorInterface.ApplicationBundleTreeSHA256 != "" || manifest.OperatorInterface.ApplicationBundleEntrypointRelativePath != "" {
		return fmt.Errorf("Linux Host product removal cannot remove a macOS operator application")
	}
	return nil
}

func (remover *LinuxHostProductRemover) RemoveHostProductActivationLink(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireLinuxManifest(manifest); err != nil {
		return err
	}
	currentPath := manifest.Activation.CurrentReleaseLinkPath
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(filepath.Dir(currentPath)); err != nil {
		return fmt.Errorf("inspect current release activation parent: %w", err)
	}
	info, err := os.Lstat(currentPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect current release activation: %w", err)
	}
	if info.Mode()&os.ModeSymlink == 0 {
		return fmt.Errorf("current release activation is not a symbolic link")
	}
	resolvedCurrent, err := filepath.EvalSymlinks(currentPath)
	if err != nil {
		return fmt.Errorf("resolve current release activation: %w", err)
	}
	resolvedExpected, err := filepath.EvalSymlinks(manifest.Activation.ExpectedReleaseRootPath)
	if err != nil {
		return fmt.Errorf("resolve expected immutable release root: %w", err)
	}
	if filepath.Clean(resolvedCurrent) != filepath.Clean(resolvedExpected) {
		return fmt.Errorf("current release activation does not point to the declared release")
	}
	if err := os.Remove(currentPath); err != nil {
		return fmt.Errorf("remove current release activation: %w", err)
	}
	return nil
}

func (remover *LinuxHostProductRemover) RemoveHostProductReleaseCatalog(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireLinuxManifest(manifest); err != nil {
		return err
	}
	catalogPath := manifest.ImmutablePayload.ReleaseCatalogPath
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(catalogPath); err != nil {
		return fmt.Errorf("inspect declared release catalog: %w", err)
	}
	info, err := os.Lstat(catalogPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect declared release catalog: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return fmt.Errorf("declared release catalog is not a directory")
	}
	entries, err := os.ReadDir(catalogPath)
	if err != nil {
		return fmt.Errorf("read declared release catalog: %w", err)
	}
	if len(entries) > 1 {
		return fmt.Errorf("declared release catalog contains more than the admitted release")
	}
	if len(entries) == 1 {
		entry := entries[0]
		if entry.Name() != manifest.Release.ID || !entry.IsDir() {
			return fmt.Errorf("declared release catalog does not contain only the admitted release")
		}
		if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(filepath.Join(catalogPath, entry.Name())); err != nil {
			return fmt.Errorf("inspect declared immutable release root: %w", err)
		}
	}
	if err := os.RemoveAll(catalogPath); err != nil {
		return fmt.Errorf("remove declared release catalog: %w", err)
	}
	return nil
}

func (remover *LinuxHostProductRemover) RemoveHostProductMutableStores(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, stores []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) error {
	if err := requireLinuxManifest(manifest); err != nil {
		return err
	}
	for _, store := range stores {
		if err := removeDeclaredDirectory(store.Path); err != nil {
			return fmt.Errorf("remove declared mutable store %s: %w", store.ID, err)
		}
	}
	return nil
}

func (remover *LinuxHostProductRemover) RemoveHostProductPackageReceipt(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) (hostinstallationmanagerdomain.HostProductPackageReceiptRemoval, error) {
	if err := requireLinuxManifest(manifest); err != nil {
		return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{}, err
	}
	return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{State: hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager}, nil
}

func requireLinuxManifest(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "linux" {
		return fmt.Errorf("Linux Host product remover cannot remove platform %q", manifest.Platform)
	}
	if manifest.Activation.ReferenceKind != "symbolic-link" {
		return fmt.Errorf("Linux Host product remover requires symbolic-link activation, got %q", manifest.Activation.ReferenceKind)
	}
	for _, service := range manifest.RequiredServices {
		if service.Manager != "systemd" {
			return fmt.Errorf("declared Host service %s is not managed by systemd", service.Role)
		}
	}
	return nil
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

func copyDeclaredRegularFileOnce(source string, destination string) error {
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
