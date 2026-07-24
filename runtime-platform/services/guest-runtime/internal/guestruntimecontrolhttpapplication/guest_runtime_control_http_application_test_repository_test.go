package guestruntimecontrolhttpapplication

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sort"
	"sync"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type testArchiveLineageRepository struct {
	details        map[string]guestruntimedomain.ArchiveArtifactDetail
	readinessError error
}

func newTestArchiveLineageRepository() *testArchiveLineageRepository {
	return &testArchiveLineageRepository{
		details: make(map[string]guestruntimedomain.ArchiveArtifactDetail),
	}
}

func (repository *testArchiveLineageRepository) Close() error { return nil }

func (repository *testArchiveLineageRepository) WriteGuestOperationalStateArtifactInventory(
	_ context.Context,
	operationID string,
	createdAt string,
	destination io.Writer,
) (int, error) {
	return 0, json.NewEncoder(destination).Encode(
		guestruntimedomain.GuestOperationalStateArtifactInventory{
			SchemaVersion:       guestruntimedomain.SchemaVersion,
			OperationID:         operationID,
			Artifacts:           []guestruntimedomain.GuestOperationalStateArtifactInventoryItem{},
			ObjectBytesIncluded: false,
			CreatedAt:           createdAt,
		},
	)
}

func (repository *testArchiveLineageRepository) GuestRuntimeReadinessDependencyID() string {
	return "archive-export-postgresql"
}

func (repository *testArchiveLineageRepository) VerifyGuestRuntimeReadinessDependency(
	context.Context,
) error {
	return repository.readinessError
}

func (repository *testArchiveLineageRepository) CommitFinalizedArchiveArtifact(
	context.Context,
	guestruntimedomain.ArchiveArtifact,
	guestruntimedomain.RecorderArtifactAttribution,
) error {
	return nil
}

func (repository *testArchiveLineageRepository) CommitArchiveUploadAttempt(
	context.Context,
	guestruntimedomain.ArchiveUploadAttempt,
) error {
	return nil
}

func (repository *testArchiveLineageRepository) CommitArchiveIndexingReceipt(
	context.Context,
	guestruntimedomain.ArchiveIndexingReceipt,
) error {
	return nil
}

