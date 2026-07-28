package hostagentapplication_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hoststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type fakeUpdateBootstrapper struct {
	clock        hostagentapplication.HostAgentClock
	state        string
	calls        int
	handoffCalls int
	handoffIssue *hostagentdomain.Issue
}

func (bootstrapper *fakeUpdateBootstrapper) Stage(_ context.Context, journal hostagentdomain.HostUpdateJournal, _ hostagentdomain.UpdateBootstrapEnvelope) hostagentdomain.UpdateBootstrapReceipt {
	bootstrapper.calls++
	receipt := hostagentdomain.UpdateBootstrapReceipt{
		SchemaVersion:       hostagentdomain.SchemaVersion,
		UpdateID:            journal.ID,
		RequestID:           journal.RequestID,
		BootstrapEnvelopeID: journal.BootstrapEnvelopeID,
		NextUpdaterSHA256:   journal.NextUpdaterSHA256,
		State:               bootstrapper.state,
		ObservedAt:          hostagentdomain.Timestamp(bootstrapper.clock.Now()),
	}
	if bootstrapper.state == "failed" || bootstrapper.state == "unavailable" {
		receipt.Issue = &hostagentdomain.Issue{Code: "test-bootstrap-" + bootstrapper.state, Dependency: "test-bootstrapper"}
	}
	return receipt
}

func (bootstrapper *fakeUpdateBootstrapper) RequestHandoff(context.Context, hostagentdomain.HostUpdateJournal) *hostagentdomain.Issue {
	bootstrapper.handoffCalls++
	return bootstrapper.handoffIssue
}

func updateSHA(character string) string { return strings.Repeat(character, 64) }

func updateCommand(requestID string, revision int) hostagentdomain.HostUpdateCommand {
	return hostagentdomain.HostUpdateCommand{
		SchemaVersion:                "v1",
		RequestID:                    requestID,
		InstallationID:               "host-installation",
		ExpectedInstallationRevision: revision,
		BundleReferenceID:            "offline-bundle",
		BootstrapEnvelope: hostagentdomain.UpdateBootstrapEnvelope{
			SchemaVersion:       "v1",
			ID:                  "release-bootstrap-1",
			ProductID:           "vitalserver-runtime-platform",
			Target:              hostagentdomain.UpdateTarget{Platform: "macos", Architecture: "arm64"},
			TargetRelease:       hostagentdomain.Release{ProductVersion: "0.2.0", RuntimeVersion: "0.2.0"},
			LayerOrder:          []string{hostagentdomain.UpdateLayerGuestRuntime, hostagentdomain.UpdateLayerContainer, hostagentdomain.UpdateLayerHostPlatform},
			NextUpdaterArtifact: hostagentdomain.UpdateArtifact{ID: "host-updater", RelativePath: "payload/host-updater", SHA256: updateSHA("a"), SizeBytes: 42, MediaType: "application/octet-stream"},
			Specification:       hostagentdomain.UpdateArtifact{ID: "update-spec", RelativePath: "payload/update-spec.json", SHA256: updateSHA("b"), SizeBytes: 73, MediaType: "application/json"},
			Signature:           hostagentdomain.UpdateSignature{Algorithm: "ed25519", KeyID: "release-key-1", SignedSHA256: updateSHA("c"), Value: "test-signature"},
			IssuedAt:            "2026-07-17T00:00:00Z",
		},
	}
}

func newUpdateService(t *testing.T, bootstrapper *fakeUpdateBootstrapper) (*hostagentapplication.HostUpdateApplicationService, *hoststatesqliterepository.HostAgentStateSQLiteRepository) {
	t.Helper()
	repository := configuredRepository(t)
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{}}
	guest := &fakeGuestControl{}
	_ = newServiceWithRepository(t, repository, provider, guest)
	service, err := hostagentapplication.NewHostUpdateApplicationService(repository, bootstrapper, fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}, &sequentialIdentifiers{})
	if err != nil {
		t.Fatalf("new update service: %v", err)
	}
	return service, repository
}

