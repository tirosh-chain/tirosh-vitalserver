// Package hostinstallationmanagerapplication orchestrates explicit Host
// installation effects. Domain policy remains in hostinstallationmanagerdomain;
// adapters own filesystem, package-manager, and launchd interaction.
package hostinstallationmanagerapplication

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type HostProductInstallationManifestReader interface {
	ReadHostProductInstallationManifest(context.Context, string) (hostinstallationmanagerdomain.HostProductInstallationManifest, error)
}

type HostInstallationFootprintObserver interface {
	ObserveHostInstallationFootprint(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, string, string) (hostinstallationmanagerdomain.HostInstallationFootprint, error)
}

type HostInstallationJournalStore interface {
	ReadHostInstallationJournal(context.Context, string) (hostinstallationmanagerdomain.HostInstallationJournal, error)
	WriteHostInstallationJournal(context.Context, string, hostinstallationmanagerdomain.HostInstallationJournal) error
}

type HostInstallationReceiptStore interface {
	WriteHostInstallationReceipt(context.Context, string, hostinstallationmanagerdomain.HostInstallationReceipt) error
}

// HostProductRemovalJournalStore persists the independent C54 lifecycle.
// C50 installation transactions and C54 removal transactions must never be
// decoded as one another merely because both happen below product data.
type HostProductRemovalJournalStore interface {
	ReadHostProductRemovalJournal(context.Context, string) (hostinstallationmanagerdomain.HostProductRemovalJournal, error)
	WriteHostProductRemovalJournal(context.Context, string, hostinstallationmanagerdomain.HostProductRemovalJournal) error
}