func (repository *testArchiveLineageRepository) ReadArchiveArtifactDetail(
	_ context.Context,
	artifactID string,
) (guestruntimedomain.ArchiveArtifactDetail, error) {
	value, exists := repository.details[artifactID]
	if !exists {
		return guestruntimedomain.ArchiveArtifactDetail{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *testArchiveLineageRepository) ListMatchedRecorderArchiveArtifacts(
	_ context.Context,
	recorderID string,
	limit int,
	position *guestruntimeapplication.ArchiveArtifactPagePosition,
) ([]guestruntimedomain.ArchiveArtifactDetail, error) {
	values := make([]guestruntimedomain.ArchiveArtifactDetail, 0)
	for _, detail := range repository.details {
		if detail.Attribution.MatchedRecorderID == nil ||
			*detail.Attribution.MatchedRecorderID != recorderID {
			continue
		}
		if position != nil &&
			!(detail.Attribution.ResolvedAt < position.ResolvedAt ||
				(detail.Attribution.ResolvedAt == position.ResolvedAt &&
					detail.Artifact.ArtifactID < position.ArtifactID)) {
			continue
		}
		values = append(values, detail)
	}
	sort.Slice(values, func(left int, right int) bool {
		if values[left].Attribution.ResolvedAt == values[right].Attribution.ResolvedAt {
			return values[left].Artifact.ArtifactID > values[right].Artifact.ArtifactID
		}
		return values[left].Attribution.ResolvedAt > values[right].Attribution.ResolvedAt
	})
	if len(values) > limit {
		values = values[:limit]
	}
	return values, nil
}

func (repository *testArchiveLineageRepository) ReadArchiveSourceAdmission(
	context.Context,
	string,
) (guestruntimeapplication.ArchiveStoredSourceAdmission, error) {
	return guestruntimeapplication.ArchiveStoredSourceAdmission{},
		guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
}

func (repository *testArchiveLineageRepository) ReadArchiveArtifactDetailBySourceReceipt(
	context.Context,
	string,
	string,
	string,
) (guestruntimedomain.ArchiveArtifactDetail, error) {
	return guestruntimedomain.ArchiveArtifactDetail{},
		guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
}

func (repository *testArchiveLineageRepository) CommitAcceptedArchiveSourceAdmission(
	_ context.Context,
	_ string,
	_ guestruntimedomain.ArchiveSourceAdmissionCommand,
	_ guestruntimedomain.ArchiveSourceAdmissionReceipt,
	artifact guestruntimedomain.ArchiveArtifact,
	attribution guestruntimedomain.RecorderArtifactAttribution,
) error {
	repository.details[artifact.ArtifactID] = guestruntimedomain.ArchiveArtifactDetail{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		Artifact:      artifact,
		Attribution:   attribution,
	}
	return nil
}

func (repository *testArchiveLineageRepository) CommitTerminalArchiveSourceAdmission(
	context.Context,
	string,
	guestruntimedomain.ArchiveSourceAdmissionCommand,
	guestruntimedomain.ArchiveSourceAdmissionReceipt,
) error {
	return nil
}

type testRecorderCatalogRepository struct {
	mu                sync.Mutex
	observations      map[string]guestruntimedomain.CatalogObservation
	bySource          map[string]guestruntimeapplication.CatalogStoredObservation
	byRequest         map[string]guestruntimeapplication.CatalogStoredAdmission
	summaries         map[string]guestruntimedomain.RecorderObservabilitySummary
	expectations      map[string]guestruntimedomain.RecorderExpectation
	expectationEvents map[string]guestruntimeapplication.CatalogStoredExpectationEvent
	readinessError    error
}

type testRecorderAssignmentRepository struct {
	byRequest   map[string]guestruntimeapplication.StoredRecorderAssignmentEvidence
	evidences   []guestruntimedomain.RecorderAssignmentEvidence
	resolutions map[string]guestruntimedomain.RecorderAssignmentResolution
}

func newTestRecorderAssignmentRepository() *testRecorderAssignmentRepository {
	return &testRecorderAssignmentRepository{
		byRequest:   make(map[string]guestruntimeapplication.StoredRecorderAssignmentEvidence),
		resolutions: make(map[string]guestruntimedomain.RecorderAssignmentResolution),
	}
}

func (repository *testRecorderAssignmentRepository) Close() error { return nil }

func (repository *testRecorderAssignmentRepository) GuestRuntimeReadinessDependencyID() string {
	return "recorder-assignment-postgresql"
}

func (repository *testRecorderAssignmentRepository) VerifyGuestRuntimeReadinessDependency(
	context.Context,
) error {
	return nil
}

func (repository *testRecorderAssignmentRepository) ReadRecorderAssignmentEvidenceByRequestID(
	_ context.Context,
	requestID string,
) (guestruntimeapplication.StoredRecorderAssignmentEvidence, error) {
	value, exists := repository.byRequest[requestID]
	if !exists {
		return guestruntimeapplication.StoredRecorderAssignmentEvidence{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *testRecorderAssignmentRepository) CommitRecorderAssignmentEvidence(
	_ context.Context,
	requestID string,
	commandDigest string,
	evidence guestruntimedomain.RecorderAssignmentEvidence,
) error {
	if _, exists := repository.byRequest[requestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[requestID] = guestruntimeapplication.StoredRecorderAssignmentEvidence{
		Evidence:      evidence,
		CommandDigest: commandDigest,
	}
	repository.evidences = append(repository.evidences, evidence)
	return nil
}

func (repository *testRecorderAssignmentRepository) ListEffectiveRecorderAssignmentEvidence(
	context.Context,
	string,
	string,
	int,
) ([]guestruntimedomain.RecorderAssignmentEvidence, error) {
	return append([]guestruntimedomain.RecorderAssignmentEvidence(nil), repository.evidences...), nil
}

func (repository *testRecorderAssignmentRepository) ReadRecorderAssignmentResolution(
	_ context.Context,
	resolutionID string,
) (guestruntimedomain.RecorderAssignmentResolution, error) {
	value, exists := repository.resolutions[resolutionID]
	if !exists {
		return guestruntimedomain.RecorderAssignmentResolution{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *testRecorderAssignmentRepository) CommitRecorderAssignmentResolution(
	_ context.Context,
	resolution guestruntimedomain.RecorderAssignmentResolution,
) error {
	if _, exists := repository.resolutions[resolution.ResolutionID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.resolutions[resolution.ResolutionID] = resolution
	return nil
}

func newTestRecorderCatalogRepository() *testRecorderCatalogRepository {
	return &testRecorderCatalogRepository{
		observations:      make(map[string]guestruntimedomain.CatalogObservation),
		bySource:          make(map[string]guestruntimeapplication.CatalogStoredObservation),
		byRequest:         make(map[string]guestruntimeapplication.CatalogStoredAdmission),
		summaries:         make(map[string]guestruntimedomain.RecorderObservabilitySummary),
		expectations:      make(map[string]guestruntimedomain.RecorderExpectation),
		expectationEvents: make(map[string]guestruntimeapplication.CatalogStoredExpectationEvent),
	}
}

func (repository *testRecorderCatalogRepository) ReadRecorderExpectation(_ context.Context, recorderID string) (guestruntimedomain.RecorderExpectation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	value, exists := repository.expectations[recorderID]
	if !exists {
		return guestruntimedomain.RecorderExpectation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *testRecorderCatalogRepository) ReadRecorderExpectationEventByRequestID(_ context.Context, requestID string) (guestruntimeapplication.CatalogStoredExpectationEvent, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	value, exists := repository.expectationEvents[requestID]
	if !exists {
		return guestruntimeapplication.CatalogStoredExpectationEvent{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *testRecorderCatalogRepository) CommitRecorderExpectation(_ context.Context, event guestruntimedomain.RecorderExpectationEvent, digest string, expectation guestruntimedomain.RecorderExpectation, summary guestruntimedomain.RecorderObservabilitySummary, expectedSummaryRevision int) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.expectationEvents[event.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if current, exists := repository.summaries[summary.RecorderID]; (exists && current.ResourceRevision != expectedSummaryRevision) || (!exists && expectedSummaryRevision != 0) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.expectationEvents[event.RequestID] = guestruntimeapplication.CatalogStoredExpectationEvent{Event: event, CommandDigest: digest}
	repository.expectations[expectation.RecorderID] = expectation
	repository.summaries[summary.RecorderID] = summary
	return nil
}

func (repository *testRecorderCatalogRepository) Close() error { return nil }

func (repository *testRecorderCatalogRepository) GuestRuntimeReadinessDependencyID() string {
	return "recorder-catalog-postgresql"
}

func (repository *testRecorderCatalogRepository) VerifyGuestRuntimeReadinessDependency(
	context.Context,
) error {
	return repository.readinessError
}

func (repository *testRecorderCatalogRepository) ReadGuestOperationalStatePostgreSQLIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStatePostgreSQLIdentity, error) {
	return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{
		DatabaseID:      "guest-postgresql-00000000-0000-0000-0000-000000000001",
		AlembicRevision: "0006_backup_owner",
		OwnerSchemas: append(
			[]string(nil),
			guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...,
		),
	}, nil
}

func (repository *testRecorderCatalogRepository) ReadCatalogObservation(_ context.Context, id string) (guestruntimedomain.CatalogObservation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	observation, exists := repository.observations[id]
	if !exists {
		return guestruntimedomain.CatalogObservation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return observation, nil
}

func (repository *testRecorderCatalogRepository) ListRecorderCatalogObservations(_ context.Context, recorderID string, limit int, position *guestruntimeapplication.CatalogObservationPagePosition, reportedIssuesOnly bool) ([]guestruntimedomain.CatalogObservation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	values := make([]guestruntimedomain.CatalogObservation, 0)
	for _, observation := range repository.observations {
		if observation.Envelope.RecorderID != recorderID || (reportedIssuesOnly && observation.Envelope.Time.Issue == nil && observation.Envelope.Runtime.Issue == nil) {
			continue
		}
		if position != nil && !(observation.PersistedAt < position.PersistedAt || (observation.PersistedAt == position.PersistedAt && observation.ID < position.ObservationID)) {
			continue
		}
		values = append(values, observation)
	}
	sort.Slice(values, func(left, right int) bool {
		if values[left].PersistedAt == values[right].PersistedAt {
			return values[left].ID > values[right].ID
		}
		return values[left].PersistedAt > values[right].PersistedAt
	})
	if len(values) > limit {
		values = values[:limit]
	}
	return values, nil
}

func (repository *testRecorderCatalogRepository) ListRecorderObservabilitySummaries(_ context.Context, limit int, position *guestruntimeapplication.RecorderSummaryPagePosition) ([]guestruntimedomain.RecorderObservabilitySummary, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	values := make([]guestruntimedomain.RecorderObservabilitySummary, 0)
	for _, summary := range repository.summaries {
		if position == nil || summary.RecorderID > position.RecorderID {
			values = append(values, summary)
		}
	}
	sort.Slice(values, func(left, right int) bool {
		return values[left].RecorderID < values[right].RecorderID
	})
	if len(values) > limit {
		values = values[:limit]
	}
	return values, nil
}

func (repository *testRecorderCatalogRepository) ReadCatalogObservationBySourceKey(_ context.Context, sourceKey string) (guestruntimeapplication.CatalogStoredObservation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	observation, exists := repository.bySource[sourceKey]
	if !exists {
		return guestruntimeapplication.CatalogStoredObservation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return observation, nil
}

func (repository *testRecorderCatalogRepository) ReadCatalogObservationAdmissionByRequestID(_ context.Context, requestID string) (guestruntimeapplication.CatalogStoredAdmission, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	admission, exists := repository.byRequest[requestID]
	if !exists {
		return guestruntimeapplication.CatalogStoredAdmission{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return admission, nil
}

func (repository *testRecorderCatalogRepository) ReadRecorderObservabilitySummary(_ context.Context, recorderID string) (guestruntimedomain.RecorderObservabilitySummary, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	summary, exists := repository.summaries[recorderID]
	if !exists {
		return guestruntimedomain.RecorderObservabilitySummary{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return summary, nil
}

func (repository *testRecorderCatalogRepository) CommitAcceptedCatalogObservation(_ context.Context, observation guestruntimedomain.CatalogObservation, commandDigest string, envelopeDigest string, admission guestruntimedomain.CatalogObservationAdmission, summary guestruntimedomain.RecorderObservabilitySummary, expectedPreviousRevision int, _ guestruntimeapplication.CatalogObservationAdmissionEvidence) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	sourceKey := guestruntimedomain.CatalogSourceKey(observation.Envelope)
	if _, exists := repository.byRequest[admission.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if _, exists := repository.bySource[sourceKey]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if existing, exists := repository.summaries[summary.RecorderID]; (exists && existing.ResourceRevision != expectedPreviousRevision) || (!exists && expectedPreviousRevision != 0) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.observations[observation.ID] = observation
	repository.byRequest[admission.RequestID] = guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}
	repository.summaries[summary.RecorderID] = summary
	repository.bySource[sourceKey] = guestruntimeapplication.CatalogStoredObservation{
		Observation:    observation,
		EnvelopeDigest: envelopeDigest,
		Admission:      admission,
	}
	return nil
}

func (repository *testRecorderCatalogRepository) CommitDuplicateCatalogObservationAdmission(_ context.Context, commandDigest string, _ string, _ string, admission guestruntimedomain.CatalogObservationAdmission, _ guestruntimeapplication.CatalogObservationAdmissionEvidence) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.byRequest[admission.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[admission.RequestID] = guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}
	return nil
}

func (repository *testRecorderCatalogRepository) CommitQuarantinedCatalogObservationAdmission(_ context.Context, commandDigest string, admission guestruntimedomain.CatalogObservationAdmission, _ map[string]any, _ guestruntimeapplication.CatalogObservationAdmissionEvidence) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.byRequest[admission.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[admission.RequestID] = guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}
	return nil
}

func openTestGuestRuntimeControlHTTPApplication(
	ctx context.Context,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (*GuestRuntimeControlHTTPApplication, error) {
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err != nil {
		return nil, err
	}
	controlRepository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(
		ctx,
		deployment.GuestRuntimeStateDatabasePath,
	)
	if err != nil {
		return nil, err
	}
	application, err := openGuestRuntimeControlHTTPApplicationWithRepositories(
		controlRepository,
		newTestRecorderCatalogRepository(),
		newTestArchiveLineageRepository(),
		newTestRecorderAssignmentRepository(),
		deployment,
	)
	if err != nil {
		_ = controlRepository.Close()
		return nil, err
	}
	return application, nil
}

func TestGuestRuntimeReadinessPreservesRecorderCatalogPostgreSQLFailure(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	controlRepository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(
		context.Background(),
		deployment.GuestRuntimeStateDatabasePath,
	)
	if err != nil {
		t.Fatal(err)
	}
	recorderCatalog := newTestRecorderCatalogRepository()
	recorderCatalog.readinessError = errors.New("expected Alembic revision is unavailable")
	application, err := openGuestRuntimeControlHTTPApplicationWithRepositories(
		controlRepository,
		recorderCatalog,
		newTestArchiveLineageRepository(),
		newTestRecorderAssignmentRepository(),
		deployment,
	)
	if err != nil {
		_ = controlRepository.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := application.CloseGuestRuntimeControlHTTPApplication(); err != nil {
			t.Fatal(err)
		}
	})

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/v1/runtime/readiness", nil)
	application.ControlHTTPHandler.ServeHTTP(response, request)
	var document struct {
		State string `json:"state"`
		Issue *struct {
			Code       string `json:"code"`
			Dependency string `json:"dependency"`
		} `json:"issue"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &document); err != nil {
		t.Fatal(err)
	}
	if document.State != "failed" ||
		document.Issue == nil ||
		document.Issue.Code != "guest-readiness-dependency-unavailable" ||
		document.Issue.Dependency != "recorder-catalog-postgresql" {
		t.Fatalf("readiness=%s", response.Body.String())
	}
}
