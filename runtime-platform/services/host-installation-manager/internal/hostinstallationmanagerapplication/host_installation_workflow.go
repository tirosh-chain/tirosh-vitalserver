// Package hostinstallationmanagerapplication orchestrates explicit Host
// installation effects. Domain policy remains in hostinstallationmanagerdomain;
// adapters own filesystem, package-manager, and launchd interaction.
package hostinstallationmanagerapplication

import (
	"context"
	"fmt"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type HostProductInstallationManifestReader interface {
	ReadHostProductInstallationManifest(context.Context, string) (hostinstallationmanagerdomain.HostProductInstallationManifest, error)
}

type HostInstallationFootprintObserver interface {
	ObserveHostInstallationFootprint(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, string) (hostinstallationmanagerdomain.HostInstallationFootprint, error)
}

type HostInstallationJournalStore interface {
	ReadHostInstallationJournal(context.Context, string) (hostinstallationmanagerdomain.HostInstallationJournal, error)
	WriteHostInstallationJournal(context.Context, string, hostinstallationmanagerdomain.HostInstallationJournal) error
}

type HostInstallationReceiptStore interface {
	WriteHostInstallationReceipt(context.Context, string, hostinstallationmanagerdomain.HostInstallationReceipt) error
}

type HostProductReleaseActivator interface {
	ActivateHostProductRelease(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
}

// HostProductServiceQuiescer owns the Host-specific effect of stopping the
// services declared by C48. It receives the manifest rather than labels
// inferred by a package script, so service ownership stays explicit.
type HostProductServiceQuiescer interface {
	QuiesceHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
}

type HostInstallationClock interface {
	Now() time.Time
}

type HostInstallationWorkflow struct {
	manifestReader    HostProductInstallationManifestReader
	footprintObserver HostInstallationFootprintObserver
	journalStore      HostInstallationJournalStore
	receiptStore      HostInstallationReceiptStore
	releaseActivator  HostProductReleaseActivator
	serviceQuiescer   HostProductServiceQuiescer
	clock             HostInstallationClock
}

func NewHostInstallationWorkflow(
	manifestReader HostProductInstallationManifestReader,
	footprintObserver HostInstallationFootprintObserver,
	journalStore HostInstallationJournalStore,
	receiptStore HostInstallationReceiptStore,
	releaseActivator HostProductReleaseActivator,
	serviceQuiescer HostProductServiceQuiescer,
	clock HostInstallationClock,
) (*HostInstallationWorkflow, error) {
	if manifestReader == nil || footprintObserver == nil || journalStore == nil || receiptStore == nil || releaseActivator == nil || serviceQuiescer == nil || clock == nil {
		return nil, fmt.Errorf("Host Installation Manager workflow dependencies are required")
	}
	return &HostInstallationWorkflow{
		manifestReader:    manifestReader,
		footprintObserver: footprintObserver,
		journalStore:      journalStore,
		receiptStore:      receiptStore,
		releaseActivator:  releaseActivator,
		serviceQuiescer:   serviceQuiescer,
		clock:             clock,
	}, nil
}

// ExecuteHostInstallationPreflight writes a durable journal only for an
// admitted installation. A blocked direct update produces an explicit receipt
// and does not create a transaction that a later installer could misread.
func (workflow *HostInstallationWorkflow) ExecuteHostInstallationPreflight(
	context context.Context,
	request hostinstallationmanagerdomain.HostInstallationRequest,
	manifestPath string,
	journalPath string,
	receiptPath string,
) (hostinstallationmanagerdomain.HostInstallationReceipt, error) {
	manifest, err := workflow.manifestReader.ReadHostProductInstallationManifest(context, manifestPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("read Host product installation manifest: %w", err)
	}
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, journalPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("observe Host installation footprint: %w", err)
	}
	decision, err := hostinstallationmanagerdomain.DecideHostInstallationPreflight(request, manifest, footprint)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decide Host installation preflight: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	receipt := hostInstallationReceiptForDecision(request, manifest, decision, now)
	if decision.State == "admitted" {
		journal := hostinstallationmanagerdomain.HostInstallationJournal{
			SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
			DocumentKind:   "host-installation-journal",
			ID:             request.ID + "-journal",
			RequestID:      request.ID,
			InstallationID: manifest.InstallationID,
			ReleaseID:      manifest.Release.ID,
			State:          hostinstallationmanagerdomain.HostInstallationJournalPreflightVerified,
			CreatedAt:      now,
			UpdatedAt:      now,
		}
		if err := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, journal); err != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write admitted Host installation journal: %w", err)
		}
	}
	if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write Host installation preflight receipt: %w", err)
	}
	return receipt, nil
}