type HostProductRemovalReceiptStore interface {
	WriteHostProductRemovalReceipt(context.Context, string, hostinstallationmanagerdomain.HostProductRemovalReceipt) error
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

// HostProductServiceReconciler owns the Host-specific effect that makes the
// C48-declared service registrations match the selected current release.
// It is deliberately separate from quiescence: recovery can reconcile after
// an interrupted stop/activate/finalize sequence without guessing services.
type HostProductServiceReconciler interface {
	ReconcileHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
}

// HostProductRemovalEffects owns the physical effects of an already-admitted
// C54 plan. Each method is deliberately semantic so the application does not
// choose paths, labels, or package identities from Host conventions.
type HostProductRemovalEffects interface {
	PrepareHostProductPackageManagerCompletionTransport(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport) error
	RemoveHostProductServiceDefinitions(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
	RemoveHostProductOperatorApplication(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
	RemoveHostProductActivationLink(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
	RemoveHostProductReleaseCatalog(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error
	RemoveHostProductMutableStores(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) error
	RemoveHostProductPackageReceipt(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) (hostinstallationmanagerdomain.HostProductPackageReceiptRemoval, error)
}

type HostInstallationClock interface {
	Now() time.Time
}

type HostInstallationWorkflow struct {
	manifestReader      HostProductInstallationManifestReader
	footprintObserver   HostInstallationFootprintObserver
	journalStore        HostInstallationJournalStore
	receiptStore        HostInstallationReceiptStore
	releaseActivator    HostProductReleaseActivator
	serviceQuiescer     HostProductServiceQuiescer
	serviceReconciler   HostProductServiceReconciler
	removalJournalStore HostProductRemovalJournalStore
	removalReceiptStore HostProductRemovalReceiptStore
	removalEffects      HostProductRemovalEffects
	clock               HostInstallationClock
}

func NewHostInstallationWorkflow(
	manifestReader HostProductInstallationManifestReader,
	footprintObserver HostInstallationFootprintObserver,
	journalStore HostInstallationJournalStore,
	receiptStore HostInstallationReceiptStore,
	releaseActivator HostProductReleaseActivator,
	serviceQuiescer HostProductServiceQuiescer,
	serviceReconciler HostProductServiceReconciler,
	clock HostInstallationClock,
) (*HostInstallationWorkflow, error) {
	if manifestReader == nil || footprintObserver == nil || journalStore == nil || receiptStore == nil || releaseActivator == nil || serviceQuiescer == nil || serviceReconciler == nil || clock == nil {
		return nil, fmt.Errorf("Host Installation Manager workflow dependencies are required")
	}
	return &HostInstallationWorkflow{
		manifestReader:    manifestReader,
		footprintObserver: footprintObserver,
		journalStore:      journalStore,
		receiptStore:      receiptStore,
		releaseActivator:  releaseActivator,
		serviceQuiescer:   serviceQuiescer,
		serviceReconciler: serviceReconciler,
		clock:             clock,
	}, nil
}

// NewHostInstallationWorkflowWithRemoval keeps C54 dependencies explicit at
// the composition root. Existing package-install callers use the smaller C50
// constructor and cannot accidentally invoke a removal with missing effects.
func NewHostInstallationWorkflowWithRemoval(
	manifestReader HostProductInstallationManifestReader,
	footprintObserver HostInstallationFootprintObserver,
	journalStore HostInstallationJournalStore,
	receiptStore HostInstallationReceiptStore,
	releaseActivator HostProductReleaseActivator,
	serviceQuiescer HostProductServiceQuiescer,
	serviceReconciler HostProductServiceReconciler,
	removalJournalStore HostProductRemovalJournalStore,
	removalReceiptStore HostProductRemovalReceiptStore,
	removalEffects HostProductRemovalEffects,
	clock HostInstallationClock,
) (*HostInstallationWorkflow, error) {
	workflow, err := NewHostInstallationWorkflow(manifestReader, footprintObserver, journalStore, receiptStore, releaseActivator, serviceQuiescer, serviceReconciler, clock)
	if err != nil {
		return nil, err
	}
	if removalJournalStore == nil || removalReceiptStore == nil || removalEffects == nil {
		return nil, fmt.Errorf("Host product removal workflow dependencies are required")
	}
	workflow.removalJournalStore = removalJournalStore
	workflow.removalReceiptStore = removalReceiptStore
	workflow.removalEffects = removalEffects
	return workflow, nil
}

// ObserveDeclaredHostInstallationFootprint exposes C49 as a read-only
// Host-owned contract. C48 names the only C50 transaction store that may be
// observed; a caller cannot substitute an arbitrary journal or receipt path.
// It intentionally does not run transition policy, write a C50 transaction,
// or reconcile services: callers that need an operational fact must receive
// the adapter observation rather than recreate one from an installer log or a
// path convention.
func (workflow *HostInstallationWorkflow) ObserveDeclaredHostInstallationFootprint(
	context context.Context,
	manifestPath string,
) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	manifest, err := workflow.manifestReader.ReadHostProductInstallationManifest(context, manifestPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("read Host product installation manifest: %w", err)
	}
	journalPath, receiptPath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionPaths(manifest)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("resolve declared C50 transaction paths: %w", err)
	}
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("observe Host installation footprint: %w", err)
	}
	return footprint, nil
}

// ExecuteHostInstallationPreflight writes durable product state only for an
// admitted installation. A blocked preflight is returned as a structured
// operation result for the package log, but it must not create a receipt,
// journal, or parent directory below the product data boundary. Otherwise an
// install that never began would leave a stale footprint that later preflight
// could not distinguish from user or product state.
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
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("observe Host installation footprint: %w", err)
	}
	decision, err := hostinstallationmanagerdomain.DecideHostInstallationPreflight(request, manifest, footprint)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decide Host installation preflight: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	receipt := hostInstallationReceiptForDecision(request, manifest, decision, now)
	if decision.State != "admitted" {
		return receipt, nil
	}
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
	if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write Host installation preflight receipt: %w", err)
	}
	return receipt, nil
}