func successReport(journal hostagentdomain.HostUpdateJournal) hostagentdomain.UpdateExecutionReport {
	evidence := make([]hostagentdomain.UpdateLayerEvidence, 0, len(journal.LayerOrder))
	for index, layer := range journal.LayerOrder {
		evidence = append(evidence, hostagentdomain.UpdateLayerEvidence{
			Layer:          layer,
			State:          "succeeded",
			ArtifactSHA256: updateSHA(string(rune('d' + index))),
			ObservedAt:     "2026-07-17T00:01:00Z",
			Evidence:       hostagentdomain.EvidenceReference{Kind: "update-layer-proof", ID: "proof-" + layer},
		})
	}
	return hostagentdomain.UpdateExecutionReport{
		SchemaVersion:             "v1",
		UpdateID:                  journal.ID,
		RequestID:                 journal.RequestID,
		BootstrapEnvelopeID:       journal.BootstrapEnvelopeID,
		UpdateSpecificationSHA256: journal.UpdateSpecificationSHA256,
		State:                     "succeeded",
		StartedAt:                 "2026-07-17T00:00:30Z",
		FinishedAt:                "2026-07-17T00:01:00Z",
		LayerEvidence:             evidence,
		Rollback:                  hostagentdomain.UpdateRollbackEvidence{State: "not-required", ObservedAt: "2026-07-17T00:01:00Z"},
	}
}

func TestUpdateStagesExactlyOnceAndOnlyNextUpdaterCanSettleIt(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, repository := newUpdateService(t, bootstrapper)
	command := updateCommand("update-request-1", 1)

	first, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), command)
	if rejection != nil || admissionFailure != nil || first.Operation.State != "running" || first.Journal.State != "handoff-pending" {
		t.Fatalf("first update outcome=%+v rejection=%+v admissionFailure=%+v", first, rejection, admissionFailure)
	}
	if bootstrapper.calls != 1 || bootstrapper.handoffCalls != 1 || first.Journal.JournalRevision != 3 {
		t.Fatalf("bootstrap calls=%d handoffs=%d journal=%+v", bootstrapper.calls, bootstrapper.handoffCalls, first.Journal)
	}

	replayed, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), command)
	if rejection != nil || admissionFailure != nil || replayed.Journal.ID != first.Journal.ID || bootstrapper.calls != 1 || bootstrapper.handoffCalls != 1 {
		t.Fatalf("replayed update outcome=%+v rejection=%+v admissionFailure=%+v calls=%d handoffs=%d", replayed, rejection, admissionFailure, bootstrapper.calls, bootstrapper.handoffCalls)
	}

	report := successReport(first.Journal)
	completed, rejection, admissionFailure := service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{SchemaVersion: "v1", UpdateID: first.Journal.ID, ExpectedJournalRevision: first.Journal.JournalRevision, Report: report})
	if rejection != nil || admissionFailure != nil || completed.Operation.State != "succeeded" || completed.Journal.State != "succeeded" {
		t.Fatalf("completed update outcome=%+v rejection=%+v admissionFailure=%+v", completed, rejection, admissionFailure)
	}
	installation, err := repository.ReadHostPlatformInstallation(context.Background())
	if err != nil || installation.ResourceRevision != 2 || installation.Release.ProductVersion != "0.2.0" || installation.Release.RuntimeVersion != "0.2.0" {
		t.Fatalf("installation after update=%+v err=%v", installation, err)
	}

	replayedCompletion, rejection, admissionFailure := service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{SchemaVersion: "v1", UpdateID: first.Journal.ID, ExpectedJournalRevision: first.Journal.JournalRevision, Report: report})
	if rejection != nil || admissionFailure != nil || replayedCompletion.Operation.ID != completed.Operation.ID || replayedCompletion.Journal.JournalRevision != completed.Journal.JournalRevision {
		t.Fatalf("replayed completion=%+v rejection=%+v admissionFailure=%+v", replayedCompletion, rejection, admissionFailure)
	}
}

