package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeTopologyApplicationService orchestrates the Guest-owned RuntimeTopology,
// its command operations, capability projection, and readiness projection.
// It is not the owner of Lab, archive, external integration, or process state.
type GuestRuntimeTopologyApplicationService struct {
	repository         GuestRuntimeTopologyStateRepository
	externalReader     GuestRuntimeExternalUpstreamCapabilityReader
	clock              GuestRuntimeClock
	identifiers        GuestRuntimeRequestCorrelationIdentifierGenerator
	serviceVersion     string
	serviceInstance    string
	topologyWorkflowMu sync.Mutex
}

func NewGuestRuntimeTopologyApplicationService(repository GuestRuntimeTopologyStateRepository, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator, serviceVersion string, serviceInstance string) (*GuestRuntimeTopologyApplicationService, error) {
	return NewGuestRuntimeTopologyApplicationServiceWithExternalUpstreamReader(repository, nil, clock, identifiers, serviceVersion, serviceInstance)
}

// NewGuestRuntimeTopologyApplicationServiceWithExternalUpstreamReader composes RuntimeTopology with the explicit External
// Upstream read boundary. A nil reader is an explicit module absence, never a
// bundled-profile fallback; the topology can report that unsupported state but
// cannot manufacture an external capability.
func NewGuestRuntimeTopologyApplicationServiceWithExternalUpstreamReader(repository GuestRuntimeTopologyStateRepository, externalReader GuestRuntimeExternalUpstreamCapabilityReader, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator, serviceVersion string, serviceInstance string) (*GuestRuntimeTopologyApplicationService, error) {
	if repository == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("repository, clock, and identifier generator are required")
	}
	if serviceVersion == "" {
		return nil, fmt.Errorf("service version is required")
	}
	return &GuestRuntimeTopologyApplicationService{
		repository:      repository,
		externalReader:  externalReader,
		clock:           clock,
		identifiers:     identifiers,
		serviceVersion:  serviceVersion,
		serviceInstance: serviceInstance,
	}, nil
}

func (service *GuestRuntimeTopologyApplicationService) ReadRuntimeTopology(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	topology, err := service.repository.ReadRuntimeTopology(ctx)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "runtime-topology-missing", "no RuntimeTopology has been applied")
	}
	if err != nil {
		return failedRead(now, "guest-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := topology.ResourceRevision
	return guestruntimedomain.ReadResult{
		SchemaVersion:  guestruntimedomain.SchemaVersion,
		State:          "available",
		ObservedAt:     now,
		Value:          topology,
		SourceRevision: &revision,
	}
}

func (service *GuestRuntimeTopologyApplicationService) ReadRuntimeTopologyOperation(ctx context.Context, operationID string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(operationID) {
		return invalidRead(now, "invalid-operation-id", "operationId must be a v1 identifier")
	}
	operation, err := service.repository.ReadRuntimeTopologyOperation(ctx, operationID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "operation-missing", "the requested operation does not exist")
	}
	if err != nil {
		return failedRead(now, "guest-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value:         operation,
	}
}

func (service *GuestRuntimeTopologyApplicationService) ReadRuntimeTopologyCapabilityDocument(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	topology, err := service.repository.ReadRuntimeTopology(ctx)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "runtime-topology-missing", "no RuntimeTopology has been applied")
	}
	if err != nil {
		return failedRead(now, "guest-state-store-read-failed", err.Error(), "guest-state-store")
	}
	switch topology.Spec.ProfileKind {
	case "bundled-upstream":
		capability, capabilityErr := service.repository.ReadRuntimeTopologyCapabilityDocument(ctx)
		if capabilityErr == nil {
			if topology.Status.CapabilityDocumentReference == nil || topology.Status.CapabilityDocumentReference.ResourceID != capability.ID || topology.Status.CapabilityRevision == nil || *topology.Status.CapabilityRevision != capability.CapabilityRevision {
				return failedRead(now, "guest-capability-topology-invariant-failed", "Guest Runtime topology and capability documents do not describe the same bundled profile", "guest-state-store")
			}
			revision := capability.CapabilityRevision
			return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: capability, SourceRevision: &revision}
		}
		if !errors.Is(capabilityErr, ErrGuestRuntimeOwnedResourceNotFound) {
			return failedRead(now, "guest-state-store-read-failed", capabilityErr.Error(), "guest-state-store")
		}
		return failedRead(now, "guest-bundled-capability-missing", "bundled RuntimeTopology has no durable CapabilityDocument", "guest-state-store")
	case "external-upstream":
		return service.getExternalCapabilities(ctx, topology, now)
	default:
		return failedRead(now, "guest-topology-profile-invariant-failed", "RuntimeTopology has an unsupported profile kind", "guest-state-store")
	}
}