// ExecuteHostProductServiceQuiescence stops only C48-declared Host services
// after the package has written the immutable slot. It first persists
// services-quiescing, so a process interruption during launchctl effects is
// recoverable rather than indistinguishable from an untouched preflight.
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
	quiescingJournal := journal
	quiescingJournal.State = hostinstallationmanagerdomain.HostInstallationJournalServicesQuiescing
	quiescingJournal.Failure = nil
	quiescingJournal.UpdatedAt = now
	if err := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, quiescingJournal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("persist Host service quiescence intent: %w", err)
	}
	if err := workflow.serviceQuiescer.QuiesceHostProductServices(context, manifest); err != nil {
		failedJournal := quiescingJournal
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
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
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

// ExecuteHostProductServiceFinalization reconciles the C48-declared Host
// services only after current points to the verified immutable release. A
// successful activation is therefore not reported as a completed install
// until service registration has also succeeded.
func (workflow *HostInstallationWorkflow) ExecuteHostProductServiceFinalization(
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
	request := hostInstallationRequestFromJournal(hostinstallationmanagerdomain.HostInstallationOperationFinalizeServices, journal)
	decision, err := hostinstallationmanagerdomain.DecideHostProductServiceFinalization(request, manifest, journal)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decide Host product service finalization: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	if decision.State != "admitted" {
		receipt := hostInstallationReceiptForDecision(request, manifest, decision, now)
		if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write blocked Host service finalization receipt: %w", err)
		}
		return receipt, nil
	}
	if err := workflow.serviceReconciler.ReconcileHostProductServices(context, manifest); err != nil {
		return workflow.recordHostInstallationFailure(context, request, manifest, journalPath, receiptPath, journal, "service-finalization-failed", err, now)
	}
	completedJournal := journal
	completedJournal.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	completedJournal.Failure = nil
	completedJournal.UpdatedAt = now
	if err := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, completedJournal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("persist completed Host installation journal: %w", err)
	}
	receipt := hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-receipt",
		ID:             request.ID + "-receipt",
		RequestID:      request.ID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationReceiptCompleted,
		ObservedAt:     now,
	}
	if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write completed Host installation receipt: %w", err)
	}
	return receipt, nil
}

// ExecuteHostInstallationRecovery is the explicit compensating workflow for
// an interrupted postinstall sequence. It never derives an old release or
// service set: it either marks an unstarted preflight recovered, or proves and
// completes the exact C48 release recorded in C50.
func (workflow *HostInstallationWorkflow) ExecuteHostInstallationRecovery(
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
	request := hostInstallationRequestFromJournal(hostinstallationmanagerdomain.HostInstallationOperationRecoverInstallation, journal)
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("observe Host installation footprint for recovery: %w", err)
	}
	decision, err := hostinstallationmanagerdomain.DecideHostInstallationRecovery(request, manifest, footprint, journal)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decide Host installation recovery: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	if decision.State != "admitted" {
		receipt := hostInstallationReceiptForDecision(request, manifest, decision, now)
		if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write blocked Host installation recovery receipt: %w", err)
		}
		return receipt, nil
	}
	if decision.Mode == "recovery-already-terminal" {
		state := hostinstallationmanagerdomain.HostInstallationReceiptCompleted
		if journal.State == hostinstallationmanagerdomain.HostInstallationJournalRecovered {
			state = hostinstallationmanagerdomain.HostInstallationReceiptRecovered
		}
		receipt := hostInstallationReceipt(request, manifest, state, nil, now)
		if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write terminal Host installation recovery receipt: %w", err)
		}
		return receipt, nil
	}
	if decision.Mode == "recover-release-and-services" {
		if err := workflow.releaseActivator.ActivateHostProductRelease(context, manifest); err != nil {
			return workflow.recordHostInstallationFailure(context, request, manifest, journalPath, receiptPath, journal, "recovery-release-activation-failed", err, now)
		}
		if err := workflow.serviceReconciler.ReconcileHostProductServices(context, manifest); err != nil {
			return workflow.recordHostInstallationFailure(context, request, manifest, journalPath, receiptPath, journal, "recovery-service-reconciliation-failed", err, now)
		}
	}
	recoveredJournal := journal
	recoveredJournal.State = hostinstallationmanagerdomain.HostInstallationJournalRecovered
	recoveredJournal.Failure = nil
	recoveredJournal.UpdatedAt = now
	if err := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, recoveredJournal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("persist recovered Host installation journal: %w", err)
	}
	receipt := hostInstallationReceipt(request, manifest, hostinstallationmanagerdomain.HostInstallationReceiptRecovered, nil, now)
	if err := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("write recovered Host installation receipt: %w", err)
	}
	return receipt, nil
}

