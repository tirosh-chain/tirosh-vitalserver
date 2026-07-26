package gueststatepostgresqlrepository_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestRecorderAssignmentPostgreSQLRepositoryPersistsEvidenceAndResolution(t *testing.T) {
	databaseURL := os.Getenv("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL is not configured")
	}
	repository, err := gueststatepostgresqlrepository.OpenRecorderAssignmentPostgreSQLRepository(
		context.Background(),
		databaseURL,
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	service, err := guestruntimeapplication.NewGuestRuntimeRecorderAssignmentApplicationService(
		repository,
		integrationClock{now: time.Date(2026, 7, 24, 10, 5, 0, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	command := guestruntimedomain.RecorderAssignmentEvidenceCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "postgres-assignment-request-1",
		EvidenceID:    "postgres-assignment-evidence-1",
		RecorderID:    "postgres-assignment-recorder-1",
		BedName:       "OR-PG-01",
		EffectiveFrom: "2026-07-24T10:00:00Z",
		ObservedAt:    "2026-07-24T10:00:00Z",
		SourceKind:    guestruntimedomain.RecorderAssignmentAdministratorSourceKind,
		SourceReference: guestruntimedomain.EvidenceReference{
			Kind: "administrator-command",
			ID:   "postgres-assignment-command-1",
		},
	}
	receipt, rejection, failure := service.AdmitRecorderAssignmentEvidence(
		context.Background(),
		command,
	)
	if rejection != nil || failure != nil || receipt.Outcome != "accepted" {
		t.Fatalf("receipt=%#v rejection=%#v failure=%#v", receipt, rejection, failure)
	}
	resolution, err := service.ResolveRecorderAssignment(
		context.Background(),
		"OR-PG-01",
		"2026-07-24T10:30:00Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(resolution.CandidateRecorderIDs) != 1 ||
		resolution.CandidateRecorderIDs[0] != command.RecorderID {
		t.Fatalf("resolution=%#v", resolution)
	}
}
