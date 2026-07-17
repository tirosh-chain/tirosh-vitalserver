package hostagentapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type HostAgentControlStateInitialization struct {
	InstallationID                string
	ProductVersion                string
	RuntimeVersion                string
	DataDirectory                 string
	GuestRuntimeControlEndpointID string
	GuestRuntimeControlHTTPScheme string
	GuestRuntimeControlHTTPHost   string
	GuestRuntimeControlHTTPPort   int
	ProviderKind                  string
	ProviderID                    string
}

type HostAgentControlApplicationService struct {
	repository                   HostAgentControlStateRepository
	provider                     PlatformProviderLifecycleClient
	guestRuntimeControlTransport GuestRuntimeControlHTTPTransport
	clock                        HostAgentClock
	identifiers                  HostAgentRequestCorrelationIdentifierGenerator
	endpointWorkflowMu           sync.Mutex
}

func NewHostAgentControlApplicationService(repository HostAgentControlStateRepository, provider PlatformProviderLifecycleClient, guestRuntimeControlTransport GuestRuntimeControlHTTPTransport, clock HostAgentClock, identifiers HostAgentRequestCorrelationIdentifierGenerator) (*HostAgentControlApplicationService, error) {
	if repository == nil || provider == nil || guestRuntimeControlTransport == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("repository, provider, Guest Runtime Control transport, clock, and identifier generator are required")
	}
	return &HostAgentControlApplicationService{repository: repository, provider: provider, guestRuntimeControlTransport: guestRuntimeControlTransport, clock: clock, identifiers: identifiers}, nil
}

func (service *HostAgentControlApplicationService) InitializeHostAgentControlState(ctx context.Context, configuration HostAgentControlStateInitialization) error {
	if !hostagentdomain.ValidIdentifier(configuration.InstallationID) || !hostagentdomain.ValidIdentifier(configuration.GuestRuntimeControlEndpointID) || !hostagentdomain.ValidIdentifier(configuration.ProviderID) {
		return fmt.Errorf("installation, Guest Runtime Control endpoint, and provider identifiers must be valid v1 identifiers")
	}
	if !hostagentdomain.ValidPlatformProviderKind(configuration.ProviderKind) {
		return fmt.Errorf("configured Host provider kind is unsupported: %s", configuration.ProviderKind)
	}
	if configuration.ProductVersion == "" || configuration.RuntimeVersion == "" || configuration.DataDirectory == "" {
		return fmt.Errorf("product version, runtime version, and data directory are required")
	}
	if (configuration.GuestRuntimeControlHTTPScheme != "http" && configuration.GuestRuntimeControlHTTPScheme != "https") || configuration.GuestRuntimeControlHTTPHost == "" || configuration.GuestRuntimeControlHTTPPort < 1 || configuration.GuestRuntimeControlHTTPPort > 65535 {
		return fmt.Errorf("Guest Runtime Control HTTP scheme, host, and port must be explicit and valid")
	}
	now := hostagentdomain.Timestamp(service.clock.Now())
	installation := hostagentdomain.PlatformInstallation{
		SchemaVersion:    hostagentdomain.SchemaVersion,
		ID:               configuration.InstallationID,
		ResourceRevision: 1,
		Release: hostagentdomain.Release{
			ProductVersion: configuration.ProductVersion,
			RuntimeVersion: configuration.RuntimeVersion,
		},
		DataDirectory: configuration.DataDirectory,
		InstalledAt:   now,
		UpdatedAt:     now,
	}
	endpoint := hostagentdomain.GuestRuntimeControlEndpoint{
		SchemaVersion:    hostagentdomain.SchemaVersion,
		ID:               configuration.GuestRuntimeControlEndpointID,
		ResourceRevision: 1,
		Address: hostagentdomain.ConfiguredGuestRuntimeControlHTTPAddress{
			Scheme: configuration.GuestRuntimeControlHTTPScheme,
			Host:   configuration.GuestRuntimeControlHTTPHost,
			Port:   configuration.GuestRuntimeControlHTTPPort,
		},
		Provider: hostagentdomain.PlatformProviderObservation{
			Kind:       configuration.ProviderKind,
			ID:         configuration.ProviderID,
			State:      "not-observed",
			ObservedAt: now,
		},
		Transport: hostagentdomain.GuestRuntimeControlTransportObservation{State: "not-checked", ObservedAt: now},
		CreatedAt: now,
		UpdatedAt: now,
	}
	return service.repository.InitializeHostAgentControlState(ctx, installation, endpoint)
}