func TestUpdateRejectsSecondRequestWhileDurableUpdateOwnsInstallation(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, _ := newUpdateService(t, bootstrapper)

	first, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-owner", 1))
	if rejection != nil || admissionFailure != nil || first.Journal.State != "handoff-pending" {
		t.Fatalf("first update outcome=%+v rejection=%+v admissionFailure=%+v", first, rejection, admissionFailure)
	}
	second, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-conflict", 1))
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "host-update-operation-active" {
		t.Fatalf("second update outcome=%+v rejection=%+v admissionFailure=%+v", second, rejection, admissionFailure)
	}
	if bootstrapper.calls != 1 || bootstrapper.handoffCalls != 1 {
		t.Fatalf("conflicting update reached effects: stage=%d handoff=%d", bootstrapper.calls, bootstrapper.handoffCalls)
	}
}

func TestUpdateOwnershipReadDistinguishesIdleActiveAndTerminal(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, _ := newUpdateService(t, bootstrapper)

	idle := service.ReadHostUpdateOperationOwnership(context.Background())
	idleOwnership, ok := idle.Value.(hostagentdomain.HostUpdateOperationOwnership)
	if idle.State != "available" || !ok || idleOwnership.State != "idle" || idleOwnership.InstallationID != "host-installation" || idleOwnership.InstallationRevision != 1 {
		t.Fatalf("idle ownership read=%+v value=%+v", idle, idle.Value)
	}
	admitted, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-ownership-read", 1))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("admit update rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
	active := service.ReadHostUpdateOperationOwnership(context.Background())
	activeOwnership, ok := active.Value.(hostagentdomain.HostUpdateOperationOwnership)
	if active.State != "available" || !ok || activeOwnership.State != "active" || activeOwnership.UpdateID != admitted.Journal.ID || activeOwnership.OperationID != admitted.Operation.ID || activeOwnership.JournalRevision != admitted.Journal.JournalRevision {
		t.Fatalf("active ownership read=%+v value=%+v", active, active.Value)
	}
	report := successReport(admitted.Journal)
	completed, rejection, admissionFailure := service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{
		SchemaVersion:           "v1",
		UpdateID:                admitted.Journal.ID,
		ExpectedJournalRevision: admitted.Journal.JournalRevision,
		Report:                  report,
	})
	if rejection != nil || admissionFailure != nil || completed.Journal.State != "succeeded" {
		t.Fatalf("complete update outcome=%+v rejection=%+v admissionFailure=%+v", completed, rejection, admissionFailure)
	}
	terminal := service.ReadHostUpdateOperationOwnership(context.Background())
	terminalOwnership, ok := terminal.Value.(hostagentdomain.HostUpdateOperationOwnership)
	if terminal.State != "available" || !ok || terminalOwnership.State != "idle" || terminalOwnership.InstallationRevision != 2 {
		t.Fatalf("terminal ownership read=%+v value=%+v", terminal, terminal.Value)
	}
}

