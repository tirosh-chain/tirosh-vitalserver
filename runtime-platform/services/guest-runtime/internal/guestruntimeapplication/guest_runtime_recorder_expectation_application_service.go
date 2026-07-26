package guestruntimeapplication

import (
	"context"
	"errors"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func (service *GuestRuntimeObservationCatalogApplicationService) ApplyRecorderExpectation(
	ctx context.Context,
	recorderID string,
	command guestruntimedomain.RecorderObservabilityExpectationCommand,
) (guestruntimedomain.RecorderExpectationReceipt, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateRecorderObservabilityExpectationCommand(recorderID, command); issue != nil {
		_, rejection, failure := service.commandRejection(command.RequestID, *issue)
		return guestruntimedomain.RecorderExpectationReceipt{}, rejection, failure
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "not-admitted", catalogIssue("recorder-expectation-command-digest-failed", "Recorder Catalog could not calculate the expectation command digest", true))
	}
	storedEvent, err := service.repository.ReadRecorderExpectationEventByRequestID(ctx, command.RequestID)
	if err == nil {
		if storedEvent.CommandDigest == digest {
			return guestruntimedomain.NewRecorderExpectationReceipt(storedEvent.Event), nil, nil
		}
		_, rejection, failure := service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Recorder expectation command"})
		return guestruntimedomain.RecorderExpectationReceipt{}, rejection, failure
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "not-admitted", catalogIssue("recorder-expectation-state-store-read-failed", "Recorder Catalog could not read expectation request ownership", true))
	}
	var previous *guestruntimedomain.RecorderExpectation
	storedExpectation, err := service.repository.ReadRecorderExpectation(ctx, recorderID)
	if err == nil {
		previous = &storedExpectation
	} else if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "not-admitted", catalogIssue("recorder-expectation-state-store-read-failed", "Recorder Catalog could not read the current expectation", true))
	}
	var current *guestruntimedomain.RecorderObservabilitySummary
	expectedSummaryRevision := 0
	storedSummary, err := service.repository.ReadRecorderObservabilitySummary(ctx, recorderID)
	if err == nil {
		current = &storedSummary
		expectedSummaryRevision = storedSummary.ResourceRevision
	} else if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "not-admitted", catalogIssue("observation-catalog-state-store-read-failed", "Recorder Catalog could not read the current Recorder summary", true))
	}
	eventID, err := service.identifiers.NewRequestCorrelationIdentifier("recorder-expectation-event")
	if err != nil {
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "not-admitted", catalogIssue("recorder-expectation-event-id-unavailable", "Recorder Catalog could not allocate an expectation event identifier", true))
	}
	now := service.clock.Now()
	event, expectation, summary, err := guestruntimedomain.DecideRecorderExpectation(recorderID, eventID, command, previous, current, now, now, now)
	if err != nil {
		if err.Error() == "recorder-expectation-revision-conflict" {
			_, rejection, failure := service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "recorder-expectation-revision-conflict", Message: "expectedResourceRevision does not match the Recorder expectation revision"})
			return guestruntimedomain.RecorderExpectationReceipt{}, rejection, failure
		}
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "not-admitted", catalogIssue("recorder-expectation-transition-invalid", "Recorder Catalog could not decide the expectation transition", false))
	}
	if err := service.repository.CommitRecorderExpectation(ctx, event, digest, expectation, summary, expectedSummaryRevision); err != nil {
		if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
			stored, readErr := service.repository.ReadRecorderExpectationEventByRequestID(ctx, command.RequestID)
			if readErr == nil && stored.CommandDigest == digest {
				return guestruntimedomain.NewRecorderExpectationReceipt(stored.Event), nil, nil
			}
		}
		return guestruntimedomain.RecorderExpectationReceipt{}, nil, service.newAdmissionFailure(command.RequestID, "unknown", catalogIssue("recorder-expectation-write-outcome-unknown", "Recorder Catalog could not determine whether the expectation was durably persisted", true))
	}
	return guestruntimedomain.NewRecorderExpectationReceipt(event), nil, nil
}
