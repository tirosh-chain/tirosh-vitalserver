// Package hostplatformstagedreleaseupdateapplication orchestrates one C68 Host
// Platform transition. The Host Installation Manager remains the sole owner of
// its operation state; the staged updater only receives its C55 projection.
package hostplatformstagedreleaseupdateapplication

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

// InspectedHostPlatformReleaseArchive is application-local transport between
// archive inspection and candidate persistence. It is neither C68 state nor a
// public contract: its filesystem paths remain adapter implementation detail.
type InspectedHostPlatformReleaseArchive struct {
	Manifest                 hostinstallationmanagerdomain.HostProductInstallationManifest
	TemporaryDirectory       string
	ReleaseDirectory         string
	ServiceDefinitionSources map[string]string
	OperatorBootstrapSource  string
}
type ArchiveInspector interface {
	Inspect(context.Context, hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, string) (InspectedHostPlatformReleaseArchive, error)
	Persist(InspectedHostPlatformReleaseArchive, hostinstallationmanagerdomain.HostProductInstallationManifest, hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand) (hostplatformstagedreleaseupdatedomain.CandidateHostRelease, error)
	Remove(InspectedHostPlatformReleaseArchive) error
}
type ActiveReleaseReader interface {
	ReadActiveHostRelease(context.Context, string) (hostplatformstagedreleaseupdatedomain.ActiveHostRelease, error)
}
type OperationStore interface {
	ReadHostPlatformStagedReleaseUpdateOperation(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, string) (hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation, error)
	WriteHostPlatformStagedReleaseUpdateOperation(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation) error
	ReadHostPlatformStagedReleaseRecoveryReceipt(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, string, string) (hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt, error)
	WriteHostPlatformStagedReleaseRecoveryReceipt(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt) error
}

// HostInstallationTransactionRecorder owns the terminal C50 projection of a
// completed/recovered C68 operation. C68 owns the decision to record it; the
// adapter owns the declared C48 filesystem paths and durable writes.
type HostInstallationTransactionRecorder interface {
	RecordHostInstallationTransaction(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, hostinstallationmanagerdomain.HostInstallationJournal, hostinstallationmanagerdomain.HostInstallationReceipt) error
}
type ServiceQuiescer interface {
	QuiesceHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
}
type ReleasePublisher interface {
	PublishStagedHostProductRelease(context.Context, hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, hostplatformstagedreleaseupdatedomain.CandidateHostRelease) error
}
type ReleaseActivator interface {
	ActivateStagedHostProductRelease(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, hostinstallationmanagerdomain.HostProductInstallationManifest) error
}
type ServiceReconciler interface {
	ReconcileHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
}
type Clock interface{ Now() string }

type Workflow struct {
	archiveInspector    ArchiveInspector
	activeReleaseReader ActiveReleaseReader
	operationStore      OperationStore
	transactionRecorder HostInstallationTransactionRecorder
	serviceQuiescer     ServiceQuiescer
	releasePublisher    ReleasePublisher
	releaseActivator    ReleaseActivator
	serviceReconciler   ServiceReconciler
	clock               Clock
}

func NewWorkflow(archiveInspector ArchiveInspector, activeReleaseReader ActiveReleaseReader, operationStore OperationStore, transactionRecorder HostInstallationTransactionRecorder, serviceQuiescer ServiceQuiescer, releasePublisher ReleasePublisher, releaseActivator ReleaseActivator, serviceReconciler ServiceReconciler, clock Clock) (*Workflow, error) {
	if archiveInspector == nil || activeReleaseReader == nil || operationStore == nil || transactionRecorder == nil || serviceQuiescer == nil || releasePublisher == nil || releaseActivator == nil || serviceReconciler == nil || clock == nil {
		return nil, fmt.Errorf("C68 workflow dependencies are required")
	}
	return &Workflow{archiveInspector: archiveInspector, activeReleaseReader: activeReleaseReader, operationStore: operationStore, transactionRecorder: transactionRecorder, serviceQuiescer: serviceQuiescer, releasePublisher: releasePublisher, releaseActivator: releaseActivator, serviceReconciler: serviceReconciler, clock: clock}, nil
}