// ExecuteHostProductServiceQuiescence stops only C48-declared Host services
// after a successful preflight and before pkgbuild replaces immutable bytes.
// It persists activation-pending only after every declared service has been
// quiesced successfully; a partial quiescence remains an explicit failed
// transaction that must be recovered deliberately.
func (workflow *HostInstallationWorkflow) ExecuteHostProductServiceQuiescence(
	context context.Context,
	manifestPath string,
	journalPath string,
	receiptPath string,
) (hostinstallationmanagerdomain.HostInstallationReceipt, error) {
	manifest, err := workflow.manifestReader.ReadHostProductInstallationManifest(context, manifestPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("read Host product installation manifest: %w", err)
	}
	journal, err := workflow.journalStore.ReadHostInstallationJournal(context, journalPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("read Host installation journal: %w", err)
	}
	request := hostinstallationmanagerdomain.HostInstallationRequest{
		SchemaVersion:     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:      "host-installation-request",
		ID:                journal.RequestID,
		InstallationID:    journal.InstallationID,
		Operation:         hostinstallationmanagerdomain.HostInstallationOperationQuiesceServices,
		ExpectedReleaseID: journal.ReleaseID,
		RequestedAt:       journal.UpdatedAt,
	}
	decision, err := hostinstallationmanagerdomain.DecideHostProductServiceQuiescence(request, manifest, journal)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decide Host product service quiescence: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	if decision.State != "admitted" {
		receipt := hostInstallationReceiptForDecision(request, manifest, decision, now)
		if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write blocked Host service quiescence receipt: %w", err)
		}
		return receipt, nil
	}
	if err := workflow.serviceQuiescer.QuiesceHostProductServices(context, manifest); err != nil {
		failedJournal := journal
		failedJournal.State = hostinstallationmanagerdomain.HostInstallationJournalFailed
		failedJournal.Failure = &hostinstallationmanagerdomain.HostInstallationIssue{Code: "service-quiescence-failed", Message: err.Error()}
		failedJournal.UpdatedAt = now
		if writeError := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, failedJournal); writeError != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("quiesce Host product services: %w; persist service quiescence failure: %v", err, writeError)
		}
		receipt := hostInstallationReceiptForDecision(request, manifest, hostinstallationmanagerdomain.HostInstallationDecision{State: "failed", Issue: failedJournal.Failure}, now)
		if writeError := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); writeError != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("quiesce Host product services: %w; write service quiescence failure receipt: %v", err, writeError)
		}
		return receipt, nil
	}
	pendingJournal := journal
	pendingJournal.State = hostinstallationmanagerdomain.HostInstallationJournalActivationPending
	pendingJournal.Failure = nil
	pendingJournal.UpdatedAt = now
	if err := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, pendingJournal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("persist Host service quiescence journal: %w", err)
	}
	receipt := hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-receipt",
		ID:             request.ID + "-receipt",
		RequestID:      request.ID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationReceiptServicesQuiesced,
		ObservedAt:     now,
	}
	if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write Host service quiescence receipt: %w", err)
	}
	return receipt, nil
}

