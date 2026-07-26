package hostagentapplication

import (
	"context"
	"errors"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// HostUpdateBundleStore owns the filesystem representation of offline update
// bundles.  It reports whether a bundle was copied, already present, invalid,
// or unavailable; application code never treats a directory name as a bundle.
type HostUpdateBundleStore interface {
	Import(context.Context, hostagentdomain.HostUpdateBundleImportCommand) (hostagentdomain.HostUpdateBundleImportReceipt, error)
	Read(context.Context, string) (hostagentdomain.HostUpdateBundleDeclaration, error)
}

var (
	ErrHostUpdateBundleNotFound = errors.New("Host update bundle not found")
	ErrHostUpdateBundleInvalid  = errors.New("Host update bundle is invalid")
	ErrHostUpdateBundleConflict = errors.New("Host update bundle conflicts with imported bytes")
)

// HostUpdateBundleApplicationService has one narrow responsibility: turn an
// OS-local bundle selection into a Host-owned immutable bundle reference, then
// bind that reference to the existing durable C27 update workflow.
type HostUpdateBundleApplicationService struct {
	store   HostUpdateBundleStore
	updates *HostUpdateApplicationService
	clock   HostAgentClock
}

func NewHostUpdateBundleApplicationService(store HostUpdateBundleStore, updates *HostUpdateApplicationService, clock HostAgentClock) (*HostUpdateBundleApplicationService, error) {
	if store == nil || updates == nil || clock == nil {
		return nil, fmt.Errorf("update bundle store, update workflow, and clock are required")
	}
	return &HostUpdateBundleApplicationService{store: store, updates: updates, clock: clock}, nil
}

func (service *HostUpdateBundleApplicationService) ImportHostUpdateBundleCommand(ctx context.Context, command hostagentdomain.HostUpdateBundleImportCommand) (hostagentdomain.HostUpdateBundleImportReceipt, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if issue := hostagentdomain.ValidateHostUpdateBundleImportCommand(command); issue != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, service.rejection(command.RequestID, *issue), nil
	}
	receipt, err := service.store.Import(ctx, command)
	if err != nil {
		rejection, admissionFailure := service.storeOutcome(command.RequestID, err)
		return hostagentdomain.HostUpdateBundleImportReceipt{}, rejection, admissionFailure
	}
	if issue := hostagentdomain.ValidateHostUpdateBundleImportReceipt(receipt); issue != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "host-update-bundle-store"})
	}
	if receipt.RequestID != command.RequestID {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-bundle-import-correlation-invalid", Message: "bundle store returned a receipt for another request", Retryable: hostagentdomain.Bool(false), Dependency: "host-update-bundle-store"})
	}
	return receipt, nil, nil
}

func (service *HostUpdateBundleApplicationService) ReadHostUpdateBundle(ctx context.Context, bundleID string) hostagentdomain.ReadResult {
	if !hostagentdomain.ValidIdentifier(bundleID) {
		return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "invalid", ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: &hostagentdomain.Issue{Code: "invalid-host-update-bundle-id", Message: "update bundle id is invalid"}}
	}
	bundle, err := service.store.Read(ctx, bundleID)
	if err != nil {
		state, issue := bundleReadOutcome(err)
		return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: state, ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: &issue}
	}
	if issue := hostagentdomain.ValidateHostUpdateBundleDeclaration(bundle); issue != nil {
		return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "invalid", ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: issue}
	}
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), Value: bundle}
}

func (service *HostUpdateBundleApplicationService) ApplyHostUpdateBundleCommand(ctx context.Context, command hostagentdomain.HostUpdateBundleApplyCommand) (HostUpdateWorkflowOutcome, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if issue := hostagentdomain.ValidateHostUpdateBundleApplyCommand(command); issue != nil {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, *issue), nil
	}
	bundle, err := service.store.Read(ctx, command.BundleReferenceID)
	if err != nil {
		rejection, admissionFailure := service.storeOutcome(command.RequestID, err)
		return HostUpdateWorkflowOutcome{}, rejection, admissionFailure
	}
	if issue := hostagentdomain.ValidateHostUpdateBundleDeclaration(bundle); issue != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "host-update-bundle-store"})
	}
	return service.updates.ExecuteHostUpdateCommand(ctx, hostagentdomain.HostUpdateCommand{
		SchemaVersion:                hostagentdomain.SchemaVersion,
		RequestID:                    command.RequestID,
		InstallationID:               command.InstallationID,
		ExpectedInstallationRevision: command.ExpectedInstallationRevision,
		BundleReferenceID:            bundle.ID,
		BootstrapEnvelope:            bundle.BootstrapEnvelope,
	})
}

func (service *HostUpdateBundleApplicationService) rejection(requestID string, issue hostagentdomain.Issue) *hostagentdomain.CommandRejection {
	if !hostagentdomain.ValidIdentifier(requestID) {
		requestID = "rejection-unavailable-request-id"
	}
	return &hostagentdomain.CommandRejection{SchemaVersion: hostagentdomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: issue}
}

func (service *HostUpdateBundleApplicationService) admissionFailure(requestID string, admissionState string, issue hostagentdomain.Issue) *hostagentdomain.CommandAdmissionFailure {
	if !hostagentdomain.ValidIdentifier(requestID) {
		requestID = "admission-unavailable-request-id"
	}
	return &hostagentdomain.CommandAdmissionFailure{SchemaVersion: hostagentdomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), AdmissionState: admissionState, Issue: issue}
}

func (service *HostUpdateBundleApplicationService) storeOutcome(requestID string, err error) (*hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrHostUpdateBundleInvalid) {
		return service.rejection(requestID, hostagentdomain.Issue{Code: "host-update-bundle-invalid", Message: err.Error()}), nil
	}
	if errors.Is(err, ErrHostUpdateBundleConflict) {
		return service.rejection(requestID, hostagentdomain.Issue{Code: "host-update-bundle-conflict", Message: err.Error()}), nil
	}
	if errors.Is(err, ErrHostUpdateBundleNotFound) {
		return service.rejection(requestID, hostagentdomain.Issue{Code: "host-update-bundle-missing", Message: "the imported update bundle does not exist"}), nil
	}
	return nil, service.admissionFailure(requestID, "unknown", hostagentdomain.Issue{Code: "host-update-bundle-store-unavailable", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-update-bundle-store"})
}

func bundleReadOutcome(err error) (string, hostagentdomain.Issue) {
	if errors.Is(err, ErrHostUpdateBundleNotFound) {
		return "missing", hostagentdomain.Issue{Code: "host-update-bundle-missing", Message: "the imported update bundle does not exist"}
	}
	if errors.Is(err, ErrHostUpdateBundleInvalid) {
		return "invalid", hostagentdomain.Issue{Code: "host-update-bundle-invalid", Message: err.Error()}
	}
	return "unavailable", hostagentdomain.Issue{Code: "host-update-bundle-store-unavailable", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-update-bundle-store"}
}