func (workflow *Workflow) ExecuteHostPlatformStagedReleaseUpdate(ctx context.Context, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, activeManifestPath, artifactPath string) (hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation, error) {
	if ctx == nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("C68 execution context is required")
	}
	if err := hostplatformstagedreleaseupdatedomain.ValidateCommand(command); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if activeManifestPath == "" {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("C68 active Host manifest path is required")
	}
	active, err := workflow.activeReleaseReader.ReadActiveHostRelease(ctx, activeManifestPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("read active C68 Host release: %w", err)
	}
	existing, err := workflow.operationStore.ReadHostPlatformStagedReleaseUpdateOperation(ctx, active.Manifest, command.OperationID)
	if err == nil {
		if !hostplatformstagedreleaseupdatedomain.SameOperation(command, existing) {
			return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("C68 existing operation does not match requested command")
		}
		return existing, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("read C68 operation: %w", err)
	}
	if err := workflow.writeState(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateReceived, nil); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	inspected, err := workflow.archiveInspector.Inspect(ctx, command, artifactPath)
	if err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateReceived, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-release-archive-invalid", err.Error(), "host-update-staging")
	}
	defer workflow.archiveInspector.Remove(inspected)
	candidate, err := workflow.archiveInspector.Persist(inspected, active.Manifest, command)
	if err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateReceived, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-candidate-persistence-failed", err.Error(), "host-installation-manager")
	}
	if err := hostplatformstagedreleaseupdatedomain.DecideAdmission(command, candidate, active); err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateReceived, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-release-transition-blocked", err.Error(), "host-installation-manager")
	}
	if err := workflow.writeState(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateStaged, nil); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if err := workflow.writeState(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateServicesQuiescing, nil); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if err := workflow.serviceQuiescer.QuiesceHostProductServices(ctx, active.Manifest); err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateServicesQuiescing, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-service-quiescence-failed", err.Error(), "host-installation-manager")
	}
	if err := workflow.writeState(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateReleasePublishing, nil); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if err := workflow.releasePublisher.PublishStagedHostProductRelease(ctx, command, candidate); err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateReleasePublishing, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-release-publishing-failed", err.Error(), "host-installation-manager")
	}
	if err := workflow.writeState(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateActivating, nil); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if err := workflow.releaseActivator.ActivateStagedHostProductRelease(ctx, active.Manifest, candidate.Manifest); err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateActivating, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-release-activation-failed", err.Error(), "host-installation-manager")
	}
	if err := workflow.serviceReconciler.ReconcileHostProductServices(ctx, candidate.Manifest); err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateActivating, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-service-finalization-failed", err.Error(), "host-installation-manager")
	}
	now := workflow.clock.Now()
	if err := workflow.recordTerminalHostInstallationTransaction(ctx, candidate.Manifest, command.OperationID, hostinstallationmanagerdomain.HostInstallationJournalCompleted, hostinstallationmanagerdomain.HostInstallationReceiptCompleted, now); err != nil {
		return workflow.fail(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.StateActivating, hostplatformstagedreleaseupdatedomain.StateFailed, "host-platform-installation-transaction-record-failed", err.Error(), "host-installation-manager")
	}
	operation, err := hostplatformstagedreleaseupdatedomain.NewOperation(command, hostplatformstagedreleaseupdatedomain.StateSucceeded, nil, now)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if err := workflow.operationStore.WriteHostPlatformStagedReleaseUpdateOperation(ctx, active.Manifest, operation); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("persist C68 succeeded operation: %w", err)
	}
	return operation, nil
}
func (workflow *Workflow) writeState(ctx context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, state string, issue *hostplatformstagedreleaseupdatedomain.Issue) error {
	operation, err := hostplatformstagedreleaseupdatedomain.NewOperation(command, state, issue, workflow.clock.Now())
	if err != nil {
		return err
	}
	if err := workflow.operationStore.WriteHostPlatformStagedReleaseUpdateOperation(ctx, manifest, operation); err != nil {
		return fmt.Errorf("persist C68 %s operation: %w", state, err)
	}
	return nil
}
func (workflow *Workflow) RecoverHostPlatformStagedReleaseUpdate(ctx context.Context, command hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryCommand, activeManifestPath string) (hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt, error) {
	if ctx == nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("C68 recovery context is required")
	}
	if err := hostplatformstagedreleaseupdatedomain.ValidateRecoveryCommand(command); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	if activeManifestPath == "" {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("C68 recovery active Host manifest path is required")
	}
	active, err := workflow.activeReleaseReader.ReadActiveHostRelease(ctx, activeManifestPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("read active C68 Host release for recovery: %w", err)
	}
	existing, err := workflow.operationStore.ReadHostPlatformStagedReleaseRecoveryReceipt(ctx, active.Manifest, command.OperationID, command.RecoveryID)
	if err == nil {
		if !hostplatformstagedreleaseupdatedomain.SameRecoveryCommand(command, existing) {
			return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("C68 existing recovery receipt does not match requested command")
		}
		return existing, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("read C68 recovery receipt: %w", err)
	}
	prior, err := workflow.operationStore.ReadHostPlatformStagedReleaseUpdateOperation(ctx, active.Manifest, command.OperationID)
	if errors.Is(err, os.ErrNotExist) {
		return workflow.blockRecovery(ctx, active.Manifest, command, "recovery-operation-not-found", "no C68 operation exists for the declared recovery operation id")
	}
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("read C68 operation for recovery: %w", err)
	}
	if issue := hostplatformstagedreleaseupdatedomain.DecideRecoveryAdmission(command, prior, active); issue != nil {
		return workflow.writeRecoveryReceipt(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.RecoveryStateBlocked, "", issue)
	}
	if err := workflow.serviceReconciler.ReconcileHostProductServices(ctx, active.Manifest); err != nil {
		return workflow.writeRecoveryReceipt(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.RecoveryStateFailed, "", &hostplatformstagedreleaseupdatedomain.Issue{Code: "recovery-service-reconciliation-failed", Message: err.Error(), Dependency: "host-installation-manager"})
	}
	now := workflow.clock.Now()
	if err := workflow.recordTerminalHostInstallationTransaction(ctx, active.Manifest, command.OperationID, hostinstallationmanagerdomain.HostInstallationJournalRecovered, hostinstallationmanagerdomain.HostInstallationReceiptRecovered, now); err != nil {
		return workflow.writeRecoveryReceipt(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.RecoveryStateFailed, "", &hostplatformstagedreleaseupdatedomain.Issue{Code: "recovery-installation-transaction-record-failed", Message: err.Error(), Dependency: "host-installation-manager"})
	}
	return workflow.writeRecoveryReceipt(ctx, active.Manifest, command, hostplatformstagedreleaseupdatedomain.RecoveryStateSucceeded, active.Manifest.Release.ID, nil)
}