func (service *HostAgentControlApplicationService) ReadHostPlatformInstallation(ctx context.Context) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	installation, err := service.repository.ReadHostPlatformInstallation(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "platform-installation-missing", "Host installation state has not been configured")
	}
	if err != nil {
		return failedRead(now, "host-state-store-read-failed", err.Error(), "host-state-store")
	}
	revision := installation.ResourceRevision
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: installation, SourceRevision: &revision}
}

func (service *HostAgentControlApplicationService) ReadGuestRuntimeControlEndpoint(ctx context.Context) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	endpoint, err := service.repository.ReadGuestRuntimeControlEndpoint(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "guest-runtime-control-endpoint-missing", "Host Guest Runtime Control endpoint has not been configured")
	}
	if err != nil {
		return failedRead(now, "host-state-store-read-failed", err.Error(), "host-state-store")
	}
	revision := endpoint.ResourceRevision
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: endpoint, SourceRevision: &revision}
}

func (service *HostAgentControlApplicationService) ReadHostGuestLifecycleOperation(ctx context.Context, operationID string) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	if !hostagentdomain.ValidIdentifier(operationID) {
		return invalidRead(now, "invalid-operation-id", "operationId must be a v1 identifier")
	}
	operation, err := service.repository.ReadHostOperation(ctx, operationID)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "operation-missing", "the requested Host operation does not exist")
	}
	if err != nil {
		return failedRead(now, "host-state-store-read-failed", err.Error(), "host-state-store")
	}
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: operation}
}

