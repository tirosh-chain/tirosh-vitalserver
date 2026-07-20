// Package stagedlayereffectprocess invokes only C26-declared, verified
// executables from a Host-owned staged bundle. It never evaluates a shell
// expression or accepts caller-selected executor arguments.
package stagedlayereffectprocess

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

const maximumReceiptBytes int64 = 1 << 20

// StagedLayerEffectProcessExecutorConfig is explicit Host-local composition
// input. The deployment supervisor names both state directories before it
// starts a next updater; C26 names only verified payload-relative bytes.
type StagedLayerEffectProcessExecutorConfig struct {
	StagingDirectory string
	ReceiptDirectory string
}

// StagedLayerEffectProcessExecutor produces C55 inputs for the application
// workflow. A command exit is transport evidence only; it cannot become an
// update result without the strict C55 receipt written by the release payload.
type StagedLayerEffectProcessExecutor struct {
	stagingDirectory string
	receiptDirectory string
}

func NewStagedLayerEffectProcessExecutor(config StagedLayerEffectProcessExecutorConfig) (*StagedLayerEffectProcessExecutor, error) {
	staging, err := requireDirectory(config.StagingDirectory)
	if err != nil {
		return nil, fmt.Errorf("configure staged update directory: %w", err)
	}
	receipts, err := requireDirectory(config.ReceiptDirectory)
	if err != nil {
		return nil, fmt.Errorf("configure layer effect receipt directory: %w", err)
	}
	return &StagedLayerEffectProcessExecutor{stagingDirectory: staging, receiptDirectory: receipts}, nil
}

func (executor *StagedLayerEffectProcessExecutor) Execute(ctx context.Context, invocationPath string, input hostupdaterdomain.StagedProductUpdatePlanningInput, layer hostupdaterdomain.ProductUpdateLayerPlan, operation string, artifact hostupdaterdomain.ProductUpdateArtifact) (hostupdaterdomain.StagedUpdateLayerEffectReceipt, error) {
	if ctx == nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("layer effect context is required")
	}
	if err := requireInvocationInStagingDirectory(invocationPath, executor.stagingDirectory); err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	if operation != hostupdaterdomain.StagedUpdateLayerEffectOperationApply && operation != hostupdaterdomain.StagedUpdateLayerEffectOperationRollback {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("layer effect operation is unsupported")
	}
	if err := verifyArtifact(executor.stagingDirectory, artifact.ID, artifact.RelativePath, artifact.SHA256, artifact.SizeBytes); err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("verify layer artifact: %w", err)
	}
	if err := verifyArtifact(executor.stagingDirectory, layer.EffectExecutor.ID, layer.EffectExecutor.RelativePath, layer.EffectExecutor.SHA256, layer.EffectExecutor.SizeBytes); err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("verify layer effect executor: %w", err)
	}
	if err := verifyArtifact(executor.stagingDirectory, layer.EffectExecutor.ConfigurationArtifact.ID, layer.EffectExecutor.ConfigurationArtifact.RelativePath, layer.EffectExecutor.ConfigurationArtifact.SHA256, layer.EffectExecutor.ConfigurationArtifact.SizeBytes); err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("verify layer effect executor configuration: %w", err)
	}
	executorPath, err := safeChild(executor.stagingDirectory, layer.EffectExecutor.RelativePath)
	if err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	if err := requireExecutableRegularFile(executorPath); err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	artifactPath, err := safeChild(executor.stagingDirectory, artifact.RelativePath)
	if err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	effectConfigurationPath, err := safeChild(executor.stagingDirectory, layer.EffectExecutor.ConfigurationArtifact.RelativePath)
	if err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	receiptPath, err := executor.receiptPath(input.Invocation.UpdateID, layer.Layer, operation)
	if err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	if receipt, exists, readErr := readReceiptIfPresent(receiptPath); readErr != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, readErr
	} else if exists {
		return receipt, nil
	}
	command := exec.CommandContext(ctx, executorPath,
		"--protocol-version", "v1",
		"--effect-executor-id", layer.EffectExecutor.ID,
		"--effect-configuration-path", effectConfigurationPath,
		"--receipt-path", receiptPath,
		"--update-id", input.Invocation.UpdateID,
		"--layer", layer.Layer,
		"--operation", operation,
		"--artifact-path", artifactPath,
		"--artifact-sha256", artifact.SHA256,
	)
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	commandErr := command.Run()
	receipt, exists, readErr := readReceiptIfPresent(receiptPath)
	if readErr != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, readErr
	}
	if exists {
		return receipt, nil
	}
	if commandErr != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("layer effect executor exited without C55 receipt: %w", commandErr)
	}
	return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("layer effect executor completed without C55 receipt")
}