func TestUpdateInterruptionRequestKeepsOwnershipActiveAndIsIdempotent(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, _ := newUpdateService(t, bootstrapper)
	admitted, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-interrupt-owner", 1))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("admit update rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
	command := hostagentdomain.HostUpdateInterruptionRequest{
		SchemaVersion:                "v1",
		RequestID:                    "interrupt-request-1",
		UpdateID:                     admitted.Journal.ID,
		InstallationID:               admitted.Journal.InstallationID,
		ExpectedInstallationRevision: admitted.Journal.ExpectedInstallationRevision,
		ExpectedJournalRevision:      admitted.Journal.JournalRevision,
		Reason:                       hostagentdomain.Issue{Code: "host-installation-removal-requested", Message: "Host product removal requires the active update to stop"},
	}
	requested, rejection, admissionFailure := service.RequestHostUpdateInterruption(context.Background(), command)
	if rejection != nil || admissionFailure != nil || requested.Journal.State != "handoff-pending" || requested.Journal.Interruption == nil || requested.Journal.Interruption.InterruptedState != "handoff-pending" {
		t.Fatalf("request interruption outcome=%+v rejection=%+v admissionFailure=%+v", requested, rejection, admissionFailure)
	}
	replayed, rejection, admissionFailure := service.RequestHostUpdateInterruption(context.Background(), command)
	if rejection != nil || admissionFailure != nil || replayed.Journal.JournalRevision != requested.Journal.JournalRevision {
		t.Fatalf("replay interruption outcome=%+v rejection=%+v admissionFailure=%+v", replayed, rejection, admissionFailure)
	}
	ownershipRead := service.ReadHostUpdateOperationOwnership(context.Background())
	ownership, ok := ownershipRead.Value.(hostagentdomain.HostUpdateOperationOwnership)
	if ownershipRead.State != "available" || !ok || ownership.State != "active" || ownership.UpdateState != "handoff-pending" || !ownership.InterruptionRequested {
		t.Fatalf("interruption ownership read=%+v value=%+v", ownershipRead, ownershipRead.Value)
	}
	second, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-during-cancellation", 1))
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "host-update-operation-active" || second.Journal.ID != "" {
		t.Fatalf("second update outcome=%+v rejection=%+v admissionFailure=%+v", second, rejection, admissionFailure)
	}
	report := successReport(admitted.Journal)
	completed, rejection, admissionFailure := service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{
		SchemaVersion:           "v1",
		UpdateID:                admitted.Journal.ID,
		ExpectedJournalRevision: admitted.Journal.JournalRevision,
		Report:                  report,
	})
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "update-journal-revision-conflict" || completed.Journal.ID != "" {
		t.Fatalf("stale completion outcome=%+v rejection=%+v admissionFailure=%+v", completed, rejection, admissionFailure)
	}
	completed, rejection, admissionFailure = service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{
		SchemaVersion:           "v1",
		UpdateID:                requested.Journal.ID,
		ExpectedJournalRevision: requested.Journal.JournalRevision,
		Report:                  report,
	})
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "update-interruption-pending" || completed.Journal.ID != "" {
		t.Fatalf("completion during interruption outcome=%+v rejection=%+v admissionFailure=%+v", completed, rejection, admissionFailure)
	}
	confirmation := hostagentdomain.HostUpdateInterruptionConfirmation{
		SchemaVersion:                "v1",
		RequestID:                    "interruption-confirmation-1",
		UpdateID:                     requested.Journal.ID,
		InstallationID:               requested.Journal.InstallationID,
		ExpectedInstallationRevision: requested.Journal.ExpectedInstallationRevision,
		ExpectedJournalRevision:      requested.Journal.JournalRevision,
		InterruptionRequestID:        requested.Journal.Interruption.RequestID,
		TerminationEvidence:          hostagentdomain.EvidenceReference{Kind: "host-update-process-termination", ID: "dispatch-attempt-1"},
		Outcome:                      hostagentdomain.Issue{Code: "staged-next-updater-terminated", Message: "the supervisor observed child process termination"},
		ObservedAt:                   "2026-07-17T00:00:10Z",
	}
	confirmed, rejection, admissionFailure := service.ConfirmHostUpdateInterruption(context.Background(), confirmation)
	if rejection != nil || admissionFailure != nil || confirmed.Operation.State != "interrupted" || confirmed.Journal.State != "interrupted" || hostagentdomain.ValidateHostUpdateJournal(confirmed.Journal) != nil {
		t.Fatalf("confirmed interruption outcome=%+v rejection=%+v admissionFailure=%+v validation=%+v", confirmed, rejection, admissionFailure, hostagentdomain.ValidateHostUpdateJournal(confirmed.Journal))
	}
	replayedConfirmation, rejection, admissionFailure := service.ConfirmHostUpdateInterruption(context.Background(), confirmation)
	if rejection != nil || admissionFailure != nil || replayedConfirmation.Journal.JournalRevision != confirmed.Journal.JournalRevision {
		t.Fatalf("replayed confirmation outcome=%+v rejection=%+v admissionFailure=%+v", replayedConfirmation, rejection, admissionFailure)
	}
	terminalOwnership := service.ReadHostUpdateOperationOwnership(context.Background())
	terminal, ok := terminalOwnership.Value.(hostagentdomain.HostUpdateOperationOwnership)
	if terminalOwnership.State != "available" || !ok || terminal.State != "idle" {
		t.Fatalf("terminal interruption ownership=%+v value=%+v", terminalOwnership, terminalOwnership.Value)
	}
}