// ExecuteHostProductRemoval implements the explicit C54 lifecycle. It
// persists removal intent before every destructive phase, stops only the
// C48-declared services, and verifies the complete observed C49 footprint at
// the end. A preserve request retains mutable stores and a durable C54
// receipt; a purge deliberately leaves no in-product journal or receipt.
func (workflow *HostInstallationWorkflow) ExecuteHostProductRemoval(
	context context.Context,
	request hostinstallationmanagerdomain.HostProductRemovalRequest,
	manifestPath string,
	installationJournalPath string,
	installationReceiptPath string,
	removalJournalPath string,
	removalReceiptPath string,
) (hostinstallationmanagerdomain.HostProductRemovalReceipt, error) {
	if workflow.removalJournalStore == nil || workflow.removalReceiptStore == nil || workflow.removalEffects == nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("Host product removal is not configured in this workflow")
	}
	manifest, err := workflow.manifestReader.ReadHostProductInstallationManifest(context, manifestPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("read Host product installation manifest: %w", err)
	}
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, installationJournalPath, installationReceiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("observe Host installation footprint for product removal: %w", err)
	}
	plan, decision, err := hostinstallationmanagerdomain.DecideHostProductRemoval(request, manifest, footprint, removalJournalPath, removalReceiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("decide Host product removal: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	if decision.State != "admitted" {
		return hostProductRemovalReceiptForDecision(request, manifest, decision, now), nil
	}
	if existingJournal, readError := workflow.removalJournalStore.ReadHostProductRemovalJournal(context, removalJournalPath); readError == nil {
		if existingJournal.InstallationID != manifest.InstallationID || existingJournal.ReleaseID != manifest.Release.ID || existingJournal.State != hostinstallationmanagerdomain.HostProductRemovalJournalCompleted {
			return hostProductRemovalReceiptForDecision(request, manifest, hostinstallationmanagerdomain.HostInstallationDecision{State: "blocked", Issue: &hostinstallationmanagerdomain.HostInstallationIssue{Code: "unfinished-product-removal-transaction", Message: "an earlier product removal journal remains; inspect or recover it explicitly before another removal"}}, now), nil
		}
	} else if !errors.Is(readError, os.ErrNotExist) {
		// `os.ErrNotExist` is preserved by the file adapter. All other errors are
		// an unreadable removal boundary, never evidence that no transaction ran.
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("read Host product removal journal: %w", readError)
	}
	journal := hostProductRemovalJournal(request, manifest, hostinstallationmanagerdomain.HostProductRemovalJournalAdmitted, nil, now, now)
	if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, journal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("write Host product removal admission journal: %w", err)
	}
	if plan.PreparePackageManagerCompletionTransport {
		if request.PackageManagerCompletionTransport == nil {
			return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("admitted Host product removal is missing its package-manager completion transport")
		}
		if err := workflow.removalEffects.PrepareHostProductPackageManagerCompletionTransport(context, manifest, *request.PackageManagerCompletionTransport); err != nil {
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "package-manager-completion-transport-preparation-failed", err, now)
		}
	}
	journal.State = hostinstallationmanagerdomain.HostProductRemovalJournalServicesQuiescing
	journal.UpdatedAt = now
	if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, journal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("persist Host product removal service quiescence intent: %w", err)
	}
	if err := workflow.serviceQuiescer.QuiesceHostProductServices(context, manifest); err != nil {
		return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "service-quiescence-failed", err, now)
	}
	if err := workflow.removalEffects.RemoveHostProductServiceDefinitions(context, manifest); err != nil {
		return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "service-definition-removal-failed", err, now)
	}
	journal.State = hostinstallationmanagerdomain.HostProductRemovalJournalImmutableContentRemoving
	journal.UpdatedAt = now
	if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, journal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("persist Host product removal immutable-content intent: %w", err)
	}
	if plan.RemoveOperatorApplication {
		if err := workflow.removalEffects.RemoveHostProductOperatorApplication(context, manifest); err != nil {
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "operator-application-removal-failed", err, now)
		}
	}
	if plan.RemoveActivationLink {
		if err := workflow.removalEffects.RemoveHostProductActivationLink(context, manifest); err != nil {
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "release-activation-removal-failed", err, now)
		}
	}
	if plan.RemoveReleaseCatalog {
		if err := workflow.removalEffects.RemoveHostProductReleaseCatalog(context, manifest); err != nil {
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "release-catalog-removal-failed", err, now)
		}
	}
	if len(plan.RemoveMutableStores) != 0 {
		journal.State = hostinstallationmanagerdomain.HostProductRemovalJournalMutableDataRemoving
		journal.UpdatedAt = now
		if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, journal); err != nil {
			return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("persist Host product removal mutable-data intent: %w", err)
		}
		if err := workflow.removalEffects.RemoveHostProductMutableStores(context, manifest, plan.RemoveMutableStores); err != nil {
			if request.DataDisposition == hostinstallationmanagerdomain.HostProductRemovalDataDispositionPurgeAllProductData {
				// A partially completed purge may already have removed the journal
				// directory. Do not recreate product data merely to record a
				// failure; return the explicit failed receipt to the caller.
				return hostProductRemovalReceipt(request, manifest, hostinstallationmanagerdomain.HostProductRemovalReceiptFailed, "", &hostinstallationmanagerdomain.HostInstallationIssue{Code: "mutable-store-removal-failed", Message: err.Error()}, nil, now), nil
			}
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "mutable-store-removal-failed", err, now)
		}
	}
	packageReceiptRemoval := hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{State: hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByManager}
	if plan.RemovePackageReceipt {
		var packageReceiptRemovalError error
		packageReceiptRemoval, packageReceiptRemovalError = workflow.removalEffects.RemoveHostProductPackageReceipt(context, manifest)
		if packageReceiptRemovalError != nil {
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "package-receipt-removal-failed", packageReceiptRemovalError, now)
		}
	}
	completedFootprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, installationJournalPath, installationReceiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("observe completed Host product removal footprint: %w", err)
	}
	completedAt := workflow.clock.Now().UTC().Format(time.RFC3339)
	if packageReceiptRemoval.State == hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager {
		pending, retainedStoreIDs, pendingError := hostinstallationmanagerdomain.DecideHostProductRemovalAwaitingPackageManager(request, manifest, completedFootprint)
		if pendingError != nil {
			return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("decide Host product removal package-manager hand-off: %w", pendingError)
		}
		if pending.State != "admitted" {
			issue := pending.Issue
			if issue == nil {
				issue = &hostinstallationmanagerdomain.HostInstallationIssue{Code: "product-removal-package-manager-handoff-not-proven", Message: "the Host footprint did not prove safe OS package-manager hand-off"}
			}
			if request.DataDisposition == hostinstallationmanagerdomain.HostProductRemovalDataDispositionPurgeAllProductData {
				return hostProductRemovalReceipt(request, manifest, hostinstallationmanagerdomain.HostProductRemovalReceiptFailed, "", issue, nil, completedAt), nil
			}
			return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, issue.Code, fmt.Errorf("%s", issue.Message), completedAt)
		}
		receipt := hostProductRemovalReceipt(request, manifest, hostinstallationmanagerdomain.HostProductRemovalReceiptAwaitingPackageManager, hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager, nil, retainedStoreIDs, completedAt)
		if request.DataDisposition == hostinstallationmanagerdomain.HostProductRemovalDataDispositionPurgeAllProductData {
			// The declared purge removed the only mutable location that could retain
			// a C54 document. stdout is the explicit hand-off proof until the OS
			// package manager removes its own receipt.
			return receipt, nil
		}
		journal.State = hostinstallationmanagerdomain.HostProductRemovalJournalAwaitingPackageManager
		journal.Failure = nil
		journal.UpdatedAt = completedAt
		if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, journal); err != nil {
			return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("persist Host product removal package-manager hand-off journal: %w", err)
		}
		if err := workflow.removalReceiptStore.WriteHostProductRemovalReceipt(context, removalReceiptPath, receipt); err != nil {
			return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("write Host product removal package-manager hand-off receipt: %w", err)
		}
		return receipt, nil
	}
	if packageReceiptRemoval.State != hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByManager {
		return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, "package-receipt-removal-outcome-invalid", fmt.Errorf("package receipt removal returned unsupported outcome %q", packageReceiptRemoval.State), completedAt)
	}
	completion, retainedStoreIDs, err := hostinstallationmanagerdomain.DecideHostProductRemovalCompletion(request, manifest, completedFootprint)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("decide Host product removal completion: %w", err)
	}
	if completion.State != "admitted" {
		if request.DataDisposition == hostinstallationmanagerdomain.HostProductRemovalDataDispositionPurgeAllProductData {
			issue := completion.Issue
			if issue == nil {
				issue = &hostinstallationmanagerdomain.HostInstallationIssue{Code: "product-removal-completion-not-proven", Message: "the final Host footprint did not prove product removal"}
			}
			return hostProductRemovalReceipt(request, manifest, hostinstallationmanagerdomain.HostProductRemovalReceiptFailed, "", issue, nil, completedAt), nil
		}
		issue := completion.Issue
		if issue == nil {
			issue = &hostinstallationmanagerdomain.HostInstallationIssue{Code: "product-removal-completion-not-proven", Message: "the final Host footprint did not prove product removal"}
		}
		return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, issue.Code, fmt.Errorf("%s", issue.Message), completedAt)
	}
	receipt := hostProductRemovalReceipt(request, manifest, hostinstallationmanagerdomain.HostProductRemovalReceiptCompleted, hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByManager, nil, retainedStoreIDs, completedAt)
	if request.DataDisposition == hostinstallationmanagerdomain.HostProductRemovalDataDispositionPurgeAllProductData {
		// The mutable-store effect intentionally removed the C54 journal path.
		// The returned stdout document is the completion evidence; recreating a
		// file here would violate the selected clean-Host disposition.
		return receipt, nil
	}
	journal.State = hostinstallationmanagerdomain.HostProductRemovalJournalCompleted
	journal.Failure = nil
	journal.UpdatedAt = completedAt
	if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, journal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("persist completed Host product removal journal: %w", err)
	}
	if err := workflow.removalReceiptStore.WriteHostProductRemovalReceipt(context, removalReceiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("write Host product removal receipt: %w", err)
	}
	return receipt, nil
}