func (workflow *Workflow) recordTerminalHostInstallationTransaction(ctx context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, operationID, journalState, receiptState, observedAt string) error {
	journal := hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-journal",
		ID:             operationID + "-installation-journal",
		RequestID:      operationID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          journalState,
		CreatedAt:      observedAt,
		UpdatedAt:      observedAt,
	}
	receipt := hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-receipt",
		ID:             operationID + "-installation-receipt",
		RequestID:      operationID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          receiptState,
		ObservedAt:     observedAt,
	}
	if err := workflow.transactionRecorder.RecordHostInstallationTransaction(ctx, manifest, journal, receipt); err != nil {
		return fmt.Errorf("record terminal C50 transaction: %w", err)
	}
	return nil
}

func (workflow *Workflow) writeRecoveryReceipt(ctx context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, command hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryCommand, state, activeReleaseID string, issue *hostplatformstagedreleaseupdatedomain.Issue) (hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt, error) {
	receipt, err := hostplatformstagedreleaseupdatedomain.NewRecoveryReceipt(command, state, activeReleaseID, issue, workflow.clock.Now())
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	if err := workflow.operationStore.WriteHostPlatformStagedReleaseRecoveryReceipt(ctx, manifest, receipt); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("persist C68 recovery receipt: %w", err)
	}
	return receipt, nil
}

func (workflow *Workflow) blockRecovery(ctx context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, command hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryCommand, code, message string) (hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt, error) {
	return workflow.writeRecoveryReceipt(ctx, manifest, command, hostplatformstagedreleaseupdatedomain.RecoveryStateBlocked, "", &hostplatformstagedreleaseupdatedomain.Issue{Code: code, Message: message, Dependency: "host-installation-manager"})
}

func (workflow *Workflow) fail(ctx context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, lastDurableState, state, code, message, dependency string) (hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation, error) {
	operation := hostplatformstagedreleaseupdatedomain.Failure(command, state, lastDurableState, code, message, dependency, workflow.clock.Now())
	if err := workflow.operationStore.WriteHostPlatformStagedReleaseUpdateOperation(ctx, manifest, operation); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("persist C68 failure operation: %w", err)
	}
	return operation, nil
}
