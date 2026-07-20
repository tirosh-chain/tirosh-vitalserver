package hostplatformstagedreleaseupdateapplication

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

type workflowClock struct{}

func (workflowClock) Now() string { return "2026-07-20T00:00:00Z" }

type archiveInspectorFake struct {
	inspected             InspectedHostPlatformReleaseArchive
	inspectCalls          int
	persisted             bool
	persistedForReleaseID string
}

func (fake *archiveInspectorFake) Inspect(context.Context, hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, string) (InspectedHostPlatformReleaseArchive, error) {
	fake.inspectCalls++
	return fake.inspected, nil
}
func (fake *archiveInspectorFake) Persist(inspected InspectedHostPlatformReleaseArchive, active hostinstallationmanagerdomain.HostProductInstallationManifest, _ hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand) (hostplatformstagedreleaseupdatedomain.CandidateHostRelease, error) {
	fake.persisted, fake.persistedForReleaseID = true, active.Release.ID
	return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{Manifest: inspected.Manifest, CandidateDirectory: "/candidate"}, nil
}
func (*archiveInspectorFake) Remove(InspectedHostPlatformReleaseArchive) error { return nil }

type activeReleaseReaderFake struct {
	active hostplatformstagedreleaseupdatedomain.ActiveHostRelease
}

func (fake activeReleaseReaderFake) ReadActiveHostRelease(context.Context, string) (hostplatformstagedreleaseupdatedomain.ActiveHostRelease, error) {
	return fake.active, nil
}

type operationStoreFake struct {
	operation  *hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation
	writes     []hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation
	recoveries map[string]hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt
}

type transactionRecorderFake struct {
	journals []hostinstallationmanagerdomain.HostInstallationJournal
	receipts []hostinstallationmanagerdomain.HostInstallationReceipt
	err      error
}

func (fake *transactionRecorderFake) RecordHostInstallationTransaction(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, journal hostinstallationmanagerdomain.HostInstallationJournal, receipt hostinstallationmanagerdomain.HostInstallationReceipt) error {
	fake.journals = append(fake.journals, journal)
	fake.receipts = append(fake.receipts, receipt)
	return fake.err
}

func (fake *operationStoreFake) ReadHostPlatformStagedReleaseUpdateOperation(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, string) (hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation, error) {
	if fake.operation == nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, os.ErrNotExist
	}
	return *fake.operation, nil
}
func (fake *operationStoreFake) WriteHostPlatformStagedReleaseUpdateOperation(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, operation hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation) error {
	fake.writes = append(fake.writes, operation)
	fake.operation = &operation
	return nil
}
func (fake *operationStoreFake) ReadHostPlatformStagedReleaseRecoveryReceipt(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, operationID, recoveryID string) (hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt, error) {
	if fake.recoveries == nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, os.ErrNotExist
	}
	receipt, found := fake.recoveries[operationID+"/"+recoveryID]
	if !found {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, os.ErrNotExist
	}
	return receipt, nil
}
func (fake *operationStoreFake) WriteHostPlatformStagedReleaseRecoveryReceipt(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, receipt hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt) error {
	if fake.recoveries == nil {
		fake.recoveries = map[string]hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}
	}
	fake.recoveries[receipt.OperationID+"/"+receipt.RecoveryID] = receipt
	return nil
}

type quiescerFake struct{ calls int }

func (fake *quiescerFake) QuiesceHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.calls++
	return nil
}

type publisherFake struct{ calls int }

func (fake *publisherFake) PublishStagedHostProductRelease(context.Context, hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, hostplatformstagedreleaseupdatedomain.CandidateHostRelease) error {
	fake.calls++
	return nil
}

type activatorFake struct{ calls int }

func (fake *activatorFake) ActivateStagedHostProductRelease(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.calls++
	return nil
}

type reconcilerFake struct{ calls int }

func (fake *reconcilerFake) ReconcileHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.calls++
	return nil
}

