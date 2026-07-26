package guestruntimeapplication_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type recordingLabRecorderRunner struct {
	stopError error
	starts    int
	stops     int
}

func (runner *recordingLabRecorderRunner) StartLabVirtualRecorderRun(_ context.Context, _ string, recorderID string, recorderCode string, _ string) (guestruntimedomain.LabRecorderRunnerStartReceipt, error) {
	runner.starts++
	return guestruntimedomain.LabRecorderRunnerStartReceipt{
		RunID:                     "lab-run-" + recorderID,
		RunRevision:               1,
		RecorderGatewayRecorderID: "recorder-" + recorderCode,
		ColdPathCaptureID:         "capture-" + recorderID,
		ArchiveOnTerminalStop:     true,
	}, nil
}

func (runner *recordingLabRecorderRunner) StopLabVirtualRecorderRun(_ context.Context, _ string, runID string, expectedRevision int) (guestruntimedomain.LabRecorderRunnerFinalizationReceipt, error) {
	runner.stops++
	if runner.stopError != nil {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, runner.stopError
	}
	return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{
		RunID:                     runID,
		RunRevision:               expectedRevision + 1,
		RecorderGatewayRecorderID: "recorder-lab-recorder-test-3",
		ColdPathCaptureID:         "capture-lab-recorder-test-3",
		FinalizationReceiptID:     "finalization-lab-recorder-test-3",
	}, nil
}

func newLabLifecycleService(t *testing.T, runner *recordingLabRecorderRunner) *guestruntimeapplication.GuestRuntimeLabApplicationService {
	t.Helper()
	service, err := guestruntimeapplication.NewGuestRuntimeLabApplicationServiceWithRecorderRunner(
		newOperationalRepository(t), runner,
		fixedClock{now: time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC)},
		&sequentialIdentifiers{},
	)
	if err != nil {
		t.Fatalf("new Lab service: %v", err)
	}
	return service
}

func startedSingleRecorder(t *testing.T, service *guestruntimeapplication.GuestRuntimeLabApplicationService) guestruntimedomain.VirtualRecorder {
	t.Helper()
	created, rejection, admissionFailure := service.CreateLabSession(context.Background(), guestruntimedomain.CreateLabSessionCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "create-direct-lifecycle", SessionID: "lab-session-direct", ExpectedSessionRevision: 0, Name: "direct-lifecycle", Scenario: "baseline-monitoring", RecorderCount: 1,
	})
	if rejection != nil || admissionFailure != nil || created.State != "succeeded" {
		t.Fatalf("create operation=%+v rejection=%+v admissionFailure=%+v", created, rejection, admissionFailure)
	}
	session := service.ReadLabSession(context.Background(), "lab-session-direct").Value.(guestruntimedomain.LabSession)
	started, rejection, admissionFailure := service.ExecuteLabResourceCommand(context.Background(), guestruntimedomain.LabResourceCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "start-direct-lifecycle", ResourceType: guestruntimedomain.LabSessionResourceType, ResourceID: session.ID, ExpectedResourceRevision: session.ResourceRevision, Action: "start",
	}, nil)
	if rejection != nil || admissionFailure != nil || started.State != "succeeded" {
		t.Fatalf("start operation=%+v rejection=%+v admissionFailure=%+v", started, rejection, admissionFailure)
	}
	recorders := service.ListLabVirtualRecorders(context.Background()).Value.([]guestruntimedomain.VirtualRecorder)
	if len(recorders) != 1 || recorders[0].ExecutionState != "running" {
		t.Fatalf("running recorders=%+v", recorders)
	}
	return recorders[0]
}

func TestIndividualVirtualRecorderStopPersistsIntentBeforeRunnerAndTerminalArchiveIntentAfterReceipt(t *testing.T) {
	runner := &recordingLabRecorderRunner{}
	service := newLabLifecycleService(t, runner)
	recorder := startedSingleRecorder(t, service)

	operation, rejection, admissionFailure := service.ExecuteLabResourceCommand(context.Background(), guestruntimedomain.LabResourceCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "stop-direct-lifecycle", ResourceType: guestruntimedomain.VirtualRecorderResourceType, ResourceID: recorder.ID, ExpectedResourceRevision: recorder.ResourceRevision, Action: "stop",
	}, nil)
	if rejection != nil || admissionFailure != nil || operation.State != "succeeded" || runner.stops != 1 {
		t.Fatalf("stop operation=%+v rejection=%+v admissionFailure=%+v calls=%d", operation, rejection, admissionFailure, runner.stops)
	}
	stopped := service.ReadLabVirtualRecorder(context.Background(), recorder.ID).Value.(guestruntimedomain.VirtualRecorder)
	if stopped.ExecutionState != "stopped" || stopped.TerminalArchiveIntent == nil || stopped.TerminalArchiveIntent.State != "pending" || stopped.TerminalArchiveIntent.SourceResourceRevision != stopped.ResourceRevision {
		t.Fatalf("stopped recorder=%+v", stopped)
	}
}

func TestIndividualVirtualRecorderStopKeepsStoppingWhenRunnerOutcomeIsUnknown(t *testing.T) {
	runner := &recordingLabRecorderRunner{stopError: errors.New("connection reset after request")}
	service := newLabLifecycleService(t, runner)
	recorder := startedSingleRecorder(t, service)

	operation, rejection, admissionFailure := service.ExecuteLabResourceCommand(context.Background(), guestruntimedomain.LabResourceCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "stop-direct-unknown", ResourceType: guestruntimedomain.VirtualRecorderResourceType, ResourceID: recorder.ID, ExpectedResourceRevision: recorder.ResourceRevision, Action: "stop",
	}, nil)
	if rejection != nil || admissionFailure != nil || operation.State != "running" || runner.stops != 1 {
		t.Fatalf("unknown stop operation=%+v rejection=%+v admissionFailure=%+v calls=%d", operation, rejection, admissionFailure, runner.stops)
	}
	stopping := service.ReadLabVirtualRecorder(context.Background(), recorder.ID).Value.(guestruntimedomain.VirtualRecorder)
	if stopping.ExecutionState != "stopping" || stopping.RecorderGatewayFinalizationReceiptID != "" {
		t.Fatalf("unknown Runner outcome must remain explicit stopping=%+v", stopping)
	}
}
