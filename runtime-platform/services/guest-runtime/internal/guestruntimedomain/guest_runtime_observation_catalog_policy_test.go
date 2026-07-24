package guestruntimedomain

import (
	"strings"
	"testing"
	"time"
)

func TestCatalogSourceKeyIsPostgreSQLTextSafeAndTupleUnambiguous(t *testing.T) {
	first := RecorderObservationEnvelope{RecorderID: "recorder-a", BootID: "boot-a", Sequence: 12}
	second := RecorderObservationEnvelope{RecorderID: "recorder", BootID: "a-boot-a", Sequence: 12}

	firstKey := CatalogSourceKey(first)
	secondKey := CatalogSourceKey(second)
	if strings.ContainsRune(firstKey, '\x00') {
		t.Fatalf("Catalog source key contains a PostgreSQL-invalid NUL: %q", firstKey)
	}
	if firstKey == secondKey {
		t.Fatalf("distinct Recorder source identity tuples produced the same key: %q", firstKey)
	}
	if firstKey != CatalogSourceKey(first) {
		t.Fatalf("Catalog source key is not deterministic")
	}
}

func TestAcceptedObservationProjectsIndependentCurrentStateAxes(t *testing.T) {
	version := "1.2.3"
	command := CatalogObservationIngestCommand{
		SchemaVersion: SchemaVersion,
		RequestID:     "projection-request",
		ObservationID: "projection-observation",
		Envelope: RecorderObservationEnvelope{
			SchemaVersion:   SchemaVersion,
			ProtocolVersion: "v1",
			RecorderID:      "projection-recorder",
			BootID:          "projection-boot",
			Sequence:        7,
			OccurredAt:      "2026-07-24T01:02:03Z",
			Time:            RecorderTimeObservation{State: "not-reported"},
			Runtime:         RecorderRuntimeObservation{State: "ready", Version: &version},
		},
	}
	observation, err := NewCatalogObservation(command, time.Date(2026, 7, 24, 1, 2, 4, 0, time.UTC), time.Date(2026, 7, 24, 1, 2, 5, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	summary, err := ProjectRecorderObservabilitySummary(observation, nil)
	if err != nil {
		t.Fatal(err)
	}
	if summary.SupportState != "supported" || summary.ExpectationState != "unset" || summary.ReportState != "current" || summary.ReadState != "available" {
		t.Fatalf("Recorder current state axes were collapsed or inferred: %+v", summary)
	}
	if summary.ResourceRevision != 1 || summary.LatestObservationReference == nil || summary.LatestObservationReference.ResourceID != observation.ID {
		t.Fatalf("Recorder current projection lacks explicit latest evidence: %+v", summary)
	}
}