// CompleteHostProductRemovalAfterPackageManager finishes the C54 hand-off
// after dpkg/MSI has removed its own installed-package receipt. It has no
// removal effects: it reads the pending C54 journal and C49 footprint, then
// records the terminal proof only when the OS-owned receipt is observably
// absent. Package maintainer scripts can therefore return control to their
// owner without a recursive uninstall.
func (workflow *HostInstallationWorkflow) CompleteHostProductRemovalAfterPackageManager(
	context context.Context,
	manifestPath string,
	installationJournalPath string,
	installationReceiptPath string,
	removalJournalPath string,
	removalReceiptPath string,
) (hostinstallationmanagerdomain.HostProductRemovalReceipt, error) {
	if workflow.removalJournalStore == nil || workflow.removalReceiptStore == nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("Host product removal completion is not configured in this workflow")
	}
	manifest, err := workflow.manifestReader.ReadHostProductInstallationManifest(context, manifestPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("read Host product installation manifest: %w", err)
	}
	journal, err := workflow.removalJournalStore.ReadHostProductRemovalJournal(context, removalJournalPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("read pending Host product removal journal: %w", err)
	}
	request := hostinstallationmanagerdomain.HostProductRemovalRequest{
		SchemaVersion:                     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:                      "host-product-removal-request",
		ID:                                journal.RequestID,
		InstallationID:                    journal.InstallationID,
		ExpectedReleaseID:                 journal.ReleaseID,
		DataDisposition:                   journal.DataDisposition,
		PackageManagerCompletionTransport: journal.PackageManagerCompletionTransport,
		RequestedAt:                       journal.CreatedAt,
	}
	footprint, err := workflow.footprintObserver.ObserveHostInstallationFootprint(context, manifest, installationJournalPath, installationReceiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("observe Host footprint after OS package-manager removal: %w", err)
	}
	decision, retainedStoreIDs, err := hostinstallationmanagerdomain.DecideHostProductRemovalCompletionAfterPackageManager(request, manifest, journal, footprint, removalJournalPath, removalReceiptPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("decide Host product removal completion after OS package-manager: %w", err)
	}
	now := workflow.clock.Now().UTC().Format(time.RFC3339)
	if decision.State != "admitted" {
		issue := decision.Issue
		if issue == nil {
			issue = &hostinstallationmanagerdomain.HostInstallationIssue{Code: "product-removal-completion-not-proven", Message: "the final Host footprint did not prove package-manager removal"}
		}
		return workflow.recordHostProductRemovalFailure(context, request, manifest, removalJournalPath, removalReceiptPath, journal, issue.Code, fmt.Errorf("%s", issue.Message), now)
	}
	completedJournal := journal
	completedJournal.State = hostinstallationmanagerdomain.HostProductRemovalJournalCompleted
	completedJournal.Failure = nil
	completedJournal.UpdatedAt = now
	if err := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, removalJournalPath, completedJournal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("persist completed Host product removal journal after OS package-manager: %w", err)
	}
	receipt := hostProductRemovalReceipt(
		request,
		manifest,
		hostinstallationmanagerdomain.HostProductRemovalReceiptCompleted,
		hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByOSPackageManager,
		nil,
		retainedStoreIDs,
		now,
	)
	if err := workflow.removalReceiptStore.WriteHostProductRemovalReceipt(context, removalReceiptPath, receipt); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("write completed Host product removal receipt after OS package-manager: %w", err)
	}
	return receipt, nil
}