func (service *GuestRuntimeTopologyApplicationService) getExternalCapabilities(ctx context.Context, topology guestruntimedomain.RuntimeTopology, now string) guestruntimedomain.ReadResult {
	if topology.Spec.EndpointReference.ResourceType != guestruntimedomain.ExternalUpstreamIntegrationResourceType {
		return failedRead(now, "external-topology-reference-invariant-failed", "external RuntimeTopology must reference an ExternalUpstreamIntegration", "guest-state-store")
	}
	if service.externalReader == nil {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "unsupported", ObservedAt: now, Issue: &guestruntimedomain.Issue{Code: "external-upstream-module-not-configured", Message: "Guest Runtime External Upstream module is not configured", Retryable: boolPointer(false), Dependency: "external-upstream"}}
	}
	integration, err := service.externalReader.ReadExternalUpstreamIntegrationState(ctx, topology.Spec.EndpointReference.ResourceID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return failedRead(now, "external-topology-integration-missing", "referenced ExternalUpstreamIntegration no longer exists", "external-upstream")
	}
	if err != nil {
		return failedRead(now, "external-upstream-read-failed", err.Error(), "external-upstream")
	}
	if topology.Status.ReadState != "available" {
		if topology.Status.Issue == nil {
			return failedRead(now, "external-topology-status-invariant-failed", "non-available external topology status has no typed issue", "guest-state-store")
		}
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: topology.Status.ReadState, ObservedAt: now, Issue: topology.Status.Issue}
	}
	if topology.Status.CapabilityDocumentReference == nil || topology.Status.CapabilityRevision == nil {
		return failedRead(now, "external-topology-capability-invariant-failed", "available external topology has no capability reference", "guest-state-store")
	}
	if integration.Status.State != "available" {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "stale", ObservedAt: now, Issue: &guestruntimedomain.Issue{Code: "external-topology-observation-stale", Message: "referenced external integration has a newer non-available observation", Retryable: boolPointer(true), Dependency: "external-upstream"}}
	}
	capability, err := service.externalReader.ReadExternalUpstreamCapabilityDocument(ctx, integration.ID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "stale", ObservedAt: now, Issue: &guestruntimedomain.Issue{Code: "external-topology-capability-stale", Message: "referenced external integration no longer has the topology capability document", Retryable: boolPointer(true), Dependency: "external-upstream"}}
	}
	if err != nil {
		return failedRead(now, "external-upstream-capability-read-failed", err.Error(), "external-upstream")
	}
	if capability.ID != topology.Status.CapabilityDocumentReference.ResourceID || capability.CapabilityRevision != *topology.Status.CapabilityRevision || capability.Provider.Kind != integration.Spec.Provider.Kind || capability.Provider.ID != integration.Spec.Provider.ID {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "stale", ObservedAt: now, Issue: &guestruntimedomain.Issue{Code: "external-topology-capability-stale", Message: "referenced external integration capability no longer matches the topology observation", Retryable: boolPointer(true), Dependency: "external-upstream"}}
	}
	revision := capability.CapabilityRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: capability, SourceRevision: &revision}
}

