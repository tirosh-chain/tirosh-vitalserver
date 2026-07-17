package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeTelemetryPipelineApplicationService owns a node-local diagnostic pipeline. It creates
// explicit diagnostic operations and receipts, but does not receive a product
// operation repository or mutate product outcomes.
type GuestRuntimeTelemetryPipelineApplicationService struct {
	repository  GuestRuntimeTelemetryPipelineStateRepository
	exporter    GuestRuntimeTelemetryExporter
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	node        guestruntimedomain.NodeReference
	workflowMu  sync.Mutex
}

func NewGuestRuntimeTelemetryPipelineApplicationService(repository GuestRuntimeTelemetryPipelineStateRepository, exporter GuestRuntimeTelemetryExporter, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator, node guestruntimedomain.NodeReference) (*GuestRuntimeTelemetryPipelineApplicationService, error) {
	if repository == nil || exporter == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Telemetry Pipeline repository, exporter, clock, and identifier generator are required")
	}
	if node.Kind != "guest" || !guestruntimedomain.ValidIdentifier(node.ID) {
		return nil, fmt.Errorf("Guest Telemetry Pipeline requires an explicit guest node")
	}
	return &GuestRuntimeTelemetryPipelineApplicationService{repository: repository, exporter: exporter, clock: clock, identifiers: identifiers, node: node}, nil
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) ReadTelemetryPipeline(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-telemetry-pipeline-id", "pipelineId must be a v1 identifier")
	}
	pipeline, err := service.repository.ReadTelemetryPipeline(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "telemetry-pipeline-missing", "the requested TelemetryPipeline does not exist")
	}
	if err != nil {
		return failedRead(now, "telemetry-pipeline-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := pipeline.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: pipeline, SourceRevision: &revision}
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) ReadTelemetryEmissionReceipt(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-telemetry-emission-receipt-id", "receiptId must be a v1 identifier")
	}
	receipt, err := service.repository.ReadTelemetryEmissionReceipt(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "telemetry-emission-receipt-missing", "the requested TelemetryEmissionReceipt does not exist")
	}
	if err != nil {
		return failedRead(now, "telemetry-pipeline-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: receipt}
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) ApplyTelemetryPipeline(ctx context.Context, command guestruntimedomain.TelemetryPipelineApplyCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateTelemetryPipelineApplyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if command.Node != service.node {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "telemetry-pipeline-node-owner-mismatch", Message: "Guest Telemetry Pipeline can only manage its configured guest node"})
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-command-digest-failed", "Guest Telemetry Pipeline could not calculate the command digest", true))
	}
	existing, err := service.repository.ReadTelemetryPipelineOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == guestruntimedomain.TelemetryPipelineOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-state-store-read-failed", "Guest Telemetry Pipeline could not read command request ownership", true))
	}
	current, err := service.repository.ReadTelemetryPipeline(ctx, command.PipelineID)
	if err != nil && !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-state-store-read-failed", "Guest Telemetry Pipeline could not read its current resource", true))
	}
	createdAt := ""
	nextRevision := 1
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "TelemetryPipeline is missing, so expectedResourceRevision must be zero"})
		}
	} else {
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned TelemetryPipeline"})
		}
		createdAt = current.CreatedAt
		nextRevision = current.ResourceRevision + 1
	}
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-operation-id-unavailable", "Guest Telemetry Pipeline could not allocate an operation identifier", true))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(operationID, guestruntimedomain.TelemetryPipelineOperationKind, command.RequestID, guestruntimedomain.TelemetryPipelineResourceType, command.PipelineID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-operation-transition-failed", "Guest Telemetry Pipeline could not construct operation transitions", false))
	}
	if err := service.repository.AdmitTelemetryPipelineOperation(ctx, command.PipelineID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handlePipelineAdmissionFailure(ctx, command.RequestID, digest, err)
	}
	if createdAt == "" {
		createdAt = at
	}
	observedAt := service.clock.Now()
	observation, observationErr := service.exporter.ObserveTelemetryPipeline(ctx, service.node, command.Spec, guestruntimedomain.Timestamp(observedAt))
	if observationErr != nil {
		return operation, nil, nil
	}
	pipeline, buildErr := guestruntimedomain.NewTelemetryPipeline(command, nextRevision, createdAt, observedAt, observation)
	if buildErr != nil {
		issue := telemetryIssue("telemetry-pipeline-provider-contract-invalid", "Guest Telemetry exporter returned an invalid pipeline observation", false)
		pipeline, buildErr = guestruntimedomain.NewTelemetryPipeline(command, nextRevision, createdAt, observedAt, guestruntimedomain.TelemetryPipelineObservation{State: "failed", Issue: &issue})
		if buildErr != nil {
			return operation, nil, nil
		}
	}
	terminal, transitionErr := guestruntimedomain.TransitionOperation(operation, "succeeded", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: guestruntimedomain.TelemetryPipelineResourceType, ID: pipeline.ID}}
	if err := service.repository.CommitTelemetryPipelineOutcome(ctx, pipeline, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) EmitTelemetrySignal(ctx context.Context, command guestruntimedomain.TelemetrySignalEmitCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateTelemetrySignalEmitCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-signal-command-digest-failed", "Guest Telemetry Pipeline could not calculate the signal command digest", true))
	}
	existing, err := service.repository.ReadTelemetrySignalEmissionOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == guestruntimedomain.TelemetryEmitOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-state-store-read-failed", "Guest Telemetry Pipeline could not read signal request ownership", true))
	}
	pipeline, err := service.repository.ReadTelemetryPipeline(ctx, command.PipelineID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "telemetry-pipeline-missing", Message: "Telemetry signal references a missing TelemetryPipeline"})
	}
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-pipeline-state-store-read-failed", "Guest Telemetry Pipeline could not read its configured pipeline", true))
	}
	if pipeline.ResourceRevision != command.ExpectedResourceRevision {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned TelemetryPipeline"})
	}
	knownDigests, err := service.readKnownAttributeDigests(ctx, pipeline, command.Attributes)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-cardinality-state-read-failed", "Guest Telemetry Pipeline could not read bounded-cardinality state", true))
	}
	sanitized := guestruntimedomain.SanitizeTelemetryAttributes(pipeline.Spec.Redaction, command.Attributes, knownDigests)
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-signal-operation-id-unavailable", "Guest Telemetry Pipeline could not allocate a signal operation identifier", true))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(operationID, guestruntimedomain.TelemetryEmitOperationKind, command.RequestID, guestruntimedomain.TelemetryPipelineResourceType, command.PipelineID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", telemetryIssue("telemetry-signal-operation-transition-failed", "Guest Telemetry Pipeline could not construct signal operation transitions", false))
	}
	if err := service.repository.AdmitTelemetryEmissionOperation(ctx, command.PipelineID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handleEmissionAdmissionFailure(ctx, command.RequestID, digest, err)
	}
	result := telemetryResultForPipeline(pipeline)
	if len(sanitized.Attributes) == 0 && (len(sanitized.RedactedKeys) > 0 || len(sanitized.DroppedKeys) > 0) {
		issue := telemetryIssue("telemetry-signal-dropped-by-policy", "Telemetry signal has no attributes eligible for export after redaction and cardinality policy", false)
		result = guestruntimedomain.TelemetryExportResult{Outcome: "dropped", Issue: &issue}
	} else if pipeline.Status.State == "ready" {
		var exportErr error
		result, exportErr = service.exporter.ExportTelemetrySignal(ctx, pipeline, command.Signal, sanitized.Attributes, guestruntimedomain.Timestamp(service.clock.Now()))
		if exportErr != nil {
			return operation, nil, nil
		}
	}
	receiptID, err := service.identifiers.NewRequestCorrelationIdentifier("telemetry-receipt")
	if err != nil {
		return operation, nil, nil
	}
	receipt, receiptErr := guestruntimedomain.NewTelemetryEmissionReceipt(receiptID, command, pipeline, service.clock.Now(), sanitized, result)
	if receiptErr != nil {
		return operation, nil, nil
	}
	terminal, transitionErr := telemetryTerminalOperation(operation, result, guestruntimedomain.Timestamp(service.clock.Now()))
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: "telemetry-emission-receipt", ID: receipt.ID}}
	if err := service.repository.CommitTelemetryEmissionOutcome(ctx, receipt, sanitized.AttributeDigests, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) readKnownAttributeDigests(ctx context.Context, pipeline guestruntimedomain.TelemetryPipeline, attributes map[string]string) (map[string]map[string]bool, error) {
	known := map[string]map[string]bool{}
	for _, key := range pipeline.Spec.Redaction.AllowedAttributeKeys {
		if _, present := attributes[key]; !present {
			continue
		}
		digests, err := service.repository.ReadTelemetryAttributeValueDigests(ctx, pipeline.ID, key)
		if err != nil {
			return nil, err
		}
		known[key] = map[string]bool{}
		for _, digest := range digests {
			known[key][digest] = true
		}
	}
	return known, nil
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", telemetryIssue("telemetry-rejection-correlation-unavailable", "Guest Telemetry Pipeline could not allocate a rejection correlation identifier", true))
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) newAdmissionFailure(requestID string, state string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: state, Issue: issue}
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) handlePipelineAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned TelemetryPipeline"})
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadTelemetryPipelineOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == guestruntimedomain.TelemetryPipelineOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", telemetryIssue("telemetry-pipeline-state-store-write-outcome-unknown", "Guest Telemetry Pipeline could not determine whether the operation was durably admitted", true))
}