func (workflow *HostInstallationWorkflow) recordHostProductRemovalFailure(
	context context.Context,
	request hostinstallationmanagerdomain.HostProductRemovalRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	journalPath string,
	receiptPath string,
	journal hostinstallationmanagerdomain.HostProductRemovalJournal,
	code string,
	cause error,
	now string,
) (hostinstallationmanagerdomain.HostProductRemovalReceipt, error) {
	issue := &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: cause.Error()}
	failedJournal := journal
	failedJournal.State = hostinstallationmanagerdomain.HostProductRemovalJournalFailed
	failedJournal.Failure = issue
	failedJournal.UpdatedAt = now
	if writeError := workflow.removalJournalStore.WriteHostProductRemovalJournal(context, journalPath, failedJournal); writeError != nil {
		return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("%s: %w; persist Host product removal failure: %v", code, cause, writeError)
	}
	receipt := hostProductRemovalReceipt(request, manifest, hostinstallationmanagerdomain.HostProductRemovalReceiptFailed, "", issue, nil, now)
	if receiptPath != "" {
		if writeError := workflow.removalReceiptStore.WriteHostProductRemovalReceipt(context, receiptPath, receipt); writeError != nil {
			return hostinstallationmanagerdomain.HostProductRemovalReceipt{}, fmt.Errorf("%s: %w; write Host product removal failure receipt: %v", code, cause, writeError)
		}
	}
	return receipt, nil
}