func TestTerminalUpdateReleasesAdmissionForNextInstallationRevision(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, _ := newUpdateService(t, bootstrapper)
	first, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-first-terminal", 1))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("first update rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
	report := successReport(first.Journal)
	completed, rejection, admissionFailure := service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{
		SchemaVersion:           "v1",
		UpdateID:                first.Journal.ID,
		ExpectedJournalRevision: first.Journal.JournalRevision,
		Report:                  report,
	})
	if rejection != nil || admissionFailure != nil || completed.Journal.State != "succeeded" {
		t.Fatalf("complete first update outcome=%+v rejection=%+v admissionFailure=%+v", completed, rejection, admissionFailure)
	}
	second, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-next-revision", 2))
	if rejection != nil || admissionFailure != nil || second.Journal.State != "handoff-pending" {
		t.Fatalf("next-revision update outcome=%+v rejection=%+v admissionFailure=%+v", second, rejection, admissionFailure)
	}
}

func TestSQLiteRejectsSecondActiveUpdateOwnerAtomically(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, repository := newUpdateService(t, bootstrapper)
	first, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-durable-owner", 1))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("first update rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}

	command := updateCommand("update-request-direct-conflict", 1)
	digest, err := hostagentdomain.HostUpdateCommandDigest(command)
	if err != nil {
		t.Fatalf("digest conflicting command: %v", err)
	}
	at := hostagentdomain.Timestamp(clock.Now())
	operation := hostagentdomain.NewHostUpdateOperation("host-update-operation-direct-conflict", command, at, digest)
	operation, err = hostagentdomain.TransitionOperation(operation, "accepted", at, nil)
	if err == nil {
		operation, err = hostagentdomain.TransitionOperation(operation, "running", at, nil)
	}
	if err != nil {
		t.Fatalf("prepare conflicting operation: %v", err)
	}
	journal := hostagentdomain.NewHostUpdateJournal("host-update-direct-conflict", operation, command, at)
	if err := repository.PersistNewHostUpdate(context.Background(), operation, journal); !errors.Is(err, hostagentapplication.ErrHostAgentOwnedResourceConflict) {
		t.Fatalf("second active owner write error=%v first=%+v", err, first.Journal)
	}
}

func TestUpdateBootstrapUnavailableIsExplicitTerminalFailure(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "unavailable"}
	service, repository := newUpdateService(t, bootstrapper)
	outcome, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-unavailable", 1))
	if rejection != nil || admissionFailure != nil || outcome.Operation.State != "failed" || outcome.Journal.State != "failed" || outcome.Journal.Failure == nil || outcome.Journal.Failure.Code != "test-bootstrap-unavailable" {
		t.Fatalf("unavailable update outcome=%+v rejection=%+v admissionFailure=%+v", outcome, rejection, admissionFailure)
	}
	if bootstrapper.handoffCalls != 0 {
		t.Fatalf("Host requested handoff after unavailable bootstrap")
	}
	installation, err := repository.ReadHostPlatformInstallation(context.Background())
	if err != nil || installation.ResourceRevision != 1 || installation.Release.ProductVersion != "test" {
		t.Fatalf("failed update changed installation=%+v err=%v", installation, err)
	}
}

func TestUpdateRejectsInvalidBootstrapBeforeDurableAdmissionOrStage(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, repository := newUpdateService(t, bootstrapper)
	command := updateCommand("update-request-invalid-bootstrap", 1)
	command.BootstrapEnvelope.Signature.Value = ""
	outcome, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), command)
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "invalid-update-bootstrap-envelope" || bootstrapper.calls != 0 || bootstrapper.handoffCalls != 0 {
		t.Fatalf("invalid bootstrap outcome=%+v rejection=%+v admissionFailure=%+v stageCalls=%d handoffCalls=%d", outcome, rejection, admissionFailure, bootstrapper.calls, bootstrapper.handoffCalls)
	}
	if _, err := repository.ReadHostUpdateJournalByRequestID(context.Background(), command.RequestID); !errors.Is(err, hostagentapplication.ErrHostAgentOwnedResourceNotFound) {
		t.Fatalf("invalid bootstrap unexpectedly admitted a journal: %v", err)
	}
}

