// Package macoshostproductremoval owns the macOS effects of a C54 removal
// plan. It receives only C48-declared resources from the application layer;
// it never discovers a directory, package identity, or launchd plist by
// convention.
package macoshostproductremoval

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

type HostProductRemovalCommandResult struct {
	ExitCode int
	Stderr   string
}

type HostProductRemovalCommandRunner interface {
	RunHostProductRemovalCommand(context.Context, string, ...string) (HostProductRemovalCommandResult, error)
}

type macOSHostProductRemovalSystemCommandRunner struct{}

func (macOSHostProductRemovalSystemCommandRunner) RunHostProductRemovalCommand(context context.Context, executable string, arguments ...string) (HostProductRemovalCommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.CombinedOutput()
	if err == nil {
		return HostProductRemovalCommandResult{Stderr: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return HostProductRemovalCommandResult{ExitCode: exitError.ExitCode(), Stderr: string(output)}, nil
	}
	return HostProductRemovalCommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

// MacOSHostProductRemover implements only the Host external effects in an
// admitted C54 plan. The application writes every lifecycle transition around
// these calls, including a failure receipt when an effect fails.
type MacOSHostProductRemover struct {
	pkgutilExecutablePath string
	commandRunner         HostProductRemovalCommandRunner
}

func NewMacOSHostProductRemover(pkgutilExecutablePath string) (*MacOSHostProductRemover, error) {
	return NewMacOSHostProductRemoverWithCommandRunner(pkgutilExecutablePath, macOSHostProductRemovalSystemCommandRunner{})
}

func NewMacOSHostProductRemoverWithCommandRunner(pkgutilExecutablePath string, commandRunner HostProductRemovalCommandRunner) (*MacOSHostProductRemover, error) {
	if pkgutilExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("pkgutil path and command runner are required")
	}
	return &MacOSHostProductRemover{pkgutilExecutablePath: pkgutilExecutablePath, commandRunner: commandRunner}, nil
}

// PrepareHostProductPackageManagerCompletionTransport is intentionally not a
// macOS behavior. pkgutil receipt removal is completed by C54 itself, so a
// package-manager hand-off transport would be an invalid second owner.
func (remover *MacOSHostProductRemover) PrepareHostProductPackageManagerCompletionTransport(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, transport hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport) error {
	if err := requireMacOSManifest(manifest); err != nil {
		return err
	}
	return fmt.Errorf("macOS Host product removal must not prepare package-manager completion transport %q", transport.ManagerPath)
}

func (remover *MacOSHostProductRemover) RemoveHostProductServiceDefinitions(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireMacOSManifest(manifest); err != nil {
		return err
	}
	for _, service := range manifest.RequiredServices {
		if err := removeDeclaredRegularFile(service.DefinitionPath); err != nil {
			return fmt.Errorf("remove declared Host service definition %s: %w", service.Name, err)
		}
	}
	return nil
}

// RemoveHostProductOperatorApplication removes the single macOS application
// bundle declared by an admitted C48. It never derives an application path
// from the package identifier or application name; C54's preceding C49 proof
// is the authority for this effect.
func (remover *MacOSHostProductRemover) RemoveHostProductOperatorApplication(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireMacOSManifest(manifest); err != nil {
		return err
	}
	operatorApplication := manifest.OperatorInterface
	if operatorApplication.ApplicationBundlePath == "" || operatorApplication.ApplicationBundleTreeSHA256 == "" || operatorApplication.ApplicationBundleEntrypointRelativePath == "" {
		return fmt.Errorf("macOS Host product removal requires a declared operator application bundle")
	}
	if err := removeDeclaredDirectory(operatorApplication.ApplicationBundlePath); err != nil {
		return fmt.Errorf("remove declared macOS operator application: %w", err)
	}
	return nil
}

func (remover *MacOSHostProductRemover) RemoveHostProductActivationLink(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireMacOSManifest(manifest); err != nil {
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

func (remover *MacOSHostProductRemover) RemoveHostProductReleaseCatalog(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if err := requireMacOSManifest(manifest); err != nil {
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
		releaseRootPath := filepath.Join(catalogPath, entry.Name())
		if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(releaseRootPath); err != nil {
			return fmt.Errorf("inspect declared immutable release root: %w", err)
		}
	}
	if err := os.RemoveAll(catalogPath); err != nil {
		return fmt.Errorf("remove declared release catalog: %w", err)
	}
	return nil
}

func (remover *MacOSHostProductRemover) RemoveHostProductMutableStores(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, stores []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) error {
	if err := requireMacOSManifest(manifest); err != nil {
		return err
	}
	for _, store := range stores {
		if err := removeDeclaredDirectory(store.Path); err != nil {
			return fmt.Errorf("remove declared mutable store %s: %w", store.ID, err)
		}
	}
	return nil
}

func (remover *MacOSHostProductRemover) RemoveHostProductPackageReceipt(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) (hostinstallationmanagerdomain.HostProductPackageReceiptRemoval, error) {
	if err := requireMacOSManifest(manifest); err != nil {
		return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{}, err
	}
	result, err := remover.commandRunner.RunHostProductRemovalCommand(context, remover.pkgutilExecutablePath, "--forget", manifest.Package.Identifier)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{}, fmt.Errorf("forget declared package receipt: %w", err)
	}
	if result.ExitCode != 0 {
		return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{}, fmt.Errorf("forget declared package receipt exited with status %d: %s", result.ExitCode, result.Stderr)
	}
	return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{State: hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByManager}, nil
}

func requireMacOSManifest(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "macos" {
		return fmt.Errorf("macOS Host product remover cannot remove platform %q", manifest.Platform)
	}
	if manifest.Activation.ReferenceKind != "symbolic-link" {
		return fmt.Errorf("macOS Host product remover requires symbolic-link activation, got %q", manifest.Activation.ReferenceKind)
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