func hostProductRemovalJournal(
	request hostinstallationmanagerdomain.HostProductRemovalRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	state string,
	failure *hostinstallationmanagerdomain.HostInstallationIssue,
	createdAt string,
	updatedAt string,
) hostinstallationmanagerdomain.HostProductRemovalJournal {
	return hostinstallationmanagerdomain.HostProductRemovalJournal{
		SchemaVersion:                     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:                      "host-product-removal-journal",
		ID:                                request.ID + "-journal",
		RequestID:                         request.ID,
		InstallationID:                    manifest.InstallationID,
		ReleaseID:                         manifest.Release.ID,
		DataDisposition:                   request.DataDisposition,
		PackageManagerCompletionTransport: request.PackageManagerCompletionTransport,
		State:                             state,
		Failure:                           failure,
		CreatedAt:                         createdAt,
		UpdatedAt:                         updatedAt,
	}
}

func hostProductRemovalReceipt(
	request hostinstallationmanagerdomain.HostProductRemovalRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	state string,
	packageReceiptRemoval string,
	issue *hostinstallationmanagerdomain.HostInstallationIssue,
	retainedMutableStoreIDs []string,
	observedAt string,
) hostinstallationmanagerdomain.HostProductRemovalReceipt {
	return hostinstallationmanagerdomain.HostProductRemovalReceipt{
		SchemaVersion:           hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:            "host-product-removal-receipt",
		ID:                      request.ID + "-receipt",
		RequestID:               request.ID,
		InstallationID:          manifest.InstallationID,
		ReleaseID:               manifest.Release.ID,
		DataDisposition:         request.DataDisposition,
		State:                   state,
		PackageReceiptRemoval:   packageReceiptRemoval,
		RetainedMutableStoreIDs: retainedMutableStoreIDs,
		Issue:                   issue,
		ObservedAt:              observedAt,
	}
}

