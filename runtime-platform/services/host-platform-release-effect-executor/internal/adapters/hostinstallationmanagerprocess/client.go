// Package hostinstallationmanagerprocess invokes one C67-selected fixed Host
// Installation Manager executable. It does not interpret its exit code as C55.
package hostinstallationmanagerprocess

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"
)

const maximumOperationBytes int64 = 1024 * 1024

type Client struct{}

func (Client) ExecuteHostPlatformStagedReleaseUpdate(executionContext context.Context, endpoint hostplatformreleaseeffectexecutordomain.HostInstallationManagerEndpoint, command hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateCommand, artifact hostplatformreleaseeffectexecutordomain.ReleaseArtifact) (hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation, error) {
	if executionContext == nil {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, failed("host-installation-manager-context-invalid", "C68 execution context is required", "host-installation-manager")
	}
	if err := validateExecutable(endpoint.ExecutablePath); err != nil {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, failed("host-installation-manager-unavailable", err.Error(), "host-installation-manager")
	}
	if err := validateArtifact(artifact); err != nil {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, failed("host-platform-release-artifact-unavailable", err.Error(), "host-update-staging")
	}
	arguments := []string{
		"--mode", "staged-update",
		"--operation-id", command.OperationID,
		"--update-id", command.UpdateID,
		"--operation", command.Operation,
		"--expected-active-release-id", command.Transition.ExpectedActiveReleaseID,
		"--target-release-id", command.Transition.TargetReleaseID,
		"--active-manifest", endpoint.ActiveReleaseManifestPath,
		"--artifact-path", artifact.Path,
		"--artifact-sha256", artifact.SHA256,
	}
	process := exec.CommandContext(executionContext, endpoint.ExecutablePath, arguments...)
	output, executionErr := process.Output()
	operation, decodeErr := decodeOperation(output)
	if decodeErr == nil {
		return operation, nil
	}
	if executionErr != nil {
		if errors.Is(executionErr, context.DeadlineExceeded) || errors.Is(executionContext.Err(), context.DeadlineExceeded) {
			return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, unavailable("host-installation-manager-timeout", "C68 Host Installation Manager execution timed out", "host-installation-manager")
		}
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, failed("host-installation-manager-execution-failed", "C68 Host Installation Manager produced no valid operation: "+decodeErr.Error(), "host-installation-manager")
	}
	return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, failed("host-installation-manager-response-invalid", decodeErr.Error(), "host-installation-manager")
}

func validateExecutable(path string) error {
	if path == "" || !filepath.IsAbs(path) {
		return fmt.Errorf("C67 Host Installation Manager executable path is invalid")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("C67 Host Installation Manager executable is missing, non-regular, or symbolic")
	}
	if info.Mode()&0o111 == 0 {
		return fmt.Errorf("C67 Host Installation Manager executable is not executable")
	}
	return nil
}
func validateArtifact(artifact hostplatformreleaseeffectexecutordomain.ReleaseArtifact) error {
	if artifact.Path == "" || !filepath.IsAbs(artifact.Path) || artifact.SizeBytes < 1 {
		return fmt.Errorf("C68 archive artifact is invalid")
	}
	return nil
}
func decodeOperation(source []byte) (hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation, error) {
	if len(source) == 0 {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, fmt.Errorf("C68 Host Installation Manager emitted no operation")
	}
	if int64(len(source)) > maximumOperationBytes {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, fmt.Errorf("C68 Host Installation Manager operation exceeds maximum size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(source)))
	decoder.DisallowUnknownFields()
	var operation hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation
	if err := decoder.Decode(&operation); err != nil {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, fmt.Errorf("decode C68 Host Installation Manager operation: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{}, fmt.Errorf("C68 Host Installation Manager emitted multiple documents")
	}
	return operation, nil
}
func failed(code, message, dependency string) error {
	return hostplatformreleaseeffectexecutordomain.HostPlatformReleaseManagerRequestFailure{State: hostplatformreleaseeffectexecutordomain.ReceiptStateFailed, Issue: hostplatformreleaseeffectexecutordomain.Issue{Code: code, Message: message, Dependency: dependency}}
}
func unavailable(code, message, dependency string) error {
	return hostplatformreleaseeffectexecutordomain.HostPlatformReleaseManagerRequestFailure{State: hostplatformreleaseeffectexecutordomain.ReceiptStateUnavailable, Issue: hostplatformreleaseeffectexecutordomain.Issue{Code: code, Message: message, Dependency: dependency}}
}