func (service *GuestRuntimeTopologyApplicationService) ReadGuestRuntimeReadiness(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if err := service.repository.VerifyRuntimeTopologyStateStoreAvailability(ctx); err != nil {
		return failedRead(now, "guest-state-store-unavailable", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value: guestruntimedomain.ServiceReadiness{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			Service: guestruntimedomain.ServiceIdentity{
				Name:       "guest-runtime",
				Version:    service.serviceVersion,
				InstanceID: service.serviceInstance,
			},
			State:      "ready",
			ObservedAt: now,
		},
	}
}

func (service *GuestRuntimeTopologyApplicationService) ApplyRuntimeTopology(ctx context.Context, command guestruntimedomain.TopologyApplyCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	// RuntimeTopology is a singleton resource. Serializing command admission in
	// its single owner process preserves request-id idempotency and prevents two
	// stale revisions from independently constructing an operation.
	service.topologyWorkflowMu.Lock()
	defer service.topologyWorkflowMu.Unlock()
	if issue := guestruntimedomain.ValidateTopologyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := guestruntimedomain.TopologyCommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{
			Code:       "guest-command-digest-failed",
			Message:    "Guest Runtime could not calculate the topology command digest",
			Retryable:  boolPointer(true),
			Dependency: "guest-runtime",
		})
	}
	existing, err := service.repository.ReadRuntimeTopologyOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == "runtime.topology.apply" && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{
			Code:    "request-id-reused-with-different-command",
			Message: "requestId already belongs to a different Guest Runtime command",
		})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "unknown", guestruntimedomain.Issue{
			Code:       "guest-state-store-read-outcome-unknown",
			Message:    "Guest Runtime could not read topology command request id ownership",
			Retryable:  boolPointer(true),
			Dependency: "guest-state-store",
		})
	}

	current, err := service.repository.ReadRuntimeTopology(ctx)
	if err != nil && !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "unknown", guestruntimedomain.Issue{
			Code:       "guest-state-store-read-outcome-unknown",
			Message:    "Guest Runtime could not read its current topology",
			Retryable:  boolPointer(true),
			Dependency: "guest-state-store",
		})
	}
	hasCurrent := err == nil
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{
				Code:    "resource-revision-conflict",
				Message: "RuntimeTopology is missing, so expectedResourceRevision must be zero",
			})
		}
	} else {
		if current.ID != command.TopologyID {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{
				Code:    "topology-resource-id-mismatch",
				Message: "this Guest Runtime owns one RuntimeTopology resource with a stable id",
			})
		}
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{
				Code:    "resource-revision-conflict",
				Message: "expectedResourceRevision does not match the owned RuntimeTopology",
			})
		}
	}

	requestedAt := guestruntimedomain.Timestamp(service.clock.Now())
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{
			Code:       "guest-operation-id-unavailable",
			Message:    "Guest Runtime could not allocate a topology operation identifier",
			Retryable:  boolPointer(true),
			Dependency: "guest-runtime",
		})
	}
	operation := guestruntimedomain.NewTopologyApplyOperation(operationID, command, requestedAt, digest)
	operation, err = guestruntimedomain.TransitionOperation(operation, "accepted", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{
			Code:       "guest-operation-transition-failed",
			Message:    "Guest Runtime could not construct the topology operation transition",
			Retryable:  boolPointer(false),
			Dependency: "guest-runtime",
		})
	}
	operation, err = guestruntimedomain.TransitionOperation(operation, "running", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{
			Code:       "guest-operation-transition-failed",
			Message:    "Guest Runtime could not construct the topology operation transition",
			Retryable:  boolPointer(false),
			Dependency: "guest-runtime",
		})
	}
	createdAt := requestedAt
	revision := 1
	if hasCurrent {
		createdAt = current.CreatedAt
		revision = current.ResourceRevision + 1
	}
	var externalIntegration *guestruntimedomain.ExternalUpstreamIntegration
	if command.Spec.ProfileKind == "external-upstream" {
		if command.Spec.EndpointReference.ResourceType != guestruntimedomain.ExternalUpstreamIntegrationResourceType {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "external-topology-reference-invalid", Message: "external RuntimeTopology endpointReference must identify an ExternalUpstreamIntegration"})
		}
		if service.externalReader != nil {
			integration, integrationErr := service.externalReader.ReadExternalUpstreamIntegrationState(ctx, command.Spec.EndpointReference.ResourceID)
			if errors.Is(integrationErr, ErrGuestRuntimeOwnedResourceNotFound) {
				return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "external-upstream-integration-missing", Message: "endpointReference does not identify a configured ExternalUpstreamIntegration"})
			}
			if integrationErr != nil {
				return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "external-upstream-read-outcome-unknown", Message: "Guest Runtime could not read the referenced ExternalUpstreamIntegration", Retryable: boolPointer(true), Dependency: "external-upstream"})
			}
			externalIntegration = &integration
		}
	}
	var capability *guestruntimedomain.CapabilityDocument
	status := guestruntimedomain.UnsupportedTopologyStatus(service.clock.Now(), operation.ID)
	if command.Spec.ProfileKind == "bundled-upstream" {
		bundled, capabilityErr := guestruntimedomain.BundledUpstreamCapability(command.TopologyID, command.Spec, revision, service.clock.Now())
		if capabilityErr != nil {
			return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{
				Code:       "guest-capability-construction-failed",
				Message:    "Guest Runtime could not construct the bundled upstream capability document",
				Retryable:  boolPointer(false),
				Dependency: "guest-runtime",
			})
		}
		capability = &bundled
		status = guestruntimedomain.BundledTopologyStatus(service.clock.Now(), operation.ID, bundled)
	} else if externalIntegration != nil {
		status = guestruntimedomain.ExternalTopologyStatus(*externalIntegration, operation.ID)
	} else {
		status.Issue = &guestruntimedomain.Issue{Code: "external-upstream-module-not-configured", Message: "Guest Runtime External Upstream module is not configured", Retryable: boolPointer(false), Dependency: "external-upstream"}
	}
	topology := guestruntimedomain.RuntimeTopology{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		ID:               command.TopologyID,
		ResourceRevision: revision,
		Spec:             command.Spec,
		Status:           status,
		CreatedAt:        createdAt,
		UpdatedAt:        guestruntimedomain.Timestamp(service.clock.Now()),
	}
	operation, err = guestruntimedomain.TransitionOperation(operation, "succeeded", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{
			Code:       "guest-operation-transition-failed",
			Message:    "Guest Runtime could not construct the topology operation transition",
			Retryable:  boolPointer(false),
			Dependency: "guest-runtime",
		})
	}
	if err := service.repository.CommitRuntimeTopologyApplication(ctx, topology, capability, operation); err != nil {
		if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{
				Code:    "resource-revision-conflict",
				Message: "expectedResourceRevision no longer matches the owned RuntimeTopology",
			})
		}
		if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
			existing, readErr := service.repository.ReadRuntimeTopologyOperationByRequestID(ctx, command.RequestID)
			if readErr == nil && existing.Kind == "runtime.topology.apply" && existing.CommandDigest == digest {
				return existing, nil, nil
			}
			if readErr == nil {
				return service.commandRejection(command.RequestID, guestruntimedomain.Issue{
					Code:    "request-id-reused-with-different-command",
					Message: "requestId already belongs to a different Guest Runtime command",
				})
			}
		}
		return service.admissionFailure(command.RequestID, "unknown", guestruntimedomain.Issue{
			Code:       "guest-state-store-write-outcome-unknown",
			Message:    "Guest Runtime could not determine whether the topology operation was durably admitted",
			Retryable:  boolPointer(true),
			Dependency: "guest-state-store",
		})
	}
	return operation, nil, nil
}

