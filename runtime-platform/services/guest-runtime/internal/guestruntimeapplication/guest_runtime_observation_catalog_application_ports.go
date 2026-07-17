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
	Operation      guestruntimedomain.Operation
}

// GuestRuntimeObservationCatalogStateRepository owns immutable Recorder self-observation
// projections. The source identity is a Recorder contract, not Gateway state.
type GuestRuntimeObservationCatalogStateRepository interface {
	ReadCatalogObservation(context.Context, string) (guestruntimedomain.CatalogObservation, error)
	ListCatalogObservations(context.Context) ([]guestruntimedomain.CatalogObservation, error)
	ReadCatalogObservationBySourceKey(context.Context, string) (CatalogStoredObservation, error)
	ReadCatalogObservationIngestOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	AdmitCatalogOperation(context.Context, string, guestruntimedomain.Operation) error
	CommitCatalogObservation(context.Context, guestruntimedomain.CatalogObservation, string, guestruntimedomain.Operation) error
}