// ExecuteHostProductReleaseActivation realizes only the already-admitted C50
// transaction. It verifies the written immutable slot before changing the
// current-release link, then persists terminal state.
func (workflow *HostInstallationWorkflow) ExecuteHostProductReleaseActivation(
	context context.Context,
	manifestPath string,
	journalPath string,
	receiptPath string,
) (hostinstallationmanagerdomain.HostInstallationReceipt, error) {
	manifest, err := workflow.manifestReader.ReadHostProductInstallationManifest(context, manifestPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("read Host product installation manifest: %w", err)
	}
	journal, err := workflow.journalStore.ReadHostInstallationJournal(context, journalPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("read Host installation journal: %w", err)
	}
	request := hostinstallationmanagerdomain.HostInstallationRequest{
		SchemaVersion:     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:      "host-installation-request",
		ID:                journal.RequestID,
		InstallationID:    journal.InstallationID,
		Operation:         hostinstallationmanagerdomain.HostInstallationOperationActivateRelease,
		ExpectedReleaseID: journal.ReleaseID,
		RequestedAt:       journal.UpdatedAt,
	}
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, journalPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("observe Host installation footprint: %w", err)
	}
	decision, err := hostinstallationmanagerdomain.DecideHostProductReleaseActivation(request, manifest, footprint, journal)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decide Host product release activation: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	if decision.State != "admitted" {
		receipt := hostInstallationReceiptForDecision(request, manifest, decision, now)
		if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write blocked Host installation activation receipt: %w", err)
		}
		return receipt, nil
	}
	if err := workflow.releaseActivator.ActivateHostProductRelease(context, manifest); err != nil {
		failedJournal := journal
		failedJournal.State = hostinstallationmanagerdomain.HostInstallationJournalFailed
		failedJournal.Failure = &hostinstallationmanagerdomain.HostInstallationIssue{Code: "release-activation-failed", Message: err.Error()}
		failedJournal.UpdatedAt = now
		if writeError := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, failedJournal); writeError != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("activate Host product release: %w; persist activation failure: %v", err, writeError)
		}
		receipt := hostInstallationReceiptForDecision(request, manifest, hostinstallationmanagerdomain.HostInstallationDecision{State: "failed", Issue: failedJournal.Failure}, now)
		if writeError := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); writeError != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("activate Host product release: %w; write activation failure receipt: %v", err, writeError)
		}
		return receipt, nil
	}
	completedJournal := journal
	completedJournal.State = hostinstallationmanagerdomain.HostInstallationJournalActivated
	completedJournal.Failure = nil
	completedJournal.UpdatedAt = now
	if err := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, completedJournal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("persist activated Host installation journal: %w", err)
	}
	receipt := hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-receipt",
		ID:             request.ID + "-receipt",
		RequestID:      request.ID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationReceiptActivated,
		ObservedAt:     now,
	}
	if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write activated Host installation receipt: %w", err)
	}
	return receipt, nil
}

func hostInstallationReceiptForDecision(
	request hostinstallationmanagerdomain.HostInstallationRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	decision hostinstallationmanagerdomain.HostInstallationDecision,
	observedAt string,
) hostinstallationmanagerdomain.HostInstallationReceipt {
	state := hostinstallationmanagerdomain.HostInstallationReceiptBlocked
	if decision.State == "admitted" {
		state = hostinstallationmanagerdomain.HostInstallationReceiptPreflightAdmitted
	}
	if decision.State == "failed" {
		state = hostinstallationmanagerdomain.HostInstallationReceiptFailed
	}
	return hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-receipt",
		ID:             request.ID + "-receipt",
		RequestID:      request.ID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          state,
		Issue:          decision.Issue,
		ObservedAt:     observedAt,
	}
}

type systemHostInstallationClock struct{}

func (systemHostInstallationClock) Now() time.Time { return time.Now() }

func NewSystemHostInstallationClock() HostInstallationClock { return systemHostInstallationClock{} }