// ExecuteGuestLifecycleCommand durably records a running Host operation before invoking the
// provider. A failed outcome commit therefore returns that running operation;
// it never changes an unpersisted provider effect into a fake terminal result.
func (service *HostAgentControlApplicationService) ExecuteGuestLifecycleCommand(ctx context.Context, command hostagentdomain.GuestLifecycleCommand) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	// Host Agent is the single writer for endpoint mutations in this process.
	// Lifecycle effects and Host transport observations share resourceRevision,
	// so serializing them prevents a stale pre-effect read from launching a
	// second provider effect while another workflow owns the endpoint update.
	service.endpointWorkflowMu.Lock()
	defer service.endpointWorkflowMu.Unlock()
	if issue := hostagentdomain.ValidateLifecycleCommand(command); issue != nil {
		return service.rejectGuestLifecycleCommand(command.RequestID, *issue)
	}
	digest, err := hostagentdomain.LifecycleCommandDigest(command)
	if err != nil {
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{
			Code:       "host-command-digest-failed",
			Message:    "Host Agent could not calculate the lifecycle command digest",
			Retryable:  hostagentdomain.Bool(true),
			Dependency: "host-agent",
		})
	}
	existing, err := service.repository.ReadHostOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == "platform.guest."+command.Action && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.rejectGuestLifecycleCommand(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host lifecycle command"})
	}
	if !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{
			Code:       "host-state-store-read-outcome-unknown",
			Message:    "Host Agent could not read lifecycle request id ownership",
			Retryable:  hostagentdomain.Bool(true),
			Dependency: "host-state-store",
		})
	}
	endpoint, err := service.repository.ReadGuestRuntimeControlEndpoint(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.rejectGuestLifecycleCommand(command.RequestID, hostagentdomain.Issue{Code: "guest-runtime-control-endpoint-missing", Message: "Host Guest Runtime Control endpoint is not configured"})
	}
	if err != nil {
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{
			Code:       "host-state-store-read-outcome-unknown",
			Message:    "Host Agent could not read its Guest Runtime Control endpoint",
			Retryable:  hostagentdomain.Bool(true),
			Dependency: "host-state-store",
		})
	}
	if endpoint.ID != command.GuestRuntimeControlEndpointID {
		return service.rejectGuestLifecycleCommand(command.RequestID, hostagentdomain.Issue{Code: "guest-runtime-control-endpoint-id-mismatch", Message: "command Guest Runtime Control endpoint does not match Host-owned endpoint"})
	}
	if endpoint.ResourceRevision != command.ExpectedResourceRevision {
		return service.rejectGuestLifecycleCommand(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the Host-owned Guest Runtime Control endpoint"})
	}

	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("host-operation")
	if err != nil {
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{
			Code:       "host-operation-id-unavailable",
			Message:    "Host Agent could not allocate a lifecycle operation identifier",
			Retryable:  hostagentdomain.Bool(true),
			Dependency: "host-agent",
		})
	}
	operation := hostagentdomain.NewLifecycleOperation(operationID, command, hostagentdomain.Timestamp(service.clock.Now()), digest)
	operation, err = hostagentdomain.TransitionOperation(operation, "accepted", hostagentdomain.Timestamp(service.clock.Now()), nil)
	if err != nil {
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{
			Code:       "host-operation-transition-failed",
			Message:    "Host Agent could not construct the lifecycle operation transition",
			Retryable:  hostagentdomain.Bool(false),
			Dependency: "host-agent",
		})
	}
	operation, err = hostagentdomain.TransitionOperation(operation, "running", hostagentdomain.Timestamp(service.clock.Now()), nil)
	if err != nil {
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{
			Code:       "host-operation-transition-failed",
			Message:    "Host Agent could not construct the lifecycle operation transition",
			Retryable:  hostagentdomain.Bool(false),
			Dependency: "host-agent",
		})
	}
	if err := service.repository.PersistNewHostOperation(ctx, operation); err != nil {
		if errors.Is(err, ErrHostAgentOwnedResourceConflict) {
			existing, readErr := service.repository.ReadHostOperationByRequestID(ctx, command.RequestID)
			if readErr == nil && existing.Kind == operation.Kind && existing.CommandDigest == digest {
				return existing, nil, nil
			}
			if readErr == nil {
				return service.rejectGuestLifecycleCommand(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host lifecycle command"})
			}
		}
		return service.newGuestLifecycleCommandAdmissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{
			Code:       "host-state-store-write-outcome-unknown",
			Message:    "Host Agent could not determine whether the lifecycle operation was durably admitted",
			Retryable:  hostagentdomain.Bool(true),
			Dependency: "host-state-store",
		})
	}

	providerInvocation := hostagentdomain.NewPlatformProviderLifecycleInvocation(endpoint.Provider.Kind, command, endpoint.Provider.ID)
	providerResult := service.provider.Execute(ctx, providerInvocation)
	if issue := hostagentdomain.ValidateProviderResult(providerInvocation.Lifecycle, providerResult); issue != nil {
		providerResult = hostagentdomain.FailedProviderResult(providerInvocation.Lifecycle, hostagentdomain.Timestamp(service.clock.Now()), *issue)
	}
	nextEndpoint, err := hostagentdomain.ApplyPlatformProviderObservation(endpoint, command.Action, providerResult)
	if err != nil {
		return operation, nil, nil
	}
	terminalOperation, err := hostagentdomain.CompleteLifecycleOperation(operation, command.Action, providerResult, hostagentdomain.Timestamp(service.clock.Now()))
	if err != nil {
		return operation, nil, nil
	}
	if err := service.repository.CommitGuestLifecycleOutcome(ctx, nextEndpoint, terminalOperation); err != nil {
		return operation, nil, nil
	}
	return terminalOperation, nil, nil
}

