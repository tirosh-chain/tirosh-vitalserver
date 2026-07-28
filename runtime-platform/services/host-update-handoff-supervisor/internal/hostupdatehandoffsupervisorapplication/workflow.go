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

type HostUpdateInterruptionMonitor interface {
	ObserveInterruption(context.Context, string, string, time.Duration) (hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation, bool, error)
	WaitForInterruption(context.Context, string, string, time.Duration, time.Duration) (hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation, error)
}

type HostUpdateInterruptionConfirmationPublisher interface {
	PublishInterruptionConfirmation(context.Context, string, time.Duration, hostupdatehandoffsupervisordomain.HostUpdateInterruptionConfirmation) error
}

type HostUpdateHandoffSupervisorClock interface {
	Now() time.Time
}

type HostUpdateHandoffSupervisorWorkflow struct {
	inputReader StagedNextUpdaterDispatchInputReader
	process     StagedNextUpdaterProcess
	monitor     HostUpdateInterruptionMonitor
	publisher   HostUpdateInterruptionConfirmationPublisher
	clock       HostUpdateHandoffSupervisorClock
}

func NewHostUpdateHandoffSupervisorWorkflow(inputReader StagedNextUpdaterDispatchInputReader, process StagedNextUpdaterProcess, monitor HostUpdateInterruptionMonitor, publisher HostUpdateInterruptionConfirmationPublisher, clock HostUpdateHandoffSupervisorClock) (*HostUpdateHandoffSupervisorWorkflow, error) {
	if inputReader == nil || process == nil || monitor == nil || publisher == nil || clock == nil {
		return nil, fmt.Errorf("handoff input reader, next-updater process, interruption monitor, confirmation publisher, and clock are required")
	}
	return &HostUpdateHandoffSupervisorWorkflow{inputReader: inputReader, process: process, monitor: monitor, publisher: publisher, clock: clock}, nil
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
	processContext, cancelProcess := context.WithCancel(ctx)
	defer cancelProcess()
	type processResult struct {
		submission hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission
		err        error
	}
	processResults := make(chan processResult, 1)
	go func() {
		submission, processErr := workflow.process.Dispatch(processContext, input)
		processResults <- processResult{submission: submission, err: processErr}
	}()
	monitorContext, cancelMonitor := context.WithCancel(ctx)
	defer cancelMonitor()
	type interruptionResult struct {
		observation hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation
		err         error
	}
	interruptionResults := make(chan interruptionResult, 1)
	go func() {
		observation, monitorErr := workflow.monitor.WaitForInterruption(monitorContext, configuration.HostLocalAdministrationDescriptorPath, input.UpdateID, time.Duration(configuration.ServicePollIntervalMilliseconds)*time.Millisecond, time.Duration(configuration.CompletionTimeoutMilliseconds)*time.Millisecond)
		interruptionResults <- interruptionResult{observation: observation, err: monitorErr}
	}()
	var submission hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission
	select {
	case result := <-processResults:
		cancelMonitor()
		if result.err != nil {
			observation, interrupted, observationErr := workflow.monitor.ObserveInterruption(ctx, configuration.HostLocalAdministrationDescriptorPath, input.UpdateID, time.Duration(configuration.CompletionTimeoutMilliseconds)*time.Millisecond)
			if observationErr != nil {
				return workflow.failureReceipt(attemptID, startedAt, input, classifyDispatchFailure(observationErr)), nil
			}
			if interrupted {
				return workflow.confirmInterruptedProcess(ctx, configuration, attemptID, startedAt, input, observation), nil
			}
			return workflow.failureReceipt(attemptID, startedAt, input, classifyDispatchFailure(result.err)), nil
		}
		submission = result.submission
	case interruption := <-interruptionResults:
		cancelProcess()
		<-processResults
		if interruption.err != nil {
			return workflow.failureReceipt(attemptID, startedAt, input, classifyDispatchFailure(interruption.err)), nil
		}
		return workflow.confirmInterruptedProcess(ctx, configuration, attemptID, startedAt, input, interruption.observation), nil
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

func (workflow *HostUpdateHandoffSupervisorWorkflow) confirmInterruptedProcess(ctx context.Context, configuration hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration, attemptID string, startedAt string, input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput, observation hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation) hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt {
	if err := hostupdatehandoffsupervisordomain.ValidateHostUpdateInterruptionObservation(observation, input.UpdateID); err != nil {
		return workflow.failureReceipt(attemptID, startedAt, input, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "host-update-interruption-observation-invalid", Message: err.Error(), Dependency: "host-agent"}})
	}
	confirmation, err := hostupdatehandoffsupervisordomain.NewHostUpdateInterruptionConfirmation(attemptID, observation, workflow.now())
	if err != nil {
		return workflow.failureReceipt(attemptID, startedAt, input, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "host-update-interruption-confirmation-invalid", Message: err.Error(), Dependency: "host-update-handoff-supervisor"}})
	}
	if err := workflow.publisher.PublishInterruptionConfirmation(ctx, configuration.HostLocalAdministrationDescriptorPath, time.Duration(configuration.CompletionTimeoutMilliseconds)*time.Millisecond, confirmation); err != nil {
		return workflow.failureReceipt(attemptID, startedAt, input, classifyDispatchFailure(err))
	}
	return workflow.failureReceipt(attemptID, startedAt, input, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "next-updater-interrupted", Message: "staged next-updater termination was confirmed to Host Agent", Dependency: "host-update-handoff-supervisor"}})
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
