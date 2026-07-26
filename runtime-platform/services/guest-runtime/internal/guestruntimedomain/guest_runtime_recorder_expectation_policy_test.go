package guestruntimedomain

import (
	"testing"
	"time"
)

func TestRecorderExpectationPolicyKeepsExpectationSupportAndReportIndependent(t *testing.T) {
	expected := "expected"
	unsupported := "unsupported"
	source := "deployment-profile"
	command := RecorderObservabilityExpectationCommand{
		SchemaVersion: SchemaVersion, RequestID: "expectation-request-1",
		ExpectedResourceRevision: 0, Action: "set", ExpectationState: &expected,
		SupportState: &unsupported, Source: &source, Evidence: map[string]any{"profileId": "legacy-recorder"},
	}
	at := time.Date(2026, 7, 24, 1, 2, 3, 0, time.UTC)
	event, expectation, summary, err := DecideRecorderExpectation("recorder-legacy-1", "expectation-event-1", command, nil, nil, at, at, at)
	if err != nil {
		t.Fatal(err)
	}
	if event.Revision != 1 || expectation.LifecycleState != "active" {
		t.Fatalf("event=%+v expectation=%+v", event, expectation)
	}
	if summary.ExpectationState != "expected" || summary.SupportState != "unsupported" || summary.ReportState != "never-reported" {
		t.Fatalf("summary axes were collapsed: %+v", summary)
	}

	clear := RecorderObservabilityExpectationCommand{
		SchemaVersion: SchemaVersion, RequestID: "expectation-request-2",
		ExpectedResourceRevision: 1, Action: "clear", Evidence: map[string]any{},
	}
	_, cleared, clearedSummary, err := DecideRecorderExpectation("recorder-legacy-1", "expectation-event-2", clear, &expectation, &summary, at, at, at)
	if err != nil {
		t.Fatal(err)
	}
	if cleared.LifecycleState != "cleared" || clearedSummary.ExpectationState != "unset" || clearedSummary.SupportState != "unknown" || clearedSummary.ReportState != "never-reported" {
		t.Fatalf("cleared expectation invented state: expectation=%+v summary=%+v", cleared, clearedSummary)
	}
}

func TestRecorderExpectationPolicyRejectsRevisionConflictAndImplicitClear(t *testing.T) {
	command := RecorderObservabilityExpectationCommand{
		SchemaVersion: SchemaVersion, RequestID: "expectation-request-1",
		ExpectedResourceRevision: 1, Action: "clear", Evidence: map[string]any{"implicit": true},
	}
	if issue := ValidateRecorderObservabilityExpectationCommand("recorder-1", command); issue == nil || issue.Code != "invalid-recorder-expectation-clear-command" {
		t.Fatalf("issue=%+v", issue)
	}
	command.Evidence = map[string]any{}
	_, _, _, err := DecideRecorderExpectation("recorder-1", "expectation-event-1", command, nil, nil, time.Now(), time.Now(), time.Now())
	if err == nil || err.Error() != "recorder-expectation-revision-conflict" {
		t.Fatalf("err=%v", err)
	}
}