func TestWorkflowPersistsSuccessOnlyAfterAllHostEffects(t *testing.T) {
	target := workflowManifest("release-030")
	active := workflowManifest("release-020")
	archive := &archiveInspectorFake{inspected: InspectedHostPlatformReleaseArchive{Manifest: target, TemporaryDirectory: "/temporary", ReleaseDirectory: "/temporary/release"}}
	store := &operationStoreFake{}
	transactionRecorder := &transactionRecorderFake{}
	quiescer, publisher, activator, reconciler := &quiescerFake{}, &publisherFake{}, &activatorFake{}, &reconcilerFake{}
	workflow, err := NewWorkflow(archive, activeReleaseReaderFake{active: hostplatformstagedreleaseupdatedomain.ActiveHostRelease{Manifest: active}}, store, transactionRecorder, quiescer, publisher, activator, reconciler, workflowClock{})
	if err != nil {
		t.Fatal(err)
	}
	operation, err := workflow.ExecuteHostPlatformStagedReleaseUpdate(context.Background(), workflowCommand(), "/current/installation-manifest.json", "/updates/release.tar.gz")
	if err != nil || operation.State != "succeeded" || !archive.persisted || archive.persistedForReleaseID != active.Release.ID || quiescer.calls != 1 || publisher.calls != 1 || activator.calls != 1 || reconciler.calls != 1 || len(transactionRecorder.journals) != 1 || len(transactionRecorder.receipts) != 1 || transactionRecorder.journals[0].ReleaseID != target.Release.ID || transactionRecorder.journals[0].State != hostinstallationmanagerdomain.HostInstallationJournalCompleted || transactionRecorder.receipts[0].State != hostinstallationmanagerdomain.HostInstallationReceiptCompleted {
		t.Fatalf("operation=%+v error=%v calls=%d/%d/%d/%d", operation, err, quiescer.calls, publisher.calls, activator.calls, reconciler.calls)
	}
}

