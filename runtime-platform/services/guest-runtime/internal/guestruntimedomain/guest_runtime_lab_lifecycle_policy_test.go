package guestruntimedomain

import "testing"

func TestStopLabSessionTransitionsOnlyLabExecution(t *testing.T) {
	session := LabSession{ID: "lab-session-1", ResourceRevision: 2, State: "running"}
	recorders := []VirtualRecorder{
		{ID: "lab-recorder-1", ResourceRevision: 2, ExecutionState: "running"},
		{ID: "lab-recorder-2", ResourceRevision: 2, ExecutionState: "stopped"},
	}

	nextSession, nextRecorders, issue := StopLabSession(session, recorders, "2026-07-17T00:00:00Z")

	if issue != nil {
		t.Fatalf("stop issue = %+v", issue)
	}
	if nextSession.State != "stopped" || nextSession.ResourceRevision != 3 {
		t.Fatalf("session after stop = %+v", nextSession)
	}
	if nextRecorders[0].ExecutionState != "stopped" || nextRecorders[0].ResourceRevision != 3 {
		t.Fatalf("running recorder after stop = %+v", nextRecorders[0])
	}
	if nextRecorders[1].ExecutionState != "stopped" || nextRecorders[1].ResourceRevision != 2 {
		t.Fatalf("already stopped recorder was rewritten = %+v", nextRecorders[1])
	}
}

func TestDetachIsDistinctFromVisibilityAndDelete(t *testing.T) {
	recorder := VirtualRecorder{
		ID: "lab-recorder-1", ResourceRevision: 3, ExecutionState: "stopped", Visibility: "hidden",
		BedReference: &ResourceReference{ResourceType: LabBedResourceType, ResourceID: "lab-bed-1"},
	}
	bed := LabBed{
		ID: "lab-bed-1", ResourceRevision: 2, AssignmentState: "assigned", Visibility: "visible",
		RecorderReference: &ResourceReference{ResourceType: VirtualRecorderResourceType, ResourceID: "lab-recorder-1"},
	}

	nextRecorder, nextBed, issue := DetachVirtualRecorder(recorder, bed, "2026-07-17T00:00:00Z")

	if issue != nil {
		t.Fatalf("detach issue = %+v", issue)
	}
	if nextRecorder.BedReference != nil || nextRecorder.Visibility != "hidden" {
		t.Fatalf("detach changed the wrong recorder facts: %+v", nextRecorder)
	}
	if nextBed.AssignmentState != "detached" || nextBed.RecorderReference != nil || nextBed.Visibility != "visible" {
		t.Fatalf("detach changed the wrong bed facts: %+v", nextBed)
	}
	command := LabResourceCommand{ResourceType: VirtualRecorderResourceType, ResourceID: nextRecorder.ID, Action: "delete", Cascade: "none"}
	if issue := ValidateLabDelete(command, nil, nil, &nextRecorder); issue != nil {
		t.Fatalf("a detached stopped recorder should be deletable: %+v", issue)
	}
}

