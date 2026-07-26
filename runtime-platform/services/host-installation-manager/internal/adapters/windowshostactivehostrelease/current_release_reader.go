// Package windowshostactivehostrelease owns C68 observation of the explicit
// Windows C48 directory-junction activation. A normal directory or symbolic
// link is not a compatible fallback for the declared NTFS junction contract.
package windowshostactivehostrelease

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductinstallationmanifestfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

type CommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

type CommandRunner interface {
	RunWindowsHostActiveReleaseCommand(context.Context, string, ...string) (CommandResult, error)
}

type systemCommandRunner struct{}

func (systemCommandRunner) RunWindowsHostActiveReleaseCommand(ctx context.Context, executable string, arguments ...string) (CommandResult, error) {
	command := exec.CommandContext(ctx, executable, arguments...)
	output, err := command.CombinedOutput()
	if err == nil {
		return CommandResult{Stdout: string(output)}, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		return CommandResult{ExitCode: exitError.ExitCode(), Stdout: string(output), Stderr: string(output)}, nil
	}
	return CommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

type CurrentReleaseReader struct {
	fsutilExecutablePath string
	commandRunner        CommandRunner
}

func NewCurrentReleaseReader(fsutilExecutablePath string) (*CurrentReleaseReader, error) {
	return NewCurrentReleaseReaderWithCommandRunner(fsutilExecutablePath, systemCommandRunner{})
}

func NewCurrentReleaseReaderWithCommandRunner(fsutilExecutablePath string, commandRunner CommandRunner) (*CurrentReleaseReader, error) {
	if fsutilExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("fsutil path and command runner are required")
	}
	return &CurrentReleaseReader{fsutilExecutablePath: fsutilExecutablePath, commandRunner: commandRunner}, nil
}

func (reader *CurrentReleaseReader) ReadActiveHostRelease(ctx context.Context, activeManifestPath string) (hostplatformstagedreleaseupdatedomain.ActiveHostRelease, error) {
	if ctx == nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active release observation context is required")
	}
	if activeManifestPath == "" || !filepath.IsAbs(activeManifestPath) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active C48 manifest path is invalid")
	}
	manifest, err := (hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{}).ReadHostProductInstallationManifest(ctx, activeManifestPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("read C68 active C48: %w", err)
	}
	if manifest.Platform != "windows" || manifest.Activation.ReferenceKind != "directory-junction" {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active release does not declare a Windows directory-junction activation")
	}
	if err := reader.verifyDirectoryJunction(ctx, manifest.Activation.CurrentReleaseLinkPath); err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, err
	}
	resolved, err := filepath.EvalSymlinks(manifest.Activation.CurrentReleaseLinkPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("resolve C68 active current junction: %w", err)
	}
	expected, err := filepath.EvalSymlinks(manifest.Activation.ExpectedReleaseRootPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("resolve C68 active release root: %w", err)
	}
	if !strings.EqualFold(filepath.Clean(resolved), filepath.Clean(expected)) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 current release does not match its active C48 root")
	}
	resolvedManifestPath, err := filepath.EvalSymlinks(activeManifestPath)
	if err != nil || !strings.EqualFold(filepath.Clean(resolvedManifestPath), filepath.Clean(manifest.ImmutablePayload.ManifestPath)) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active manifest path does not resolve to its declared immutable C48 path")
	}
	if err := verifyManifestBytes(manifest); err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, err
	}
	return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{Manifest: manifest}, nil
}

func (reader *CurrentReleaseReader) verifyDirectoryJunction(ctx context.Context, path string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() {
		return fmt.Errorf("C68 current release junction is missing or non-directory")
	}
	result, err := reader.commandRunner.RunWindowsHostActiveReleaseCommand(ctx, reader.fsutilExecutablePath, "reparsepoint", "query", path)
	if err != nil {
		return fmt.Errorf("inspect C68 current directory junction: %w", err)
	}
	if result.ExitCode != 0 || !strings.Contains(strings.ToLower(result.Stdout+result.Stderr), "0xa0000003") {
		return fmt.Errorf("C68 current release activation is not an NTFS directory junction")
	}
	return nil
}

func verifyManifestBytes(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	for _, entry := range manifest.ImmutablePayload.Entries {
		if err := verifySHA256(filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, filepath.FromSlash(entry.RelativePath)), entry.SHA256); err != nil {
			return fmt.Errorf("verify active C48 immutable entry %s: %w", entry.RelativePath, err)
		}
	}
	for _, service := range manifest.RequiredServices {
		if err := verifySHA256(service.DefinitionPath, service.DefinitionSHA256); err != nil {
			return fmt.Errorf("verify active C48 service definition %s: %w", service.Role, err)
		}
	}
	if err := verifySHA256(manifest.OperatorInterface.BootstrapConfigurationPath, manifest.OperatorInterface.BootstrapConfigurationSHA256); err != nil {
		return fmt.Errorf("verify active C48 operator bootstrap: %w", err)
	}
	return nil
}

func verifySHA256(path, expected string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("file is missing, non-regular, or symbolic")
	}
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return err
	}
	if actual := hex.EncodeToString(digest.Sum(nil)); actual != expected {
		return fmt.Errorf("SHA256 differs from declared value")
	}
	return nil
}