func TestWorkflowFailsWhenItCannotRecordCurrentC50TransactionAfterActivation(t *testing.T) {
	target := workflowManifest("release-030")
	active := workflowManifest("release-020")
	archive := &archiveInspectorFake{inspected: InspectedHostPlatformReleaseArchive{Manifest: target}}
	store := &operationStoreFake{}
	workflow, err := NewWorkflow(archive, activeReleaseReaderFake{active: hostplatformstagedreleaseupdatedomain.ActiveHostRelease{Manifest: active}}, store, &transactionRecorderFake{err: errors.New("disk full")}, &quiescerFake{}, &publisherFake{}, &activatorFake{}, &reconcilerFake{}, workflowClock{})
	if err != nil {
		t.Fatal(err)
	}
	operation, err := workflow.ExecuteHostPlatformStagedReleaseUpdate(context.Background(), workflowCommand(), "/current/installation-manifest.json", "/updates/release.tar.gz")
	if err != nil || operation.State != hostplatformstagedreleaseupdatedomain.StateFailed || operation.Issue == nil || operation.Issue.Code != "host-platform-installation-transaction-record-failed" {
		t.Fatalf("operation=%+v error=%v", operation, err)
	}
}
func TestWorkflowDoesNotReplayIncompleteOperation(t *testing.T) {
	target := workflowManifest("release-030")
	command := workflowCommand()
	prior, err := hostplatformstagedreleaseupdatedomain.NewOperation(command, "activating", nil, "2026-07-20T00:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	archive := &archiveInspectorFake{inspected: InspectedHostPlatformReleaseArchive{Manifest: target}}
	store := &operationStoreFake{operation: &prior}
	quiescer := &quiescerFake{}
	workflow, err := NewWorkflow(archive, activeReleaseReaderFake{}, store, &transactionRecorderFake{}, quiescer, &publisherFake{}, &activatorFake{}, &reconcilerFake{}, workflowClock{})
	if err != nil {
		t.Fatal(err)
	}
	operation, err := workflow.ExecuteHostPlatformStagedReleaseUpdate(context.Background(), command, "/current/installation-manifest.json", "/updates/release.tar.gz")
	if err != nil || operation.State != "activating" || archive.inspectCalls != 0 || archive.persisted || quiescer.calls != 0 {
		t.Fatalf("operation=%+v error=%v", operation, err)
	}
}

func TestRecoveryReconcilesExplicitlyObservedCurrentReleaseAfterActivationFailure(t *testing.T) {
	active := workflowManifest("release-030")
	command := workflowCommand()
	failed := hostplatformstagedreleaseupdatedomain.Failure(command, hostplatformstagedreleaseupdatedomain.StateFailed, hostplatformstagedreleaseupdatedomain.StateActivating, "host-platform-release-activation-failed", "activation completion is unknown", "host-installation-manager", "2026-07-20T00:00:00Z")
	store := &operationStoreFake{operation: &failed}
	reconciler := &reconcilerFake{}
	transactionRecorder := &transactionRecorderFake{}
	workflow, err := NewWorkflow(&archiveInspectorFake{}, activeReleaseReaderFake{active: hostplatformstagedreleaseupdatedomain.ActiveHostRelease{Manifest: active}}, store, transactionRecorder, &quiescerFake{}, &publisherFake{}, &activatorFake{}, reconciler, workflowClock{})
	if err != nil {
		t.Fatal(err)
	}
	recovery := hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryCommand{SchemaVersion: "v1", RecoveryID: "update-030-recovery-001", OperationID: command.OperationID, Action: hostplatformstagedreleaseupdatedomain.RecoveryActionReconcileCurrentRelease, RequestedAt: "2026-07-20T00:00:00Z"}
	receipt, err := workflow.RecoverHostPlatformStagedReleaseUpdate(context.Background(), recovery, "/current/installation-manifest.json")
	if err != nil || receipt.State != hostplatformstagedreleaseupdatedomain.RecoveryStateSucceeded || receipt.ActiveReleaseID != active.Release.ID || reconciler.calls != 1 || len(transactionRecorder.journals) != 1 || transactionRecorder.journals[0].ReleaseID != active.Release.ID || transactionRecorder.journals[0].State != hostinstallationmanagerdomain.HostInstallationJournalRecovered {
		t.Fatalf("receipt=%+v error=%v reconcileCalls=%d", receipt, err, reconciler.calls)
	}
}

func TestRecoveryBlocksBeforeServiceEffectWhenPriorOperationDidNotReachServiceBoundary(t *testing.T) {
	active := workflowManifest("release-020")
	command := workflowCommand()
	failed := hostplatformstagedreleaseupdatedomain.Failure(command, hostplatformstagedreleaseupdatedomain.StateFailed, hostplatformstagedreleaseupdatedomain.StateReceived, "host-platform-release-archive-invalid", "archive invalid", "host-update-staging", "2026-07-20T00:00:00Z")
	store := &operationStoreFake{operation: &failed}
	reconciler := &reconcilerFake{}
	workflow, err := NewWorkflow(&archiveInspectorFake{}, activeReleaseReaderFake{active: hostplatformstagedreleaseupdatedomain.ActiveHostRelease{Manifest: active}}, store, &transactionRecorderFake{}, &quiescerFake{}, &publisherFake{}, &activatorFake{}, reconciler, workflowClock{})
	if err != nil {
		t.Fatal(err)
	}
	recovery := hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryCommand{SchemaVersion: "v1", RecoveryID: "update-030-recovery-001", OperationID: command.OperationID, Action: hostplatformstagedreleaseupdatedomain.RecoveryActionReconcileCurrentRelease, RequestedAt: "2026-07-20T00:00:00Z"}
	receipt, err := workflow.RecoverHostPlatformStagedReleaseUpdate(context.Background(), recovery, "/current/installation-manifest.json")
	if err != nil || receipt.State != hostplatformstagedreleaseupdatedomain.RecoveryStateBlocked || receipt.Issue == nil || receipt.Issue.Code != "recovery-not-required" || reconciler.calls != 0 {
		t.Fatalf("receipt=%+v error=%v reconcileCalls=%d", receipt, err, reconciler.calls)
	}
}

func workflowCommand() hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand {
	return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand{SchemaVersion: "v1", OperationID: "update-030-host-platform-apply", UpdateID: "update-030", Operation: "apply", Transition: hostplatformstagedreleaseupdatedomain.ReleaseTransition{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"}, Artifact: hostplatformstagedreleaseupdatedomain.ArchiveArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 42, MediaType: hostplatformstagedreleaseupdatedomain.HostPlatformReleaseArchiveMedia}, RequestedAt: "2026-07-20T00:00:00Z"}
}
func workflowManifest(id string) hostinstallationmanagerdomain.HostProductInstallationManifest {
	return hostinstallationmanagerdomain.HostProductInstallationManifest{SchemaVersion: "v1", InstallationID: "installation-001", Platform: "macos", Release: hostinstallationmanagerdomain.HostProductRelease{ID: id, ProductVersion: "0.3.0", RuntimeVersion: "0.3.0"}, Package: hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.3.0"}, ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{ReleaseCatalogPath: "/Library/Application Support/VitalServerRuntimePlatform/releases", ReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/" + id, ManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/" + id + "/installation-manifest.json", Entries: []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Executable: true}}}, Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/" + id}, OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json", BootstrapConfigurationSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}, RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}, {Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}, {Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist", DefinitionSHA256: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}}, MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{{ID: hostinstallationmanagerdomain.HostInstallationTransactionStoreID, Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"}}}
}