func TestSessionRunnerLifecycleRequiresDurableReceiptsBeforeTerminalStates(t *testing.T) {
	at := "2026-07-19T00:00:00Z"
	session := LabSession{ID: "lab-session-1", ResourceRevision: 1, State: "prepared"}
	recorder := VirtualRecorder{ID: "lab-recorder-1", ResourceRevision: 1, RecorderGatewayRecorderCode: "lab-recorder-1", ExecutionState: "ready"}

	startingSession, issue := BeginLabSessionStart(session, []VirtualRecorder{recorder}, at)
	if issue != nil || startingSession.State != "starting" || startingSession.ResourceRevision != 2 {
		t.Fatalf("begin session start = %+v, issue=%+v", startingSession, issue)
	}
	startingRecorder, issue := BeginVirtualRecorderStart(startingSession, recorder, at)
	if issue != nil || startingRecorder.ExecutionState != "starting" || startingRecorder.ResourceRevision != 2 {
		t.Fatalf("begin recorder start = %+v, issue=%+v", startingRecorder, issue)
	}
	if _, issue = CompleteLabSessionStart(startingSession, []VirtualRecorder{startingRecorder}, at); issue == nil || issue.Code != "lab-session-recorder-start-incomplete" {
		t.Fatalf("session start must require a receipt-bearing running recorder, issue=%+v", issue)
	}
	runningRecorder, issue := CompleteVirtualRecorderStart(startingRecorder, LabRecorderRunnerStartReceipt{RunID: "lab-run-1", RunRevision: 1, RecorderGatewayRecorderID: "recorder-lab-recorder-1", ColdPathCaptureID: "capture-1", ArchiveOnTerminalStop: true}, at)
	if issue != nil || runningRecorder.ExecutionState != "running" || runningRecorder.ResourceRevision != 3 {
		t.Fatalf("complete recorder start = %+v, issue=%+v", runningRecorder, issue)
	}
	if runningRecorder.TerminalArchivePolicy != "export-on-stop" {
		t.Fatalf("Runner archive policy was not persisted explicitly: %+v", runningRecorder)
	}
	runningSession, issue := CompleteLabSessionStart(startingSession, []VirtualRecorder{runningRecorder}, at)
	if issue != nil || runningSession.State != "running" || runningSession.ResourceRevision != 3 {
		t.Fatalf("complete session start = %+v, issue=%+v", runningSession, issue)
	}

	stoppingSession, issue := BeginLabSessionStop(runningSession, []VirtualRecorder{runningRecorder}, at)
	if issue != nil || stoppingSession.State != "stopping" || stoppingSession.ResourceRevision != 4 {
		t.Fatalf("begin session stop = %+v, issue=%+v", stoppingSession, issue)
	}
	stoppingRecorder, issue := BeginVirtualRecorderStop(stoppingSession, runningRecorder, at)
	if issue != nil || stoppingRecorder.ExecutionState != "stopping" || stoppingRecorder.ResourceRevision != 4 {
		t.Fatalf("begin recorder stop = %+v, issue=%+v", stoppingRecorder, issue)
	}
	if _, issue = CompleteLabSessionStop(stoppingSession, []VirtualRecorder{stoppingRecorder}, at); issue == nil || issue.Code != "lab-session-recorder-stop-incomplete" {
		t.Fatalf("session stop must require a finalization receipt, issue=%+v", issue)
	}
	stoppedRecorder, issue := CompleteVirtualRecorderStop(stoppingRecorder, LabRecorderRunnerFinalizationReceipt{RunID: "lab-run-1", RunRevision: 2, RecorderGatewayRecorderID: "recorder-lab-recorder-1", ColdPathCaptureID: "capture-1", FinalizationReceiptID: "finalization-1"}, ResourceReference{ResourceType: "operation", ResourceID: "lab-stop-operation-1"}, at)
	if issue != nil || stoppedRecorder.ExecutionState != "stopped" || stoppedRecorder.ResourceRevision != 5 {
		t.Fatalf("complete recorder stop = %+v, issue=%+v", stoppedRecorder, issue)
	}
	if stoppedRecorder.TerminalArchiveIntent == nil || stoppedRecorder.TerminalArchiveIntent.State != "pending" || stoppedRecorder.TerminalArchiveIntent.SourceResourceRevision != stoppedRecorder.ResourceRevision {
		t.Fatalf("terminal archive intent = %+v", stoppedRecorder.TerminalArchiveIntent)
	}
	candidate, issue := TerminalArchiveExportCandidateForRecorder(stoppedRecorder)
	if issue != nil || candidate.ExpectedResourceRevision != stoppedRecorder.ResourceRevision || candidate.ColdPathFinalizationReceiptID != "finalization-1" || candidate.LabOperationReference.ResourceID != "lab-stop-operation-1" {
		t.Fatalf("terminal archive candidate=%+v issue=%+v", candidate, issue)
	}
	dispatched, issue := RecordTerminalArchiveDispatch(stoppedRecorder, candidate.RequestID, "submitted", &ResourceReference{ResourceType: "operation", ResourceID: "archive-operation-1"}, nil, at)
	if issue != nil || dispatched.ResourceRevision != stoppedRecorder.ResourceRevision+1 || dispatched.TerminalArchiveIntent == nil || dispatched.TerminalArchiveIntent.State != "submitted" || dispatched.TerminalArchiveIntent.SourceResourceRevision != stoppedRecorder.ResourceRevision {
		t.Fatalf("terminal archive dispatch=%+v issue=%+v", dispatched, issue)
	}
	unavailable, issue := RecordTerminalArchiveDispatch(stoppedRecorder, candidate.RequestID, "unavailable", nil, &Issue{Code: "archive-store-read-failed", Dependency: "guest-state-store"}, at)
	if issue != nil || unavailable.TerminalArchiveIntent == nil || unavailable.TerminalArchiveIntent.State != "unavailable" {
		t.Fatalf("unavailable terminal archive dispatch=%+v issue=%+v", unavailable, issue)
	}
	stoppedSession, issue := CompleteLabSessionStop(stoppingSession, []VirtualRecorder{stoppedRecorder}, at)
	if issue != nil || stoppedSession.State != "stopped" || stoppedSession.ResourceRevision != 5 {
		t.Fatalf("complete session stop = %+v, issue=%+v", stoppedSession, issue)
	}
}

func TestFailedSessionAllowsExplicitStopOfRunningRecorder(t *testing.T) {
	session := LabSession{ID: "lab-session-1", ResourceRevision: 2, State: "starting"}
	failed, issue := FailLabSessionExecution(session, "2026-07-19T00:00:00Z")
	if issue != nil || failed.State != "failed" {
		t.Fatalf("fail session = %+v, issue=%+v", failed, issue)
	}
	recorder := VirtualRecorder{ID: "lab-recorder-1", RecorderGatewayRecorderCode: "lab-recorder-1", RecorderGatewayRecorderID: "recorder-lab-recorder-1", LabRecorderRunnerRunID: "lab-run-1", LabRecorderRunnerRunRevision: 1, RecorderGatewayColdPathCaptureID: "capture-1", ResourceRevision: 3, ExecutionState: "running"}
	stopping, issue := BeginVirtualRecorderStop(failed, recorder, "2026-07-19T00:00:00Z")
	if issue != nil || stopping.ExecutionState != "stopping" {
		t.Fatalf("failed session must permit explicit recorder stop, recorder=%+v issue=%+v", stopping, issue)
	}
}
