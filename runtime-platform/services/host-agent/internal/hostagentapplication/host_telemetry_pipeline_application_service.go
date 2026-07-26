package hostagentapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// HostTelemetryPipelineApplicationService owns Host diagnostic telemetry only. Guest
// forwarding and lifecycle workflows do not depend on its receipt state.
type HostTelemetryPipelineApplicationService struct {
	repository  HostTelemetryPipelineStateRepository
	exporter    HostTelemetryExporter
	clock       HostAgentClock
	identifiers HostAgentRequestCorrelationIdentifierGenerator
	node        hostagentdomain.NodeReference
	workflowMu  sync.Mutex
}

func NewHostTelemetryPipelineApplicationService(repository HostTelemetryPipelineStateRepository, exporter HostTelemetryExporter, clock HostAgentClock, identifiers HostAgentRequestCorrelationIdentifierGenerator, node hostagentdomain.NodeReference) (*HostTelemetryPipelineApplicationService, error) {
	if repository == nil || exporter == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Host Telemetry Pipeline repository, exporter, clock, and identifier generator are required")
	}
	if node.Kind != "host" || !hostagentdomain.ValidIdentifier(node.ID) {
		return nil, fmt.Errorf("Host Telemetry Pipeline requires an explicit host node")
	}
	return &HostTelemetryPipelineApplicationService{repository: repository, exporter: exporter, clock: clock, identifiers: identifiers, node: node}, nil
}

func (service *HostTelemetryPipelineApplicationService) ReadHostTelemetryPipeline(ctx context.Context, id string) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	if !hostagentdomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-telemetry-pipeline-id", "pipelineId must be a v1 identifier")
	}
	pipeline, err := service.repository.ReadHostTelemetryPipeline(ctx, id)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "telemetry-pipeline-missing", "the requested Host TelemetryPipeline does not exist")
	}
	if err != nil {
		return failedRead(now, "telemetry-pipeline-state-store-read-failed", err.Error(), "host-state-store")
	}
	revision := pipeline.ResourceRevision
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: pipeline, SourceRevision: &revision}
}

func (service *HostTelemetryPipelineApplicationService) ReadHostTelemetryEmissionReceipt(ctx context.Context, id string) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	if !hostagentdomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-telemetry-emission-receipt-id", "receiptId must be a v1 identifier")
	}
	receipt, err := service.repository.ReadHostTelemetryEmissionReceipt(ctx, id)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "telemetry-emission-receipt-missing", "the requested Host TelemetryEmissionReceipt does not exist")
	}
	if err != nil {
		return failedRead(now, "telemetry-pipeline-state-store-read-failed", err.Error(), "host-state-store")
	}
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: receipt}
}