func (service *GuestRuntimeTelemetryPipelineApplicationService) handleEmissionAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned TelemetryPipeline"})
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadTelemetrySignalEmissionOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == guestruntimedomain.TelemetryEmitOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", telemetryIssue("telemetry-emission-state-store-write-outcome-unknown", "Guest Telemetry Pipeline could not determine whether the emission operation was durably admitted", true))
}

func telemetryResultForPipeline(pipeline guestruntimedomain.TelemetryPipeline) guestruntimedomain.TelemetryExportResult {
	if pipeline.Status.State == "ready" {
		return guestruntimedomain.TelemetryExportResult{Outcome: "exported"}
	}
	issue := pipeline.Status.Issue
	if issue == nil {
		generated := telemetryIssue("telemetry-pipeline-status-invariant-failed", "non-ready TelemetryPipeline has no typed issue", false)
		issue = &generated
	}
	if pipeline.Status.State == "failed" {
		return guestruntimedomain.TelemetryExportResult{Outcome: "failed", Issue: issue}
	}
	return guestruntimedomain.TelemetryExportResult{Outcome: "unavailable", Issue: issue}
}

func telemetryTerminalOperation(operation guestruntimedomain.Operation, result guestruntimedomain.TelemetryExportResult, at string) (guestruntimedomain.Operation, error) {
	if result.Outcome == "exported" || result.Outcome == "dropped" {
		return guestruntimedomain.TransitionOperation(operation, "succeeded", at, nil)
	}
	return guestruntimedomain.TransitionOperation(operation, "failed", at, result.Issue)
}

func telemetryIssue(code string, message string, retryable bool) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(retryable), Dependency: "telemetry-pipeline"}
}