func (service *HostAgentControlApplicationService) RejectMalformedGuestRuntimeControlCommand(requestID string, message string) (hostagentdomain.CommandRejection, error) {
	guestRuntimeControlCommandRejection, err := service.createHostAgentControlCommandRejection(requestID, hostagentdomain.Issue{Code: "invalid-command-envelope", Message: message})
	if err != nil {
		return hostagentdomain.CommandRejection{}, err
	}
	return *guestRuntimeControlCommandRejection, nil
}

type GuestRuntimeControlReadForwardOutcome struct {
	Response   *GuestRuntimeControlHTTPForwardedResponse
	ReadResult *hostagentdomain.ReadResult
}

type GuestRuntimeControlCommandForwardOutcome struct {
	Response *GuestRuntimeControlHTTPForwardedResponse
	Rejected *hostagentdomain.CommandRejection
	Failure  *hostagentdomain.FacadeForwardingFailure
}

func (service *HostAgentControlApplicationService) ForwardGuestRuntimeControlRead(ctx context.Context, path string) (GuestRuntimeControlReadForwardOutcome, error) {
	service.endpointWorkflowMu.Lock()
	defer service.endpointWorkflowMu.Unlock()
	endpoint, err := service.repository.ReadGuestRuntimeControlEndpoint(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		result := missingRead(hostagentdomain.Timestamp(service.clock.Now()), "guest-runtime-control-endpoint-missing", "Host Guest Runtime Control endpoint is not configured")
		return GuestRuntimeControlReadForwardOutcome{ReadResult: &result}, nil
	}
	if err != nil {
		result := failedRead(hostagentdomain.Timestamp(service.clock.Now()), "host-state-store-read-failed", err.Error(), "host-state-store")
		return GuestRuntimeControlReadForwardOutcome{ReadResult: &result}, nil
	}
	endpoint, unavailable, err := service.prepareGuestRuntimeControlForwarding(ctx, endpoint)
	if err != nil {
		result := failedRead(hostagentdomain.Timestamp(service.clock.Now()), "host-endpoint-state-write-failed", err.Error(), "host-state-store")
		return GuestRuntimeControlReadForwardOutcome{ReadResult: &result}, nil
	}
	if unavailable != nil {
		result := unavailableRead(hostagentdomain.Timestamp(service.clock.Now()), *unavailable)
		return GuestRuntimeControlReadForwardOutcome{ReadResult: &result}, nil
	}
	response, failure := service.guestRuntimeControlTransport.Forward(ctx, endpoint, "GET", path, nil, "")
	if failure == nil {
		return GuestRuntimeControlReadForwardOutcome{Response: &response}, nil
	}
	issue := normalizeForwardIssue(failure.Issue)
	if _, updateErr := service.recordUnavailableGuestRuntimeControlHTTPTransport(ctx, endpoint, issue); updateErr != nil {
		result := failedRead(hostagentdomain.Timestamp(service.clock.Now()), "host-endpoint-state-write-failed-after-forward", updateErr.Error(), "host-state-store")
		return GuestRuntimeControlReadForwardOutcome{ReadResult: &result}, nil
	}
	result := unavailableRead(hostagentdomain.Timestamp(service.clock.Now()), issue)
	return GuestRuntimeControlReadForwardOutcome{ReadResult: &result}, nil
}