func (service *HostTelemetryPipelineApplicationService) ApplyHostTelemetryPipelineCommand(ctx context.Context, command hostagentdomain.TelemetryPipelineApplyCommand) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := hostagentdomain.ValidateTelemetryPipelineApplyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if command.Node != service.node {
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "telemetry-pipeline-node-owner-mismatch", Message: "Host Telemetry Pipeline can only manage its configured host node"})
	}
	digest, err := hostagentdomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-command-digest-failed", "Host Telemetry Pipeline could not calculate the command digest", true))
	}
	existing, err := service.repository.ReadHostTelemetryPipelineOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == hostagentdomain.TelemetryPipelineOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host command"})
	}
	if !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-state-store-read-failed", "Host Telemetry Pipeline could not read command request ownership", true))
	}
	current, err := service.repository.ReadHostTelemetryPipeline(ctx, command.PipelineID)
	if err != nil && !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-state-store-read-failed", "Host Telemetry Pipeline could not read its current resource", true))
	}
	createdAt, nextRevision := "", 1
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "TelemetryPipeline is missing, so expectedResourceRevision must be zero"})
		}
	} else {
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned TelemetryPipeline"})
		}
		createdAt, nextRevision = current.CreatedAt, current.ResourceRevision+1
	}
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("host-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-operation-id-unavailable", "Host Telemetry Pipeline could not allocate an operation identifier", true))
	}
	at := hostagentdomain.Timestamp(service.clock.Now())
	operation, err := runningOperationalOperation(operationID, hostagentdomain.TelemetryPipelineOperationKind, command.RequestID, hostagentdomain.TelemetryPipelineResourceType, command.PipelineID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-operation-transition-failed", "Host Telemetry Pipeline could not construct operation transitions", false))
	}
	if err := service.repository.AdmitHostTelemetryPipelineOperation(ctx, command.PipelineID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handlePipelineAdmissionFailure(ctx, command.RequestID, digest, err)
	}
	if createdAt == "" {
		createdAt = at
	}
	observedAt := service.clock.Now()
	observation, observeErr := service.exporter.ObserveTelemetryPipeline(ctx, service.node, command.Spec, hostagentdomain.Timestamp(observedAt))
	if observeErr != nil {
		return operation, nil, nil
	}
	pipeline, buildErr := hostagentdomain.NewTelemetryPipeline(command, nextRevision, createdAt, observedAt, observation)
	if buildErr != nil {
		issue := hostTelemetryIssue("telemetry-pipeline-provider-contract-invalid", "Host Telemetry exporter returned an invalid pipeline observation", false)
		pipeline, buildErr = hostagentdomain.NewTelemetryPipeline(command, nextRevision, createdAt, observedAt, hostagentdomain.TelemetryPipelineObservation{State: "failed", Issue: &issue})
		if buildErr != nil {
			return operation, nil, nil
		}
	}
	terminal, transitionErr := hostagentdomain.TransitionOperation(operation, "succeeded", hostagentdomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []hostagentdomain.EvidenceReference{{Kind: hostagentdomain.TelemetryPipelineResourceType, ID: pipeline.ID}}
	if err := service.repository.CommitHostTelemetryPipelineOutcome(ctx, pipeline, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *HostTelemetryPipelineApplicationService) EmitHostTelemetrySignal(ctx context.Context, command hostagentdomain.TelemetrySignalEmitCommand) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := hostagentdomain.ValidateTelemetrySignalEmitCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := hostagentdomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-signal-command-digest-failed", "Host Telemetry Pipeline could not calculate the signal command digest", true))
	}
	existing, err := service.repository.ReadHostTelemetryEmissionOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == hostagentdomain.TelemetryEmitOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host command"})
	}
	if !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-state-store-read-failed", "Host Telemetry Pipeline could not read signal request ownership", true))
	}
	pipeline, err := service.repository.ReadHostTelemetryPipeline(ctx, command.PipelineID)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "telemetry-pipeline-missing", Message: "Telemetry signal references a missing Host TelemetryPipeline"})
	}
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-pipeline-state-store-read-failed", "Host Telemetry Pipeline could not read its pipeline", true))
	}
	if pipeline.ResourceRevision != command.ExpectedResourceRevision {
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned TelemetryPipeline"})
	}
	known, err := service.readKnownDigests(ctx, pipeline, command.Attributes)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-cardinality-state-read-failed", "Host Telemetry Pipeline could not read bounded-cardinality state", true))
	}
	sanitized := hostagentdomain.SanitizeTelemetryAttributes(pipeline.Spec.Redaction, command.Attributes, known)
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("host-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-signal-operation-id-unavailable", "Host Telemetry Pipeline could not allocate a signal operation identifier", true))
	}
	at := hostagentdomain.Timestamp(service.clock.Now())
	operation, err := runningOperationalOperation(operationID, hostagentdomain.TelemetryEmitOperationKind, command.RequestID, hostagentdomain.TelemetryPipelineResourceType, command.PipelineID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTelemetryIssue("telemetry-signal-operation-transition-failed", "Host Telemetry Pipeline could not construct signal operation transitions", false))
	}
	if err := service.repository.AdmitHostTelemetryEmissionOperation(ctx, command.PipelineID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handleEmissionAdmissionFailure(ctx, command.RequestID, digest, err)
	}
	result := hostResultForPipeline(pipeline)
	if len(sanitized.Attributes) == 0 && (len(sanitized.RedactedKeys) > 0 || len(sanitized.DroppedKeys) > 0) {
		issue := hostTelemetryIssue("telemetry-signal-dropped-by-policy", "Telemetry signal has no attributes eligible for export after redaction and cardinality policy", false)
		result = hostagentdomain.TelemetryExportResult{Outcome: "dropped", Issue: &issue}
	} else if pipeline.Status.State == "ready" {
		result, err = service.exporter.ExportTelemetrySignal(ctx, pipeline, command.Signal, sanitized.Attributes, hostagentdomain.Timestamp(service.clock.Now()))
		if err != nil {
			return operation, nil, nil
		}
	}
	receiptID, err := service.identifiers.NewRequestCorrelationIdentifier("telemetry-receipt")
	if err != nil {
		return operation, nil, nil
	}
	receipt, receiptErr := hostagentdomain.NewTelemetryEmissionReceipt(receiptID, command, pipeline, service.clock.Now(), sanitized, result)
	if receiptErr != nil {
		return operation, nil, nil
	}
	terminal, transitionErr := terminalTelemetryOperation(operation, result, hostagentdomain.Timestamp(service.clock.Now()))
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []hostagentdomain.EvidenceReference{{Kind: "telemetry-emission-receipt", ID: receipt.ID}}
	if err := service.repository.CommitHostTelemetryEmissionOutcome(ctx, receipt, sanitized.AttributeDigests, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *HostTelemetryPipelineApplicationService) readKnownDigests(ctx context.Context, pipeline hostagentdomain.TelemetryPipeline, attributes map[string]string) (map[string]map[string]bool, error) {
	known := map[string]map[string]bool{}
	for _, key := range pipeline.Spec.Redaction.AllowedAttributeKeys {
		if _, present := attributes[key]; !present {
			continue
		}
		digests, err := service.repository.ReadHostTelemetryAttributeValueDigests(ctx, pipeline.ID, key)
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

func (service *HostTelemetryPipelineApplicationService) commandRejection(requestID string, issue hostagentdomain.Issue) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if !hostagentdomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", hostTelemetryIssue("telemetry-rejection-correlation-unavailable", "Host Telemetry Pipeline could not allocate a rejection correlation identifier", true))
		}
		requestID = generated
	}
	return hostagentdomain.Operation{}, &hostagentdomain.CommandRejection{SchemaVersion: hostagentdomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *HostTelemetryPipelineApplicationService) admissionFailure(requestID string, state string, issue hostagentdomain.Issue) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}
