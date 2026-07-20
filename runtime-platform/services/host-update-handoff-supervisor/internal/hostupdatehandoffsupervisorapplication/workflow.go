// Package hostupdatehandoffsupervisorapplication orchestrates one explicit
// C31 dispatch. It has no filesystem, process, or Host SQLite implementation.
package hostupdatehandoffsupervisorapplication

import (
	"context"
	"fmt"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

type StagedNextUpdaterDispatchInputReader interface {
	Read(hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration, string) (hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput, error)
}

type StagedNextUpdaterProcess interface {
	Dispatch(context.Context, hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput) (hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission, error)
}

type HostUpdateHandoffSupervisorClock interface {
	Now() time.Time
}

type HostUpdateHandoffSupervisorWorkflow struct {
	inputReader StagedNextUpdaterDispatchInputReader
	process     StagedNextUpdaterProcess
	clock       HostUpdateHandoffSupervisorClock
}

func NewHostUpdateHandoffSupervisorWorkflow(inputReader StagedNextUpdaterDispatchInputReader, process StagedNextUpdaterProcess, clock HostUpdateHandoffSupervisorClock) (*HostUpdateHandoffSupervisorWorkflow, error) {
	if inputReader == nil || process == nil || clock == nil {
		return nil, fmt.Errorf("C31 input reader, next-updater process, and clock are required")
	}
	return &HostUpdateHandoffSupervisorWorkflow{inputReader: inputReader, process: process, clock: clock}, nil
}

// Dispatch reads one explicitly named C31 handoff and produces a receipt that
// says only whether C27 submission was observed. C29 remains the sole Host
// update settlement state and can report either a succeeded or failed update.
func (workflow *HostUpdateHandoffSupervisorWorkflow) Dispatch(ctx context.Context, configuration hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration, attemptID string, handoffPath string) (hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt, error) {
	if err := hostupdatehandoffsupervisordomain.ValidateConfiguration(configuration); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, fmt.Errorf("validate C56 supervisor configuration: %w", err)
	}
	if attemptID == "" || handoffPath == "" {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, fmt.Errorf("C57 attempt id and C31 handoff path are required")
	}
	startedAt := workflow.now()
	input, err := workflow.inputReader.Read(configuration, handoffPath)
	if err != nil {
		return workflow.failureReceipt(attemptID, startedAt, hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyDispatchFailure(err)), nil
	}
	if err := hostupdatehandoffsupervisordomain.ValidateDispatchInput(input); err != nil {
		return workflow.failureReceipt(attemptID, startedAt, input, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-dispatch-input-invalid", Message: err.Error(), Dependency: "host-update-handoff-supervisor"}}), nil
	}
	submission, err := workflow.process.Dispatch(ctx, input)
	if err != nil {
		return workflow.failureReceipt(attemptID, startedAt, input, classifyDispatchFailure(err)), nil
	}
	if err := hostupdatehandoffsupervisordomain.ValidateCompletionSubmission(submission); err != nil {
		return workflow.failureReceipt(attemptID, startedAt, input, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-completion-submission-invalid", Message: err.Error(), Dependency: "staged-next-updater"}}), nil
	}
	return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{
		SchemaVersion:           hostupdatehandoffsupervisordomain.SchemaVersion,
		AttemptID:               attemptID,
		UpdateID:                input.UpdateID,
		InvocationRelativePath:  input.InvocationRelativePath,
		NextUpdaterSHA256:       input.NextUpdaterSHA256,
		ExecutionMode:           input.ExecutionMode,
		State:                   "completion-submitted",
		StartedAt:               startedAt,
		FinishedAt:              workflow.now(),
		Evidence:                hostupdatehandoffsupervisordomain.EvidenceReference{Kind: "host-update-handoff-dispatch", ID: attemptID},
		CompletionCommandSHA256: submission.CompletionCommandSHA256,
	}, nil
}

func (workflow *HostUpdateHandoffSupervisorWorkflow) failureReceipt(attemptID string, startedAt string, input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput, failure hostupdatehandoffsupervisordomain.DispatchFailure) hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt {
	state := failure.State
	if state != "failed" && state != "unavailable" {
		state = "failed"
	}
	return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{
		SchemaVersion:          hostupdatehandoffsupervisordomain.SchemaVersion,
		AttemptID:              attemptID,
		UpdateID:               input.UpdateID,
		InvocationRelativePath: input.InvocationRelativePath,
		NextUpdaterSHA256:      input.NextUpdaterSHA256,
		ExecutionMode:          input.ExecutionMode,
		State:                  state,
		StartedAt:              startedAt,
		FinishedAt:             workflow.now(),
		Evidence:               hostupdatehandoffsupervisordomain.EvidenceReference{Kind: "host-update-handoff-dispatch", ID: attemptID},
		Issue:                  &failure.Issue,
	}
}

func (workflow *HostUpdateHandoffSupervisorWorkflow) now() string {
	return workflow.clock.Now().UTC().Format(time.RFC3339)
}

func classifyDispatchFailure(err error) hostupdatehandoffsupervisordomain.DispatchFailure {
	var explicit hostupdatehandoffsupervisordomain.DispatchFailure
	if errorAs(err, &explicit) {
		return explicit
	}
	return hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-dispatch-failed", Message: err.Error(), Dependency: "staged-next-updater"}}
}

// errorAs is isolated to retain a small domain-facing error surface.
func errorAs(err error, target *hostupdatehandoffsupervisordomain.DispatchFailure) bool {
	for err != nil {
		if failure, ok := err.(hostupdatehandoffsupervisordomain.DispatchFailure); ok {
			*target = failure
			return true
		}
		type unwrap interface{ Unwrap() error }
		wrapped, ok := err.(unwrap)
		if !ok {
			return false
		}
		err = wrapped.Unwrap()
	}
	return false
}