func TestUpdateRecoveryReissuesOnlyDurablyPersistedHandoff(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	initialBootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, repository := newUpdateService(t, initialBootstrapper)
	admitted, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-recovery", 1))
	if rejection != nil || admissionFailure != nil || admitted.Journal.State != "handoff-pending" || initialBootstrapper.handoffCalls != 1 {
		t.Fatalf("admitted update=%+v rejection=%+v admissionFailure=%+v handoffs=%d", admitted, rejection, admissionFailure, initialBootstrapper.handoffCalls)
	}

	// A new service instance models the Host process after restart.  Recovery
	// reads the durable journal and repeats only its idempotent handoff effect.
	recoveryBootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	restarted, err := hostagentapplication.NewHostUpdateApplicationService(repository, recoveryBootstrapper, clock, &sequentialIdentifiers{})
	if err != nil {
		t.Fatalf("new restarted update service: %v", err)
	}
	if err := restarted.RecoverDurableHostUpdateHandoffs(context.Background()); err != nil {
		t.Fatalf("recover pending update handoff: %v", err)
	}
	journal, err := repository.ReadHostUpdateJournal(context.Background(), admitted.Journal.ID)
	if err != nil || journal.State != "handoff-pending" || journal.JournalRevision != admitted.Journal.JournalRevision || recoveryBootstrapper.calls != 0 || recoveryBootstrapper.handoffCalls != 1 {
		t.Fatalf("recovered journal=%+v err=%v stageCalls=%d handoffCalls=%d", journal, err, recoveryBootstrapper.calls, recoveryBootstrapper.handoffCalls)
	}
}

func TestUpdateJournalRejectsDecodedButMismatchedBootstrapCorrelations(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, _ := newUpdateService(t, bootstrapper)
	admitted, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-corrupt-journal", 1))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("admit update rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
	if issue := hostagentdomain.ValidateHostUpdateJournal(admitted.Journal); issue != nil {
		t.Fatalf("valid journal issue=%+v", issue)
	}
	corrupted := admitted.Journal
	corrupted.NextUpdaterSHA256 = updateSHA("f")
	if issue := hostagentdomain.ValidateHostUpdateJournal(corrupted); issue == nil || issue.Code != "host-update-journal-invalid" {
		t.Fatalf("corrupted journal issue=%+v", issue)
	}
}

func TestUpdateRejectsOutOfOrderNextUpdaterEvidenceAndDoesNotAdvanceRelease(t *testing.T) {
	clock := fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}
	bootstrapper := &fakeUpdateBootstrapper{clock: clock, state: "staged"}
	service, repository := newUpdateService(t, bootstrapper)
	admitted, rejection, admissionFailure := service.ExecuteHostUpdateCommand(context.Background(), updateCommand("update-request-order", 1))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("admitted update rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
	report := successReport(admitted.Journal)
	report.LayerEvidence[0].Layer = hostagentdomain.UpdateLayerContainer
	outcome, rejection, admissionFailure := service.CompleteHostUpdateExecution(context.Background(), hostagentdomain.UpdateCompletionCommand{SchemaVersion: "v1", UpdateID: admitted.Journal.ID, ExpectedJournalRevision: admitted.Journal.JournalRevision, Report: report})
	if rejection != nil || admissionFailure != nil || outcome.Operation.State != "failed" || outcome.Journal.State != "failed" || outcome.Journal.Failure == nil || outcome.Journal.Failure.Code != "update-execution-report-invalid" {
		t.Fatalf("out-of-order completion outcome=%+v rejection=%+v admissionFailure=%+v", outcome, rejection, admissionFailure)
	}
	installation, err := repository.ReadHostPlatformInstallation(context.Background())
	if err != nil || installation.ResourceRevision != 1 || installation.Release.ProductVersion != "test" {
		t.Fatalf("invalid report changed installation=%+v err=%v", installation, err)
	}
}
