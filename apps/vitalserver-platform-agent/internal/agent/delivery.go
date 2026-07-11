package agent

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

type deliveryProcessRunner interface {
	Run(ctx context.Context, executable string, arguments ...string) ([]byte, error)
}

type systemDeliveryProcessRunner struct{}

func (systemDeliveryProcessRunner) Run(ctx context.Context, executable string, arguments ...string) ([]byte, error) {
	command := exec.CommandContext(ctx, executable, arguments...)
	output, err := command.CombinedOutput()
	if err != nil {
		return output, fmt.Errorf("delivery process failed executable=%s reason=%w output=%s", executable, err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

type deliveryController struct {
	config DeliveryConfig
	runner deliveryProcessRunner
	now    func() time.Time
}

type platformFileReference struct {
	Kind  string `json:"kind"`
	Value string `json:"value"`
}

type updateBundleRequest struct {
	Bundle platformFileReference `json:"bundle"`
}

type updateBundleSummary struct {
	Summary string `json:"summary"`
}

type trustedBundleDigestDocument struct {
	SchemaVersion int      `json:"schemaVersion"`
	SHA256        []string `json:"sha256"`
}

var (
	errUpdateApplyUnavailable   = errors.New("update apply is unavailable")
	errTrustedDigestUnavailable = errors.New("trusted bundle digest owner is unavailable")
	errUpdateBundleUntrusted    = errors.New("update bundle is not trusted")
)

func newDeliveryController(config *DeliveryConfig) *deliveryController {
	if config == nil {
		return nil
	}
	return &deliveryController{config: *config, runner: systemDeliveryProcessRunner{}, now: time.Now}
}

func ValidateDelivery(config *DeliveryConfig) error {
	if config == nil {
		return nil
	}
	for label, path := range map[string]string{
		"update tool":          config.UpdateTool,
		"rollback tool":        config.RollbackTool,
		"scheduler executable": config.SchedulerExecutable,
	} {
		info, err := os.Stat(path)
		if err != nil {
			return fmt.Errorf("platform delivery %s is unavailable path=%s: %w", label, path, err)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("platform delivery %s is not a regular file path=%s", label, path)
		}
		if config.SchedulerKind == DeliverySchedulerSystemdTransient && info.Mode().Perm()&0o111 == 0 {
			return fmt.Errorf("platform delivery %s is not executable path=%s", label, path)
		}
	}
	if config.SchedulerKind == DeliverySchedulerWindowsTask {
		info, err := os.Stat(config.SchedulerScript)
		if err != nil {
			return fmt.Errorf("platform delivery scheduler script is unavailable path=%s: %w", config.SchedulerScript, err)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("platform delivery scheduler script is not a regular file path=%s", config.SchedulerScript)
		}
	}
	if config.UninstallTool != "" {
		info, err := os.Stat(config.UninstallTool)
		if err != nil {
			return fmt.Errorf("platform delivery uninstall tool is unavailable path=%s: %w", config.UninstallTool, err)
		}
		if !info.Mode().IsRegular() || (config.SchedulerKind == DeliverySchedulerSystemdTransient && info.Mode().Perm()&0o111 == 0) {
			return fmt.Errorf("platform delivery uninstall tool is invalid path=%s", config.UninstallTool)
		}
	}
	if config.SupportExportTool != "" {
		info, err := os.Stat(config.SupportExportTool)
		if err != nil {
			return fmt.Errorf("platform delivery support export tool is unavailable path=%s: %w", config.SupportExportTool, err)
		}
		if !info.Mode().IsRegular() || (config.SchedulerKind == DeliverySchedulerSystemdTransient && info.Mode().Perm()&0o111 == 0) {
			return fmt.Errorf("platform delivery support export tool is invalid path=%s", config.SupportExportTool)
		}
	}
	workflowDirectory := filepath.Dir(config.WorkflowDocument)
	info, err := os.Stat(workflowDirectory)
	if err != nil {
		return fmt.Errorf("platform delivery workflow owner directory is unavailable path=%s: %w", workflowDirectory, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("platform delivery workflow owner parent is not a directory path=%s", workflowDirectory)
	}
	if config.ApplyPolicy == DeliveryApplyPolicySHA256Allowlist {
		if _, err := readTrustedBundleDigests(config.TrustedBundleDigests); err != nil {
			return err
		}
	}
	return nil
}

func (controller *deliveryController) canApplyBundle() bool {
	return controller != nil && controller.config.ApplyPolicy == DeliveryApplyPolicySHA256Allowlist
}

func (controller *deliveryController) summarize(ctx context.Context, bundle string) (updateBundleSummary, error) {
	context, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	executable, arguments, err := controller.toolInvocation(controller.config.UpdateTool, "summary", "--bundle", bundle)
	if err != nil {
		return updateBundleSummary{}, err
	}
	output, err := controller.runner.Run(context, executable, arguments...)
	if err != nil {
		return updateBundleSummary{}, err
	}
	var document struct {
		Summary string `json:"summary"`
	}
	if err := json.Unmarshal(output, &document); err != nil {
		return updateBundleSummary{}, fmt.Errorf("update bundle summary decode failed: %w", err)
	}
	if document.Summary == "" {
		return updateBundleSummary{}, errors.New("update bundle summary is missing")
	}
	return updateBundleSummary{Summary: document.Summary}, nil
}

func (controller *deliveryController) schedule(ctx context.Context, action, bundle string) (contract.PlatformWorkflowOperation, error) {
	return controller.scheduleCommand(
		ctx,
		"update-"+action,
		[]string{
			controller.config.UpdateTool,
			action,
			"--bundle", bundle,
		},
		func() error {
			if action == "apply" {
				return controller.requireTrustedBundle(bundle)
			}
			return nil
		},
	)
}

func (controller *deliveryController) scheduleRollback(ctx context.Context) (contract.PlatformWorkflowOperation, error) {
	return controller.scheduleCommand(
		ctx,
		"rollback",
		[]string{controller.config.RollbackTool},
		nil,
	)
}

func (controller *deliveryController) scheduleUninstall(ctx context.Context, mode string) (contract.PlatformWorkflowOperation, error) {
	if controller.config.UninstallTool == "" {
		return contract.PlatformWorkflowOperation{}, errors.New("platform uninstall tool is not configured")
	}
	return controller.scheduleCommand(
		ctx,
		"uninstall",
		[]string{controller.config.UninstallTool, "--mode", mode},
		nil,
	)
}

func (controller *deliveryController) scheduleSupportExport(ctx context.Context) (contract.PlatformWorkflowOperation, error) {
	if controller.config.SupportExportTool == "" {
		return contract.PlatformWorkflowOperation{}, errors.New("platform support export tool is not configured")
	}
	return controller.scheduleCommand(
		ctx,
		"support-export",
		[]string{controller.config.SupportExportTool},
		nil,
	)
}

func (controller *deliveryController) scheduleCommand(
	ctx context.Context,
	kind string,
	command []string,
	preflight func() error,
) (contract.PlatformWorkflowOperation, error) {
	current := owner.ReadPlatformWorkflow(controller.config.WorkflowDocument)
	if current.State == "loaded" && current.Operation != nil && (current.Operation.State == "accepted" || current.Operation.State == "running") {
		return *current.Operation, fmt.Errorf(
			"platform workflow is already active operationId=%s kind=%s state=%s",
			current.Operation.OperationID, current.Operation.Kind, current.Operation.State,
		)
	}
	if preflight != nil {
		if err := preflight(); err != nil {
			return contract.PlatformWorkflowOperation{}, err
		}
	}
	operationID, err := newWorkflowOperationID()
	if err != nil {
		return contract.PlatformWorkflowOperation{}, err
	}
	now := controller.now().UTC().Format(time.RFC3339Nano)
	operation := contract.PlatformWorkflowOperation{
		SchemaVersion: 1,
		OperationID:   operationID,
		Kind:          kind,
		State:         "accepted",
		StartedAt:     now,
		UpdatedAt:     now,
	}
	if err := owner.WritePlatformWorkflow(controller.config.WorkflowDocument, operation); err != nil {
		return contract.PlatformWorkflowOperation{}, err
	}
	unitKind := strings.ReplaceAll(kind, "-", "_")
	unit := fmt.Sprintf("vitalserver-%s-%s", unitKind, operationID[len(operationID)-12:])
	commandArguments := append([]string(nil), command[1:]...)
	commandArguments = append(commandArguments,
		"--operation-id", operationID,
		"--operation-document", controller.config.WorkflowDocument,
	)
	executable, arguments, err := controller.schedulerInvocation(unit, command[0], commandArguments)
	if err != nil {
		operation.State = "failed"
		operation.UpdatedAt = controller.now().UTC().Format(time.RFC3339Nano)
		operation.Failure = &contract.PlatformCommandFailure{Kind: "workflowScheduleFailed", Message: err.Error()}
		if writeErr := owner.WritePlatformWorkflow(controller.config.WorkflowDocument, operation); writeErr != nil {
			return operation, fmt.Errorf("workflow scheduler configuration failed: %v; failure owner write failed: %w", err, writeErr)
		}
		return operation, err
	}
	context, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if _, err := controller.runner.Run(context, executable, arguments...); err != nil {
		operation.State = "failed"
		operation.UpdatedAt = controller.now().UTC().Format(time.RFC3339Nano)
		operation.Failure = &contract.PlatformCommandFailure{Kind: "workflowScheduleFailed", Message: err.Error()}
		if writeErr := owner.WritePlatformWorkflow(controller.config.WorkflowDocument, operation); writeErr != nil {
			return operation, fmt.Errorf("workflow schedule failed: %v; failure owner write failed: %w", err, writeErr)
		}
		return operation, err
	}
	return operation, nil
}

func (controller *deliveryController) toolInvocation(tool string, arguments ...string) (string, []string, error) {
	switch controller.config.SchedulerKind {
	case DeliverySchedulerSystemdTransient:
		return tool, arguments, nil
	case DeliverySchedulerWindowsTask:
		arguments, err := windowsPowerShellArguments(arguments)
		if err != nil {
			return "", nil, err
		}
		return controller.config.SchedulerExecutable, append([]string{
			"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", tool,
		}, arguments...), nil
	default:
		return "", nil, fmt.Errorf("unsupported delivery scheduler kind=%q", controller.config.SchedulerKind)
	}
}

func (controller *deliveryController) schedulerInvocation(
	unit string,
	tool string,
	toolArguments []string,
) (string, []string, error) {
	switch controller.config.SchedulerKind {
	case DeliverySchedulerSystemdTransient:
		arguments := []string{"--unit=" + unit, "--collect", "--no-block", "--service-type=exec", tool}
		return controller.config.SchedulerExecutable, append(arguments, toolArguments...), nil
	case DeliverySchedulerWindowsTask:
		toolArguments, err := windowsPowerShellArguments(toolArguments)
		if err != nil {
			return "", nil, err
		}
		encoded, err := json.Marshal(toolArguments)
		if err != nil {
			return "", nil, fmt.Errorf("Windows workflow arguments encode failed: %w", err)
		}
		return controller.config.SchedulerExecutable, []string{
			"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
			"-File", controller.config.SchedulerScript,
			"-TaskName", unit,
			"-Tool", tool,
			"-ArgumentsBase64", base64.StdEncoding.EncodeToString(encoded),
			"-PowerShellExecutable", controller.config.SchedulerExecutable,
		}, nil
	default:
		return "", nil, fmt.Errorf("unsupported delivery scheduler kind=%q", controller.config.SchedulerKind)
	}
}

func windowsPowerShellArguments(arguments []string) ([]string, error) {
	aliases := map[string]string{
		"--bundle":             "-Bundle",
		"--operation-id":       "-OperationId",
		"--operation-document": "-OperationDocument",
		"--mode":               "-Mode",
	}
	result := make([]string, len(arguments))
	for index, argument := range arguments {
		if strings.HasPrefix(argument, "--") {
			alias, exists := aliases[argument]
			if !exists {
				return nil, fmt.Errorf("unsupported Windows workflow tool argument=%q", argument)
			}
			result[index] = alias
			continue
		}
		result[index] = argument
	}
	return result, nil
}

func (controller *deliveryController) requireTrustedBundle(bundle string) error {
	if controller.config.ApplyPolicy != DeliveryApplyPolicySHA256Allowlist {
		return errUpdateApplyUnavailable
	}
	digests, err := readTrustedBundleDigests(controller.config.TrustedBundleDigests)
	if err != nil {
		return err
	}
	file, err := os.Open(bundle)
	if err != nil {
		return fmt.Errorf("%w: bundle read failed path=%s: %v", errTrustedDigestUnavailable, bundle, err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return fmt.Errorf("%w: bundle hash failed path=%s: %v", errTrustedDigestUnavailable, bundle, err)
	}
	actual := hex.EncodeToString(hash.Sum(nil))
	if _, trusted := digests[actual]; !trusted {
		return fmt.Errorf("%w: sha256=%s", errUpdateBundleUntrusted, actual)
	}
	return nil
}

func readTrustedBundleDigests(path string) (map[string]struct{}, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("%w: read failed path=%s: %v", errTrustedDigestUnavailable, path, err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var document trustedBundleDigestDocument
	if err := decoder.Decode(&document); err != nil {
		return nil, fmt.Errorf("%w: decode failed path=%s: %v", errTrustedDigestUnavailable, path, err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("%w: trailing JSON content path=%s", errTrustedDigestUnavailable, path)
	}
	if document.SchemaVersion != 1 || len(document.SHA256) == 0 {
		return nil, fmt.Errorf("%w: invalid schema or empty sha256 list path=%s", errTrustedDigestUnavailable, path)
	}
	digests := make(map[string]struct{}, len(document.SHA256))
	for _, digest := range document.SHA256 {
		decoded, err := hex.DecodeString(digest)
		if err != nil || len(decoded) != sha256.Size || digest != strings.ToLower(digest) {
			return nil, fmt.Errorf("%w: invalid lowercase sha256 digest=%q path=%s", errTrustedDigestUnavailable, digest, path)
		}
		if _, duplicate := digests[digest]; duplicate {
			return nil, fmt.Errorf("%w: duplicate sha256 digest=%s path=%s", errTrustedDigestUnavailable, digest, path)
		}
		digests[digest] = struct{}{}
	}
	return digests, nil
}

func newWorkflowOperationID() (string, error) {
	data := make([]byte, 16)
	if _, err := rand.Read(data); err != nil {
		return "", fmt.Errorf("platform workflow operation identity generation failed: %w", err)
	}
	return "workflow-" + hex.EncodeToString(data), nil
}

func requiredLocalBundle(request *http.Request) (string, error) {
	var body updateBundleRequest
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil {
		return "", fmt.Errorf("update bundle request decode failed: %w", err)
	}
	if body.Bundle.Kind != "localPath" {
		return "", fmt.Errorf("update bundle reference kind must be localPath actual=%q", body.Bundle.Kind)
	}
	if body.Bundle.Value == "" || !filepath.IsAbs(body.Bundle.Value) {
		return "", errors.New("update bundle localPath must be an absolute path")
	}
	info, err := os.Stat(body.Bundle.Value)
	if err != nil {
		return "", fmt.Errorf("update bundle localPath read failed path=%s: %w", body.Bundle.Value, err)
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("update bundle localPath is not a regular file: %s", body.Bundle.Value)
	}
	return body.Bundle.Value, nil
}
