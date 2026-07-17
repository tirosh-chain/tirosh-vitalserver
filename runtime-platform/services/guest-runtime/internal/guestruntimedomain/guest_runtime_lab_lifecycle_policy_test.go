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
