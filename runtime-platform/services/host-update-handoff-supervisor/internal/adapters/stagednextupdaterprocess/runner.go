// Package stagednextupdaterprocess is the OS process adapter for the C25
// selected next updater. Its argument list is constructed entirely from C56
// and verified C31/C30/C25 input; it never accepts a command string.
package stagednextupdaterprocess

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

const maximumCompletionCommandBytes = 1 << 20

type StagedNextUpdaterProcessRunner struct{}

type updateCompletionCommand struct {
	SchemaVersion           string          `json:"schemaVersion"`
	UpdateID                string          `json:"updateId"`
	ExpectedJournalRevision int             `json:"expectedJournalRevision"`
	Report                  json.RawMessage `json:"report"`
}

func (StagedNextUpdaterProcessRunner) Dispatch(ctx context.Context, input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput) (hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission, error) {
	if err := hostupdatehandoffsupervisordomain.ValidateDispatchInput(input); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-dispatch-input-invalid", Message: err.Error(), Dependency: "host-update-handoff-supervisor"}}
	}
	if err := os.MkdirAll(input.LayerEffectReceiptPath, 0o700); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "unavailable", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "layer-effect-receipt-directory-unavailable", Message: err.Error(), Dependency: "host-update-evidence"}}
	}
	timeout := time.Duration(input.LayerEffectTimeoutMilliseconds+input.CompletionTimeoutMilliseconds) * time.Millisecond
	if timeout <= 0 {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-timeout-invalid", Message: "combined next-updater timeout is invalid", Dependency: "host-update-handoff-supervisor"}}
	}
	boundedContext, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	if input.ExecutionMode == "execute" {
		if err := runNextUpdaterExecution(boundedContext, input); err != nil {
			return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{}, err
		}
	}
	completionCommand, err := runNextUpdaterCompletion(boundedContext, input)
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{}, err
	}
	if err := validateCompletionCommand(completionCommand, input); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-completion-command-invalid", Message: err.Error(), Dependency: "staged-next-updater"}}
	}
	digest := sha256.Sum256(completionCommand)
	return hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{CompletionCommandSHA256: hex.EncodeToString(digest[:])}, nil
}

func runNextUpdaterExecution(ctx context.Context, input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput) error {
	arguments := []string{"--mode", "execute", "--invocation", input.InvocationPath, "--report", input.ExecutionReportPath, "--layer-effect-receipt-directory", input.LayerEffectReceiptPath, "--layer-effect-timeout", fmt.Sprintf("%dms", input.LayerEffectTimeoutMilliseconds)}
	command := exec.CommandContext(ctx, input.NextUpdaterPath, arguments...)
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err := command.Run(); err != nil {
		return hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-process-failed", Message: err.Error(), Dependency: "staged-next-updater"}}
	}
	return nil
}

func runNextUpdaterCompletion(ctx context.Context, input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput) ([]byte, error) {
	arguments := []string{"--mode", "complete", "--invocation", input.InvocationPath, "--report", input.ExecutionReportPath, "--completion-descriptor", input.CompletionDescriptorPath, "--completion-timeout", fmt.Sprintf("%dms", input.CompletionTimeoutMilliseconds)}
	command := exec.CommandContext(ctx, input.NextUpdaterPath, arguments...)
	var standardOutput limitedBuffer
	standardOutput.limit = maximumCompletionCommandBytes
	command.Stdout = &standardOutput
	command.Stderr = io.Discard
	if err := command.Run(); err != nil {
		return nil, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-process-failed", Message: err.Error(), Dependency: "staged-next-updater"}}
	}
	if standardOutput.exceeded {
		return nil, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-completion-command-oversized", Message: "staged next updater wrote an oversized C27 completion command", Dependency: "staged-next-updater"}}
	}
	return standardOutput.Bytes(), nil
}

func validateCompletionCommand(contents []byte, input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var command updateCompletionCommand
	if err := decoder.Decode(&command); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("C27 completion command must contain one JSON object")
	}
	if command.SchemaVersion != hostupdatehandoffsupervisordomain.SchemaVersion || command.UpdateID != input.UpdateID || command.ExpectedJournalRevision != input.ExpectedHandoffJournalRevision || len(command.Report) == 0 {
		return fmt.Errorf("C27 completion command does not correlate to C30")
	}
	return nil
}

type limitedBuffer struct {
	bytes.Buffer
	limit    int
	exceeded bool
}

func (buffer *limitedBuffer) Write(value []byte) (int, error) {
	remaining := buffer.limit - buffer.Len()
	if remaining <= 0 {
		buffer.exceeded = true
		return len(value), nil
	}
	if len(value) > remaining {
		_, _ = buffer.Buffer.Write(value[:remaining])
		buffer.exceeded = true
		return len(value), nil
	}
	return buffer.Buffer.Write(value)
}
