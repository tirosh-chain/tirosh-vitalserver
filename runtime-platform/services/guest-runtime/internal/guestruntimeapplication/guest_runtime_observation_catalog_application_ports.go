package guestruntimeapplication

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// CatalogStoredObservation is the Observation Catalog owner's immutable
// projection plus its exact Recorder-envelope digest and ingest operation.
type CatalogStoredObservation struct {
	Observation    guestruntimedomain.CatalogObservation
	EnvelopeDigest string
	Admission      guestruntimedomain.CatalogObservationAdmission
}

type CatalogStoredAdmission struct {
	Admission     guestruntimedomain.CatalogObservationAdmission
	CommandDigest string
}

type CatalogStoredExpectationEvent struct {
	Event         guestruntimedomain.RecorderExpectationEvent
	CommandDigest string
}

// CatalogObservationAdmissionEvidence is transport-owned evidence captured
// after the Recorder Gateway credential has been authenticated. The Catalog
// persists it but does not infer it from the observation document.
type CatalogObservationAdmissionEvidence struct {
	SourceIdentity string
	MediaType      string
	ReceivedBytes  int64
}

type CatalogObservationPagePosition struct {
	PersistedAt   string
	ObservationID string
}

type RecorderSummaryPagePosition struct {
	RecorderID string
}

// GuestRuntimeObservationCatalogStateRepository owns immutable Recorder self-observation
// projections. The source identity is a Recorder contract, not Gateway state.
type GuestRuntimeObservationCatalogStateRepository interface {
	ReadCatalogObservation(context.Context, string) (guestruntimedomain.CatalogObservation, error)
	ListRecorderCatalogObservations(context.Context, string, int, *CatalogObservationPagePosition, bool) ([]guestruntimedomain.CatalogObservation, error)
	ListRecorderObservabilitySummaries(context.Context, int, *RecorderSummaryPagePosition) ([]guestruntimedomain.RecorderObservabilitySummary, error)
	ReadCatalogObservationBySourceKey(context.Context, string) (CatalogStoredObservation, error)
	ReadCatalogObservationAdmissionByRequestID(context.Context, string) (CatalogStoredAdmission, error)
	ReadRecorderObservabilitySummary(context.Context, string) (guestruntimedomain.RecorderObservabilitySummary, error)
	ReadRecorderExpectation(context.Context, string) (guestruntimedomain.RecorderExpectation, error)
	ReadRecorderExpectationEventByRequestID(context.Context, string) (CatalogStoredExpectationEvent, error)
	CommitAcceptedCatalogObservation(context.Context, guestruntimedomain.CatalogObservation, string, string, guestruntimedomain.CatalogObservationAdmission, guestruntimedomain.RecorderObservabilitySummary, int, CatalogObservationAdmissionEvidence) error
	CommitDuplicateCatalogObservationAdmission(context.Context, string, string, string, guestruntimedomain.CatalogObservationAdmission, CatalogObservationAdmissionEvidence) error
	CommitQuarantinedCatalogObservationAdmission(context.Context, string, guestruntimedomain.CatalogObservationAdmission, map[string]any, CatalogObservationAdmissionEvidence) error
	CommitRecorderExpectation(context.Context, guestruntimedomain.RecorderExpectationEvent, string, guestruntimedomain.RecorderExpectation, guestruntimedomain.RecorderObservabilitySummary, int) error
}