func (executor *StagedLayerEffectProcessExecutor) receiptPath(updateID string, layer string, operation string) (string, error) {
	if !validIdentifier(updateID) || !validIdentifier(layer) || (operation != hostupdaterdomain.StagedUpdateLayerEffectOperationApply && operation != hostupdaterdomain.StagedUpdateLayerEffectOperationRollback) {
		return "", fmt.Errorf("layer effect receipt identity is invalid")
	}
	identity := sha256.Sum256([]byte(updateID + "\x00" + layer + "\x00" + operation))
	return filepath.Join(executor.receiptDirectory, hex.EncodeToString(identity[:])+".json"), nil
}

func requireInvocationInStagingDirectory(invocationPath string, stagingDirectory string) error {
	if invocationPath == "" || !filepath.IsAbs(invocationPath) {
		return fmt.Errorf("C30 invocation path must be absolute")
	}
	invocationDirectory, err := filepath.Abs(filepath.Dir(invocationPath))
	if err != nil {
		return fmt.Errorf("resolve C30 invocation directory: %w", err)
	}
	if invocationDirectory != stagingDirectory {
		return fmt.Errorf("C30 invocation directory does not match configured staged update directory")
	}
	return nil
}

func requireDirectory(path string) (string, error) {
	if path == "" || !filepath.IsAbs(path) {
		return "", fmt.Errorf("directory path must be absolute")
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(abs)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("directory is missing, not a directory, or a symbolic link")
	}
	return abs, nil
}

func requireExecutableRegularFile(path string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("layer effect executor is missing, not regular, or a symbolic link")
	}
	if runtime.GOOS != "windows" && info.Mode().Perm()&0o111 == 0 {
		return fmt.Errorf("layer effect executor is not executable")
	}
	return nil
}

func verifyArtifact(root string, id string, relativePath string, expectedSHA256 string, expectedSize int64) error {
	if !validIdentifier(id) || expectedSize < 1 || !validSHA256(expectedSHA256) {
		return fmt.Errorf("artifact identity, digest, or size is invalid")
	}
	path, err := safeChild(root, relativePath)
	if err != nil {
		return err
	}
	if err := rejectSymlinkedRelativePath(root, relativePath); err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("artifact is missing, not regular, or a symbolic link")
	}
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	opened, err := file.Stat()
	if err != nil || !opened.Mode().IsRegular() || opened.Size() != expectedSize {
		return fmt.Errorf("artifact is not a regular file with declared size")
	}
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return err
	}
	if hex.EncodeToString(digest.Sum(nil)) != expectedSHA256 {
		return fmt.Errorf("artifact sha256 does not match declaration")
	}
	return nil
}

func safeChild(root string, relative string) (string, error) {
	if !strings.HasPrefix(relative, "payload/") || strings.Contains(relative, "\\") || strings.Contains(relative, "..") || filepath.IsAbs(relative) {
		return "", fmt.Errorf("artifact path must stay below payload without traversal")
	}
	clean := filepath.Clean(relative)
	if clean == "payload" || !strings.HasPrefix(clean, "payload"+string(filepath.Separator)) {
		return "", fmt.Errorf("artifact path must name a payload file")
	}
	path := filepath.Join(root, clean)
	contained, err := filepath.Rel(root, path)
	if err != nil || contained == ".." || strings.HasPrefix(contained, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("artifact path escapes staged update directory")
	}
	return path, nil
}

func rejectSymlinkedRelativePath(root string, relative string) error {
	path, err := safeChild(root, relative)
	if err != nil {
		return err
	}
	contained, err := filepath.Rel(root, path)
	if err != nil {
		return err
	}
	current := root
	for _, component := range strings.Split(contained, string(filepath.Separator)) {
		current = filepath.Join(current, component)
		info, statErr := os.Lstat(current)
		if statErr != nil {
			return statErr
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("artifact path contains a symbolic link")
		}
	}
	return nil
}

func readReceiptIfPresent(path string) (hostupdaterdomain.StagedUpdateLayerEffectReceipt, bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, nil
	}
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, fmt.Errorf("C55 receipt is missing, not regular, or a symbolic link")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumReceiptBytes+1))
	if err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, err
	}
	if int64(len(contents)) > maximumReceiptBytes {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, fmt.Errorf("C55 receipt exceeds maximum size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var receipt hostupdaterdomain.StagedUpdateLayerEffectReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, fmt.Errorf("decode C55 receipt: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, false, fmt.Errorf("C55 receipt must contain exactly one JSON object")
	}
	return receipt, true, nil
}

func validIdentifier(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != ':' && character != '-' {
			return false
		}
		if index == 0 && !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') {
			return false
		}
	}
	return true
}

func validSHA256(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, character := range value {
		if !(character >= '0' && character <= '9') && !(character >= 'a' && character <= 'f') {
			return false
		}
	}
	return true
}
