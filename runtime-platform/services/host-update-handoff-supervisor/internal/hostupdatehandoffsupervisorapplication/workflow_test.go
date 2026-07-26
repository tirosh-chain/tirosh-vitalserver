package hostupdatehandoffsupervisorapplication

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

type fixedClock struct{}

func (fixedClock) Now() time.Time { return time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC) }

type inputReader struct {
	input hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput
	err   error
}

func (reader inputReader) Read(hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration, string) (hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput, error) {
	return reader.input, reader.err
}

type updaterProcess struct {
	submission hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission
	err        error
}

func (process updaterProcess) Dispatch(context.Context, hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput) (hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission, error) {
	return process.submission, process.err
}

func testConfiguration() hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration {
	return hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration{SchemaVersion: "v1", ID: "dispatcher", StagingDirectory: "/staging", HandoffQueueDirectory: "/staging/handoff-queue", ExecutionEvidenceDirectory: "/evidence", LayerEffectReceiptDirectory: "/effects", HostLocalAdministrationDescriptorPath: "/control/host.json", LayerEffectTimeoutMilliseconds: 1000, CompletionTimeoutMilliseconds: 1000, ServicePollIntervalMilliseconds: 100}
}

func testInput() hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput {
	return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{UpdateID: "update-020", InvocationRelativePath: "updates/update-020/invocation.json", InvocationPath: "/staging/updates/update-020/invocation.json", ExpectedHandoffJournalRevision: 3, NextUpdaterPath: "/staging/updates/update-020/payload/host-updater", NextUpdaterSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", ExecutionReportPath: "/evidence/update-020/execution-report.json", LayerEffectReceiptPath: "/effects/update-020", CompletionDescriptorPath: "/control/host.json", LayerEffectTimeoutMilliseconds: 1000, CompletionTimeoutMilliseconds: 1000, ExecutionMode: "execute"}
}

func TestDispatchRecordsCompletionSubmissionWithoutCallingItUpdateSuccess(t *testing.T) {
	workflow, err := NewHostUpdateHandoffSupervisorWorkflow(inputReader{input: testInput()}, updaterProcess{submission: hostupdatehandoffsupervisordomain.StagedNextUpdaterCompletionSubmission{CompletionCommandSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.Dispatch(context.Background(), testConfiguration(), "attempt-020", "/staging/handoff-queue/update-020.json")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != "completion-submitted" || receipt.CompletionCommandSHA256 == "" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestDispatchPreservesUnavailableInputAsUnavailableReceipt(t *testing.T) {
	inputFailure := hostupdatehandoffsupervisordomain.DispatchFailure{State: "unavailable", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "handoff-missing", Message: "queue entry is missing", Dependency: "handoff-queue"}}
	workflow, err := NewHostUpdateHandoffSupervisorWorkflow(inputReader{err: inputFailure}, updaterProcess{}, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.Dispatch(context.Background(), testConfiguration(), "attempt-021", "/staging/handoff-queue/update-021.json")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != "unavailable" || receipt.Issue == nil || receipt.Issue.Code != "handoff-missing" {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestDispatchTurnsUnclassifiedProcessFailureIntoFailedReceipt(t *testing.T) {
	workflow, err := NewHostUpdateHandoffSupervisorWorkflow(inputReader{input: testInput()}, updaterProcess{err: errors.New("process exited")}, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.Dispatch(context.Background(), testConfiguration(), "attempt-022", "/staging/handoff-queue/update-020.json")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != "failed" || receipt.Issue == nil || receipt.Issue.Code != "next-updater-dispatch-failed" {
		t.Fatalf("receipt=%+v", receipt)
	}
}
