// Package guestruntimeapplication orchestrates Guest Runtime ownership through explicit ports.
package guestruntimeapplication

import (
	"context"
	"errors"
	"io"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

var ErrGuestRuntimeOwnedResourceNotFound = errors.New("owned resource not found")
var ErrGuestRuntimeOwnedResourceConflict = errors.New("owned resource conflict")
var ErrGuestRuntimeOwnedResourceRevisionConflict = errors.New("owned resource revision conflict")
var ErrArchiveArtifactObjectContentMismatch = errors.New("Archive artifact object content mismatch")
var ErrLabReplaySourceObjectContentMismatch = errors.New("Lab replay source object content mismatch")

// SourceEligibilityError is a known Lab-owned negative answer. It is distinct
// from a repository failure: Archive Export can reject before admission when a
// recorder is not stopped, but must not invent that answer when Lab is unreadable.
type SourceEligibilityError struct {
	Issue guestruntimedomain.Issue
}

func (error SourceEligibilityError) Error() string {
	return error.Issue.Code + ": " + error.Issue.Message
}

// GuestRuntimeTopologyStateRepository owns persistence of the Guest Runtime topology,
// topology capability, and topology command operation. It is intentionally
// narrower than Lab, archive, time, catalog, and telemetry repositories.
type GuestRuntimeTopologyStateRepository interface {
	VerifyRuntimeTopologyStateStoreAvailability(context.Context) error
	ReadRuntimeTopology(context.Context) (guestruntimedomain.RuntimeTopology, error)
	ReadRuntimeTopologyCapabilityDocument(context.Context) (guestruntimedomain.CapabilityDocument, error)
	ReadRuntimeTopologyOperation(context.Context, string) (guestruntimedomain.Operation, error)
	ReadRuntimeTopologyOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	CommitRuntimeTopologyApplication(context.Context, guestruntimedomain.RuntimeTopology, *guestruntimedomain.CapabilityDocument, guestruntimedomain.Operation) error
}

// GuestRuntimeReadinessDependency is one explicitly composed product
// dependency whose owner can prove availability. Readiness consumes this
// result; it does not infer dependency state from process presence, logs, or
// another repository.
type GuestRuntimeReadinessDependency interface {
	GuestRuntimeReadinessDependencyID() string
	VerifyGuestRuntimeReadinessDependency(context.Context) error
}

// GuestRuntimeSQLiteIdentityReader and
// GuestRuntimePostgreSQLIdentityReader are separate owner ports. The
// application service composes them into one all-or-failed observation.
type GuestRuntimeSQLiteIdentityReader interface {
	ReadGuestOperationalStateSQLiteIdentity(
		context.Context,
	) (guestruntimedomain.GuestOperationalStateSQLiteIdentity, error)
}

type GuestRuntimePostgreSQLIdentityReader interface {
	ReadGuestOperationalStatePostgreSQLIdentity(
		context.Context,
	) (guestruntimedomain.GuestOperationalStatePostgreSQLIdentity, error)
}

type GuestRuntimeBootstrapIdentityReader interface {
	ReadGuestOperationalStateBootstrapIdentity(
		context.Context,
	) (guestruntimedomain.GuestOperationalStateBootstrapIdentity, error)
}

type StoredRecorderAssignmentEvidence struct {
	Evidence      guestruntimedomain.RecorderAssignmentEvidence
	CommandDigest string
}

// GuestRuntimeRecorderAssignmentRepository is the only persistence boundary
// for assignment evidence and time-bounded resolution receipts.
type GuestRuntimeRecorderAssignmentRepository interface {
	ReadRecorderAssignmentEvidenceByRequestID(
		context.Context,
		string,
	) (StoredRecorderAssignmentEvidence, error)
	CommitRecorderAssignmentEvidence(
		context.Context,
		string,
		string,
		guestruntimedomain.RecorderAssignmentEvidence,
	) error
	ListEffectiveRecorderAssignmentEvidence(
		context.Context,
		string,
		string,
		int,
	) ([]guestruntimedomain.RecorderAssignmentEvidence, error)
	ReadRecorderAssignmentResolution(
		context.Context,
		string,
	) (guestruntimedomain.RecorderAssignmentResolution, error)
	CommitRecorderAssignmentResolution(
		context.Context,
		guestruntimedomain.RecorderAssignmentResolution,
	) error
}

// LabStateTransitionCommit is the one explicit mutation envelope consumed by the Lab
// repository. The application layer computes every state transition before the
// adapter writes it; the adapter only performs the atomic persistence effect.
type LabStateTransitionCommit struct {
	Operation             guestruntimedomain.Operation
	OperationContinuation bool
	UpsertSession         *guestruntimedomain.LabSession
	UpsertBeds            []guestruntimedomain.LabBed
	UpsertRecorders       []guestruntimedomain.VirtualRecorder
	DeleteSessionID       string
	DeleteBedIDs          []string
	DeleteRecorderIDs     []string
	DeletionReceipt       *guestruntimedomain.DeletionReceipt
}

type GuestRuntimeLabStateRepository interface {
	ReadLabSession(context.Context, string) (guestruntimedomain.LabSession, error)
	ListLabSessions(context.Context) ([]guestruntimedomain.LabSession, error)
	ReadLabBed(context.Context, string) (guestruntimedomain.LabBed, error)
	ListLabBeds(context.Context) ([]guestruntimedomain.LabBed, error)
	ListLabBedsBySession(context.Context, string) ([]guestruntimedomain.LabBed, error)
	ReadLabVirtualRecorder(context.Context, string) (guestruntimedomain.VirtualRecorder, error)
	ListVirtualRecorders(context.Context) ([]guestruntimedomain.VirtualRecorder, error)
	ListVirtualRecordersBySession(context.Context, string) ([]guestruntimedomain.VirtualRecorder, error)
	ReadLabOperation(context.Context, string) (guestruntimedomain.Operation, error)
	ReadLabOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	ReadLabResourceDeletionReceipt(context.Context, string) (guestruntimedomain.DeletionReceipt, error)
	CommitLabStateTransition(context.Context, LabStateTransitionCommit) error
}

// GuestRuntimeLabRecorderSourceReader is the only Archive-to-Lab state boundary. Archive Export
// receives a complete stopped-source fact or an explicit failure; it does not
// read Lab tables, Lab files, or presentation state.
type GuestRuntimeLabRecorderSourceReader interface {
	ReadStoppedLabVirtualRecorderArchiveSource(context.Context, string, int) (guestruntimedomain.StoppedRecorderSource, error)
}

// GuestRuntimeLabRecorderRunner is the only Lab-to-Runner control boundary.
// The runner owns live Socket.IO effects and Gateway finalization calls; Lab
// owns durable lifecycle state and persists only the receipts this port returns.
type GuestRuntimeLabRecorderRunner interface {
	StartLabVirtualRecorderRun(context.Context, string, string, string, string) (guestruntimedomain.LabRecorderRunnerStartReceipt, error)
	StopLabVirtualRecorderRun(context.Context, string, string, int) (guestruntimedomain.LabRecorderRunnerFinalizationReceipt, error)
}

// GuestRuntimeRecorderColdPathPacketSequenceReader is the only Archive-to-
// Recorder Gateway source boundary. The adapter must return a complete,
// receipt-verified source or an explicit error. It never turns a missing
// Gateway capture into an empty artifact input.
type GuestRuntimeRecorderColdPathPacketSequenceReader interface {
	ReadFinalizedRecorderColdPathPacketSequence(context.Context, guestruntimedomain.ArtifactExportSource) (guestruntimedomain.FinalizedRecorderColdPathPacketSequence, error)
}

// GuestRuntimeVitalArtifactFormationProvider owns the binary .vital formation
// boundary. It consumes verified source bytes and returns the evidence that
// identifies that source; it does not read Lab state, access Gateway storage,
// or upload the artifact.
type GuestRuntimeVitalArtifactFormationProvider interface {
	FormVitalArtifact(context.Context, guestruntimedomain.StoppedRecorderSource, guestruntimedomain.FinalizedRecorderColdPathPacketSequence) ([]byte, guestruntimedomain.EvidenceReference, error)
}

type GuestRuntimeArchiveStateRepository interface {
	ReadArtifactExportOperation(context.Context, string) (guestruntimedomain.Operation, error)
	ReadArtifactExportOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	ReadArtifactManifest(context.Context, string) (guestruntimedomain.ArtifactManifest, error)
	ReadArtifactExportReceipt(context.Context, string) (guestruntimedomain.ExportReceipt, error)
	AdmitArtifactExport(context.Context, guestruntimedomain.ArtifactManifest, []byte, string, guestruntimedomain.Operation) error
	CommitArtifactExportOutcome(context.Context, guestruntimedomain.ExportReceipt, guestruntimedomain.Operation) error
	ListArtifactsRetainedForResource(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error)
}

// ArchiveArtifactPagePosition is the decoded PostgreSQL keyset position for
// one Recorder artifact page. Presentation cursors remain opaque outside the
// application layer.
type ArchiveArtifactPagePosition struct {
	ResolvedAt string
	ArtifactID string
}

const (
	MaximumRecorderArtifactPageSize = 100
	// Repository reads one additional item so the application owner can
	// produce an opaque next cursor without issuing a second query.
	MaximumRecorderArtifactRepositoryFetchSize = MaximumRecorderArtifactPageSize + 1
)

// GuestRuntimeArchiveLineageRepository owns durable artifact identity,
// Recorder attribution, upload attempts, and indexing receipts in the
// archive_export PostgreSQL schema. It deliberately does not own command
// operations or artifact bytes.
type GuestRuntimeArchiveLineageRepository interface {
	CommitFinalizedArchiveArtifact(
		context.Context,
		guestruntimedomain.ArchiveArtifact,
		guestruntimedomain.RecorderArtifactAttribution,
	) error
	CommitArchiveUploadAttempt(
		context.Context,
		guestruntimedomain.ArchiveUploadAttempt,
	) error
	CommitArchiveIndexingReceipt(
		context.Context,
		guestruntimedomain.ArchiveIndexingReceipt,
	) error
	ReadArchiveArtifactDetail(
		context.Context,
		string,
	) (guestruntimedomain.ArchiveArtifactDetail, error)
	ListMatchedRecorderArchiveArtifacts(
		context.Context,
		string,
		int,
		*ArchiveArtifactPagePosition,
	) ([]guestruntimedomain.ArchiveArtifactDetail, error)
}

// ArchiveStoredSourceAdmission binds request-id idempotency to the complete
// source command digest and the durable owner receipt.
type ArchiveStoredSourceAdmission struct {
	CommandDigest string
	Command       guestruntimedomain.ArchiveSourceAdmissionCommand
	Receipt       guestruntimedomain.ArchiveSourceAdmissionReceipt
}

// GuestRuntimeArchiveSourceAdmissionRepository owns Recorder upload source
// admission receipts. Accepted admission, artifact identity, and attribution
// are committed atomically; artifact bytes remain owned by the object store.
type GuestRuntimeArchiveSourceAdmissionRepository interface {
	ReadArchiveSourceAdmission(
		context.Context,
		string,
	) (ArchiveStoredSourceAdmission, error)
	ReadArchiveArtifactDetailBySourceReceipt(
		context.Context,
		string,
		string,
		string,
	) (guestruntimedomain.ArchiveArtifactDetail, error)
	CommitAcceptedArchiveSourceAdmission(
		context.Context,
		string,
		guestruntimedomain.ArchiveSourceAdmissionCommand,
		guestruntimedomain.ArchiveSourceAdmissionReceipt,
		guestruntimedomain.ArchiveArtifact,
		guestruntimedomain.RecorderArtifactAttribution,
	) error
	CommitTerminalArchiveSourceAdmission(
		context.Context,
		string,
		guestruntimedomain.ArchiveSourceAdmissionCommand,
		guestruntimedomain.ArchiveSourceAdmissionReceipt,
	) error
}

type ArchiveArtifactObjectCommit struct {
	ArtifactID  string
	Source      guestruntimedomain.RecorderVitalUploadSourceReceipt
	Content     io.Reader
	PersistedAt string
}

// GuestRuntimeArchiveArtifactObjectStore owns direct-upload .vital bytes. It
// verifies the complete Gateway receipt while streaming and atomically exposes
// only a content object accompanied by a durable object receipt.
type GuestRuntimeArchiveArtifactObjectStore interface {
	CommitArchiveArtifactObject(
		context.Context,
		ArchiveArtifactObjectCommit,
	) (guestruntimedomain.ArchiveArtifactObjectReceipt, error)
}

type StoredLabReplaySourceAdmission struct {
	CommandDigest string
	Command       guestruntimedomain.LabReplaySourceAdmissionCommand
	Receipt       guestruntimedomain.LabReplaySourceAdmissionReceipt
}

type GuestRuntimeLabReplaySourceRepository interface {
	ReadLabReplaySourceAdmission(
		context.Context,
		string,
	) (StoredLabReplaySourceAdmission, error)
	CommitLabReplaySourceAdmission(
		context.Context,
		string,
		guestruntimedomain.LabReplaySourceAdmissionCommand,
		guestruntimedomain.LabReplaySourceAdmissionReceipt,
	) error
}

type LabReplaySourceObjectCommit struct {
	Command     guestruntimedomain.LabReplaySourceAdmissionCommand
	Content     io.Reader
	PersistedAt string
}

type GuestRuntimeLabReplaySourceObjectStore interface {
	CommitLabReplaySourceObject(
		context.Context,
		LabReplaySourceObjectCommit,
	) (guestruntimedomain.LabReplaySourceObjectReceipt, error)
	OpenLabReplaySourceObject(
		context.Context,
		guestruntimedomain.ResourceReference,
		string,
	) (io.ReadCloser, error)
}

type GuestRuntimeVitalFileReplayRecordSink interface {
	AcceptHeader(guestruntimedomain.VitalFileReplayHeader) error
	AcceptTrack(guestruntimedomain.VitalFileReplayTrackDefinition) error
	AcceptWaveformChunk(guestruntimedomain.VitalFileReplayWaveformChunk) error
	AcceptNumericRecord(guestruntimedomain.VitalFileReplayNumericRecord) error
	AcceptStringRecord(guestruntimedomain.VitalFileReplayStringRecord) error
}

type GuestRuntimeVitalFileReplayParser interface {
	Probe(io.Reader) (guestruntimedomain.VitalFileReplayHeader, error)
	Scan(
		io.Reader,
		GuestRuntimeVitalFileReplayRecordSink,
	) (guestruntimedomain.VitalFileReplayScanResult, error)
}

type GuestRuntimeVitalFileReplaySpoolWriter interface {
	GuestRuntimeVitalFileReplayRecordSink
	Commit(
		guestruntimedomain.VitalFileReplayScanResult,
		string,
	) (guestruntimedomain.VitalFileReplaySpoolReceipt, error)
	Abort() error
}

type GuestRuntimeVitalFileReplaySpoolFactory interface {
	NewSpoolWriter(string) (GuestRuntimeVitalFileReplaySpoolWriter, error)
	ReadFinalizedSpoolReceipt(
		string,
	) (guestruntimedomain.VitalFileReplaySpoolReceipt, error)
	OpenSpoolReader(
		string,
		guestruntimedomain.VitalFileReplaySpoolReceipt,
		string,
	) (GuestRuntimeVitalFileReplaySpoolReader, error)
}

type GuestRuntimeVitalFileReplaySpoolReader interface {
	Receipt() guestruntimedomain.VitalFileReplaySpoolReceipt
	Frame(int, float64) (guestruntimedomain.VitalFileReplayFrame, error)
	Close() error
}

type LabReplayPrepareEffect struct {
	ReplayID                    string
	RecorderGatewayRecorderCode string
	SpoolReceipt                guestruntimedomain.VitalFileReplaySpoolReceipt
}

type LabReplayMessageBatchEffect struct {
	ReplayID          string
	RunnerSessionID   string
	BatchID           string
	StartOffsetSecond int
	Frames            []guestruntimedomain.VitalFileReplayFrame
	FinalBatch        bool
}

type LabReplayUpstreamDeliveryEffect struct {
	ReplayID           string
	RunnerSessionID    string
	ExpectedFrameCount int
}

type GuestRuntimeLabReplayEffectRunner interface {
	PrepareLabReplay(
		context.Context,
		LabReplayPrepareEffect,
	) (guestruntimedomain.LabReplayPreparationReceipt, error)
	SendLabReplayMessageBatch(
		context.Context,
		LabReplayMessageBatchEffect,
	) (guestruntimedomain.LabReplayMessageBatchReceipt, error)
	ConfirmLabReplayUpstreamDelivery(
		context.Context,
		LabReplayUpstreamDeliveryEffect,
	) (guestruntimedomain.LabReplayUpstreamDeliveryReceipt, error)
}

type LabReplayEffectRejectedError struct {
	Code    string
	Message string
}

func (failure LabReplayEffectRejectedError) Error() string {
	return failure.Message
}

type PendingLabReplayEffect struct {
	Operation guestruntimedomain.LabReplayOperation
	Command   string
	CreatedAt string
}

type GuestRuntimeLabReplayRepository interface {
	ReadLabReplayOperation(
		context.Context,
		string,
	) (guestruntimedomain.LabReplayOperation, error)
	ReadLabReplayOperationByRequestID(
		context.Context,
		string,
	) (guestruntimedomain.LabReplayOperation, error)
	AdmitLabReplayOperation(
		context.Context,
		string,
		guestruntimedomain.LabReplayOperation,
		string,
	) error
	CommitLabReplayTransition(
		context.Context,
		guestruntimedomain.LabReplayOperation,
		guestruntimedomain.LabReplayOperation,
		string,
		string,
	) error
	ListPendingLabReplayEffects(
		context.Context,
		int,
	) ([]PendingLabReplayEffect, error)
}

// GuestRuntimeRecorderArtifactAttributionResolver is the only assignment-owner
// boundary consumed by Archive Export. It returns a complete candidate answer
// or an error; Archive Export never substitutes bed-name matching.
type GuestRuntimeRecorderArtifactAttributionResolver interface {
	ResolveRecorderArtifactAttribution(
		context.Context,
		guestruntimedomain.RecorderVitalUploadSourceReceipt,
		string,
		string,
	) (guestruntimedomain.RecorderAttributionResolutionInput, error)
}

// GuestRuntimeArchiveExportProvider owns the result of each external export step. A returned
// error means the effect outcome is unknown; Archive Export keeps its durable
// operation running rather than writing a guessed failed or successful receipt.
type GuestRuntimeArchiveExportProvider interface {
	ArchiveExportProviderReference() guestruntimedomain.ArchiveProviderReference
	UploadArtifactExportPayload(context.Context, guestruntimedomain.ArtifactManifest, []byte, string) (guestruntimedomain.ExportStep, error)
	VerifyUploadedArtifactIndex(context.Context, guestruntimedomain.ArtifactManifest, guestruntimedomain.ExportStep, string) (guestruntimedomain.ExportStep, error)
}

// GuestRuntimeArchiveCredentialMaterialOwner owns only C51's private Guest
// file. It exposes a non-secret availability projection and one atomic
// provision effect. It must not use the Guest Runtime SQLite repository,
// produce an Operation/receipt, or return credential values to its caller.
type GuestRuntimeArchiveCredentialMaterialOwner interface {
	CredentialReference() guestruntimedomain.VitalServerIndexedLibraryCredentialReference
	ObserveVitalServerIndexedLibraryCredentialMaterial(context.Context) (string, *guestruntimedomain.Issue)
	ProvisionVitalServerIndexedLibraryCredentialMaterial(context.Context, guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial) *guestruntimedomain.Issue
}

// GuestRuntimeExternalUpstreamStateRepository owns only ExternalUpstreamIntegration documents
// and their provider capability projections. Topology accesses this owner
// through GuestRuntimeExternalUpstreamCapabilityReader rather than its SQLite tables.
type GuestRuntimeExternalUpstreamStateRepository interface {
	ReadExternalUpstreamIntegrationState(context.Context, string) (guestruntimedomain.ExternalUpstreamIntegration, error)
	ListExternalUpstreamIntegrations(context.Context) ([]guestruntimedomain.ExternalUpstreamIntegration, error)
	ReadExternalUpstreamCapabilityDocument(context.Context, string) (guestruntimedomain.CapabilityDocument, error)
	ReadExternalUpstreamIntegrationOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	AdmitExternalUpstreamOperation(context.Context, string, int, guestruntimedomain.Operation) error
	CommitExternalUpstreamOutcome(context.Context, guestruntimedomain.ExternalUpstreamIntegration, *guestruntimedomain.CapabilityDocument, guestruntimedomain.Operation) error
}

// GuestRuntimeExternalUpstreamCapabilityReader is the only Topology-to-External-Upstream boundary.
// It returns owner-provided integration and capability documents, never a
// synthesized topology or a direct persistence handle.
type GuestRuntimeExternalUpstreamCapabilityReader interface {
	ReadExternalUpstreamIntegrationState(context.Context, string) (guestruntimedomain.ExternalUpstreamIntegration, error)
	ReadExternalUpstreamCapabilityDocument(context.Context, string) (guestruntimedomain.CapabilityDocument, error)
}

// GuestRuntimeExternalUpstreamProvider translates a certified external provider profile
// into an explicit connection/capability answer. An error means the effect
// outcome is unknown; it is not a known unavailable/failed observation.
type GuestRuntimeExternalUpstreamProvider interface {
	ExternalUpstreamObservationProviderReference() guestruntimedomain.IntegrationProviderReference
	ObserveExternalUpstream(context.Context, string, guestruntimedomain.ExternalUpstreamSpec, string) (guestruntimedomain.ExternalUpstreamObservation, error)
}

type GuestRuntimeOutboundRelayStateRepository interface {
	ReadOutboundRelayTarget(context.Context, string) (guestruntimedomain.OutboundRelayTarget, error)
	ListOutboundRelayTargets(context.Context) ([]guestruntimedomain.OutboundRelayTarget, error)
	ReadOutboundRelayTargetOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	AdmitOutboundRelayOperation(context.Context, string, int, guestruntimedomain.Operation) error
	CommitOutboundRelayOutcome(context.Context, guestruntimedomain.OutboundRelayTarget, guestruntimedomain.Operation) error
}

// GuestRuntimeOutboundRelayProvider observes the relay target's own protocol boundary. It
// never reports downstream consumer business processing or upstream state.
type GuestRuntimeOutboundRelayProvider interface {
	OutboundRelayObservationProviderReference() guestruntimedomain.IntegrationProviderReference
	ObserveOutboundRelay(context.Context, string, guestruntimedomain.OutboundRelayTargetSpec, string) (guestruntimedomain.OutboundRelayObservation, error)
}

type GuestRuntimeClock interface {
	Now() time.Time
}

type SystemGuestRuntimeClock struct{}

func (SystemGuestRuntimeClock) Now() time.Time {
	return time.Now().UTC()
}

type GuestRuntimeRequestCorrelationIdentifierGenerator interface {
	NewRequestCorrelationIdentifier(string) (string, error)
}

type CryptoGuestRuntimeRequestCorrelationIdentifierGenerator struct{}

func (CryptoGuestRuntimeRequestCorrelationIdentifierGenerator) NewRequestCorrelationIdentifier(prefix string) (string, error) {
	return guestruntimedomain.NewIdentifier(prefix)
}