func (service *HostTelemetryPipelineApplicationService) newAdmissionFailure(requestID string, state string, issue hostagentdomain.Issue) *hostagentdomain.CommandAdmissionFailure {
	return &hostagentdomain.CommandAdmissionFailure{SchemaVersion: hostagentdomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), AdmissionState: state, Issue: issue}
}

func (service *HostTelemetryPipelineApplicationService) handlePipelineAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrHostAgentOwnedResourceConflict) {
		existing, readErr := service.repository.ReadHostTelemetryPipelineOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == hostagentdomain.TelemetryPipelineOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host command"})
		}
	}
	if errors.Is(err, ErrHostAgentOwnedResourceRevisionConflict) || errors.Is(err, ErrHostAgentOwnedResourceConflict) {
		return service.commandRejection(requestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned TelemetryPipeline"})
	}
	return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", hostTelemetryIssue("telemetry-pipeline-state-store-write-outcome-unknown", "Host Telemetry Pipeline could not determine whether the operation was durably admitted", true))
}

func (service *HostTelemetryPipelineApplicationService) handleEmissionAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrHostAgentOwnedResourceConflict) {
		existing, readErr := service.repository.ReadHostTelemetryEmissionOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == hostagentdomain.TelemetryEmitOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host command"})
		}
	}
	if errors.Is(err, ErrHostAgentOwnedResourceRevisionConflict) || errors.Is(err, ErrHostAgentOwnedResourceConflict) {
		return service.commandRejection(requestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned TelemetryPipeline"})
	}
	return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", hostTelemetryIssue("telemetry-emission-state-store-write-outcome-unknown", "Host Telemetry Pipeline could not determine whether the operation was durably admitted", true))
}

func hostResultForPipeline(pipeline hostagentdomain.TelemetryPipeline) hostagentdomain.TelemetryExportResult {
	if pipeline.Status.State == "ready" {
		return hostagentdomain.TelemetryExportResult{Outcome: "exported"}
	}
	issue := pipeline.Status.Issue
	if issue == nil {
		generated := hostTelemetryIssue("telemetry-pipeline-status-invariant-failed", "non-ready TelemetryPipeline has no typed issue", false)
		issue = &generated
	}
	if pipeline.Status.State == "failed" {
		return hostagentdomain.TelemetryExportResult{Outcome: "failed", Issue: issue}
	}
	return hostagentdomain.TelemetryExportResult{Outcome: "unavailable", Issue: issue}
}

func terminalTelemetryOperation(operation hostagentdomain.Operation, result hostagentdomain.TelemetryExportResult, at string) (hostagentdomain.Operation, error) {
	if result.Outcome == "exported" || result.Outcome == "dropped" {
		return hostagentdomain.TransitionOperation(operation, "succeeded", at, nil)
	}
	return hostagentdomain.TransitionOperation(operation, "failed", at, result.Issue)
}

func hostTelemetryIssue(code string, message string, retryable bool) hostagentdomain.Issue {
	return hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(retryable), Dependency: "host-telemetry-pipeline"}
}