func (service *GuestRuntimeTopologyApplicationService) RejectMalformedRuntimeTopologyCommand(requestID string, message string) (guestruntimedomain.CommandRejection, error) {
	rejection, err := service.rejection(requestID, guestruntimedomain.Issue{
		Code:    "invalid-command-envelope",
		Message: message,
	})
	if err != nil {
		return guestruntimedomain.CommandRejection{}, err
	}
	return *rejection, nil
}

func (service *GuestRuntimeTopologyApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	rejection, err := service.rejection(requestID, issue)
	if err != nil {
		return service.admissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{
			Code:       "guest-rejection-correlation-unavailable",
			Message:    "Guest Runtime could not allocate a rejection correlation identifier",
			Retryable:  boolPointer(true),
			Dependency: "guest-runtime",
		})
	}
	return guestruntimedomain.Operation{}, rejection, nil
}

func (service *GuestRuntimeTopologyApplicationService) admissionFailure(requestID string, admissionState string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, &guestruntimedomain.CommandAdmissionFailure{
		SchemaVersion:  guestruntimedomain.SchemaVersion,
		State:          "failed",
		RequestID:      requestID,
		ObservedAt:     guestruntimedomain.Timestamp(service.clock.Now()),
		AdmissionState: admissionState,
		Issue:          issue,
	}
}

func (service *GuestRuntimeTopologyApplicationService) rejection(requestID string, issue guestruntimedomain.Issue) (*guestruntimedomain.CommandRejection, error) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return nil, fmt.Errorf("generate rejection correlation id: %w", err)
		}
		requestID = generated
	}
	return &guestruntimedomain.CommandRejection{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "rejected",
		RequestID:     requestID,
		RejectedAt:    guestruntimedomain.Timestamp(service.clock.Now()),
		Issue:         issue,
	}, nil
}

func missingRead(at string, code string, message string) guestruntimedomain.ReadResult {
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "missing", ObservedAt: at, Issue: &guestruntimedomain.Issue{Code: code, Message: message}}
}

func invalidRead(at string, code string, message string) guestruntimedomain.ReadResult {
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "invalid", ObservedAt: at, Issue: &guestruntimedomain.Issue{Code: code, Message: message}}
}

func failedRead(at string, code string, message string, dependency string) guestruntimedomain.ReadResult {
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", ObservedAt: at, Issue: &guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(true), Dependency: dependency}}
}

func boolPointer(value bool) *bool {
	return &value
}