func hostProductRemovalReceiptForDecision(
	request hostinstallationmanagerdomain.HostProductRemovalRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	decision hostinstallationmanagerdomain.HostInstallationDecision,
	observedAt string,
) hostinstallationmanagerdomain.HostProductRemovalReceipt {
	state := hostinstallationmanagerdomain.HostProductRemovalReceiptBlocked
	if decision.State == "failed" {
		state = hostinstallationmanagerdomain.HostProductRemovalReceiptFailed
	}
	return hostProductRemovalReceipt(request, manifest, state, "", decision.Issue, nil, observedAt)
}

func (workflow *HostInstallationWorkflow) recordHostInstallationFailure(
	context context.Context,
	request hostinstallationmanagerdomain.HostInstallationRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	journalPath string,
	receiptPath string,
	journal hostinstallationmanagerdomain.HostInstallationJournal,
	code string,
	cause error,
	now string,
) (hostinstallationmanagerdomain.HostInstallationReceipt, error) {
	failedJournal := journal
	failedJournal.State = hostinstallationmanagerdomain.HostInstallationJournalFailed
	failedJournal.Failure = &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: cause.Error()}
	failedJournal.UpdatedAt = now
	if writeError := workflow.journalStore.WriteHostInstallationJournal(context, journalPath, failedJournal); writeError != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("%s: %w; persist Host installation failure: %v", code, cause, writeError)
	}
	receipt := hostInstallationReceipt(request, manifest, hostinstallationmanagerdomain.HostInstallationReceiptFailed, failedJournal.Failure, now)
	if writeError := workflow.receiptStore.WriteHostInstallationReceipt(context, receiptPath, receipt); writeError != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("%s: %w; write Host installation failure receipt: %v", code, cause, writeError)
	}
	return receipt, nil
}

func hostInstallationRequestFromJournal(operation string, journal hostinstallationmanagerdomain.HostInstallationJournal) hostinstallationmanagerdomain.HostInstallationRequest {
	return hostinstallationmanagerdomain.HostInstallationRequest{
		SchemaVersion:     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:      "host-installation-request",
		ID:                journal.RequestID,
		InstallationID:    journal.InstallationID,
		Operation:         operation,
		ExpectedReleaseID: journal.ReleaseID,
		RequestedAt:       journal.UpdatedAt,
	}
}

func hostInstallationReceipt(
	request hostinstallationmanagerdomain.HostInstallationRequest,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	state string,
	issue *hostinstallationmanagerdomain.HostInstallationIssue,
	observedAt string,
) hostinstallationmanagerdomain.HostInstallationReceipt {
	return hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:   "host-installation-receipt",
		ID:             request.ID + "-receipt",
		RequestID:      request.ID,
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          state,
		Issue:          issue,
		ObservedAt:     observedAt,
	}
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
	return hostInstallationReceipt(request, manifest, state, decision.Issue, observedAt)
}

type systemHostInstallationClock struct{}

func (systemHostInstallationClock) Now() time.Time { return time.Now() }

func NewSystemHostInstallationClock() HostInstallationClock { return systemHostInstallationClock{} }