func (service *HostAgentControlApplicationService) ForwardGuestRuntimeControlCommand(ctx context.Context, path string, body []byte, contentType string, requestID string) (GuestRuntimeControlCommandForwardOutcome, error) {
	service.endpointWorkflowMu.Lock()
	defer service.endpointWorkflowMu.Unlock()
	requestCorrelationID, err := service.resolveHostAgentControlRequestCorrelationID(requestID)
	if err != nil {
		return GuestRuntimeControlCommandForwardOutcome{}, err
	}
	endpoint, err := service.repository.ReadGuestRuntimeControlEndpoint(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		rejected, rejectionErr := service.createHostAgentControlCommandRejection(requestCorrelationID, hostagentdomain.Issue{Code: "guest-runtime-control-endpoint-missing", Message: "Host Guest Runtime Control endpoint is not configured"})
		return GuestRuntimeControlCommandForwardOutcome{Rejected: rejected}, rejectionErr
	}
	if err != nil {
		rejected, rejectionErr := service.createHostAgentControlCommandRejection(requestCorrelationID, hostagentdomain.Issue{Code: "host-state-store-unavailable", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
		return GuestRuntimeControlCommandForwardOutcome{Rejected: rejected}, rejectionErr
	}
	endpoint, unavailable, err := service.prepareGuestRuntimeControlForwarding(ctx, endpoint)
	if err != nil {
		rejected, rejectionErr := service.createHostAgentControlCommandRejection(requestCorrelationID, hostagentdomain.Issue{Code: "host-endpoint-state-write-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
		return GuestRuntimeControlCommandForwardOutcome{Rejected: rejected}, rejectionErr
	}
	if unavailable != nil {
		rejected, rejectionErr := service.createHostAgentControlCommandRejection(requestCorrelationID, *unavailable)
		return GuestRuntimeControlCommandForwardOutcome{Rejected: rejected}, rejectionErr
	}
	response, failure := service.guestRuntimeControlTransport.Forward(ctx, endpoint, "POST", path, body, contentType)
	if failure == nil {
		return GuestRuntimeControlCommandForwardOutcome{Response: &response}, nil
	}
	issue := normalizeForwardIssue(failure.Issue)
	if _, updateErr := service.recordUnavailableGuestRuntimeControlHTTPTransport(ctx, endpoint, issue); updateErr != nil {
		issue = hostagentdomain.Issue{Code: "host-endpoint-state-write-failed-after-forward", Message: updateErr.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"}
	}
	return GuestRuntimeControlCommandForwardOutcome{Failure: &hostagentdomain.FacadeForwardingFailure{
		SchemaVersion:       hostagentdomain.SchemaVersion,
		State:               "failed",
		RequestID:           requestCorrelationID,
		ObservedAt:          hostagentdomain.Timestamp(service.clock.Now()),
		DeliveryDisposition: "unknown",
		Issue:               issue,
	}}, nil
}

func (service *HostAgentControlApplicationService) prepareGuestRuntimeControlForwarding(ctx context.Context, endpoint hostagentdomain.GuestRuntimeControlEndpoint) (hostagentdomain.GuestRuntimeControlEndpoint, *hostagentdomain.Issue, error) {
	if unavailable := hostagentdomain.KnownPlatformProviderUnavailable(endpoint); unavailable != nil {
		return endpoint, unavailable, nil
	}
	probe := service.guestRuntimeControlTransport.Probe(ctx, endpoint)
	if !probe.Reachable {
		issue := normalizeProbeIssue(probe.Issue)
		next, err := service.recordUnavailableGuestRuntimeControlHTTPTransport(ctx, endpoint, issue)
		return next, &issue, err
	}
	next, err := hostagentdomain.ApplyGuestRuntimeControlTransportObservation(endpoint, "reachable", hostagentdomain.Timestamp(service.clock.Now()), nil)
	if err != nil {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, nil, err
	}
	if err := service.repository.PersistGuestRuntimeControlEndpointObservation(ctx, next); err != nil {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, nil, err
	}
	return next, nil, nil
}

func (service *HostAgentControlApplicationService) recordUnavailableGuestRuntimeControlHTTPTransport(ctx context.Context, endpoint hostagentdomain.GuestRuntimeControlEndpoint, issue hostagentdomain.Issue) (hostagentdomain.GuestRuntimeControlEndpoint, error) {
	next, err := hostagentdomain.ApplyGuestRuntimeControlTransportObservation(endpoint, "unavailable", hostagentdomain.Timestamp(service.clock.Now()), &issue)
	if err != nil {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, err
	}
	if err := service.repository.PersistGuestRuntimeControlEndpointObservation(ctx, next); err != nil {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, err
	}
	return next, nil
}

func (service *HostAgentControlApplicationService) resolveHostAgentControlRequestCorrelationID(requestID string) (string, error) {
	if hostagentdomain.ValidIdentifier(requestID) {
		return requestID, nil
	}
	return service.identifiers.NewRequestCorrelationIdentifier("facade-rejection")
}

func (service *HostAgentControlApplicationService) rejectGuestLifecycleCommand(requestID string, issue hostagentdomain.Issue) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	guestLifecycleCommandRejection, err := service.createHostAgentControlCommandRejection(requestID, issue)
	if err != nil {
		return service.newGuestLifecycleCommandAdmissionFailure(requestID, "not-admitted", hostagentdomain.Issue{
			Code:       "host-rejection-correlation-unavailable",
			Message:    "Host Agent could not allocate a rejection correlation identifier",
			Retryable:  hostagentdomain.Bool(true),
			Dependency: "host-agent",
		})
	}
	return hostagentdomain.Operation{}, guestLifecycleCommandRejection, nil
}

func (service *HostAgentControlApplicationService) newGuestLifecycleCommandAdmissionFailure(requestID string, admissionState string, issue hostagentdomain.Issue) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	return hostagentdomain.Operation{}, nil, &hostagentdomain.CommandAdmissionFailure{
		SchemaVersion:  hostagentdomain.SchemaVersion,
		State:          "failed",
		RequestID:      requestID,
		ObservedAt:     hostagentdomain.Timestamp(service.clock.Now()),
		AdmissionState: admissionState,
		Issue:          issue,
	}
}

func (service *HostAgentControlApplicationService) createHostAgentControlCommandRejection(requestID string, issue hostagentdomain.Issue) (*hostagentdomain.CommandRejection, error) {
	requestCorrelationID, err := service.resolveHostAgentControlRequestCorrelationID(requestID)
	if err != nil {
		return nil, fmt.Errorf("generate rejection correlation id: %w", err)
	}
	return &hostagentdomain.CommandRejection{SchemaVersion: hostagentdomain.SchemaVersion, State: "rejected", RequestID: requestCorrelationID, RejectedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func normalizeProbeIssue(issue *hostagentdomain.Issue) hostagentdomain.Issue {
	if issue != nil {
		return *issue
	}
	return hostagentdomain.Issue{Code: "guest-control-probe-unavailable", Message: "Guest control probe returned no reachability result", Retryable: hostagentdomain.Bool(true), Dependency: "guest-control"}
}

func normalizeForwardIssue(issue *hostagentdomain.Issue) hostagentdomain.Issue {
	if issue != nil {
		return *issue
	}
	return hostagentdomain.Issue{Code: "guest-control-forward-failed", Message: "Guest control forward failed without an adapter issue", Retryable: hostagentdomain.Bool(true), Dependency: "guest-control"}
}

func missingRead(at string, code string, message string) hostagentdomain.ReadResult {
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "missing", ObservedAt: at, Issue: &hostagentdomain.Issue{Code: code, Message: message}}
}

func unavailableRead(at string, issue hostagentdomain.Issue) hostagentdomain.ReadResult {
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "unavailable", ObservedAt: at, Issue: &issue}
}

func invalidRead(at string, code string, message string) hostagentdomain.ReadResult {
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "invalid", ObservedAt: at, Issue: &hostagentdomain.Issue{Code: code, Message: message}}
}

func failedRead(at string, code string, message string, dependency string) hostagentdomain.ReadResult {
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "failed", ObservedAt: at, Issue: &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(true), Dependency: dependency}}
}
