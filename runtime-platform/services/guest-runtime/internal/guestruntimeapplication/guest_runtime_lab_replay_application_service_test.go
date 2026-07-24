package guestruntimeapplication_test

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"io"
	"math"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayparser"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayspoolsqlite"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type labReplayClock struct {
	mutex sync.Mutex
	next  time.Time
}

func (clock *labReplayClock) Now() time.Time {
	clock.mutex.Lock()
	defer clock.mutex.Unlock()
	value := clock.next
	clock.next = clock.next.Add(time.Second)
	return value
}

type labReplaySourceObject struct {
	source guestruntimedomain.ResourceReference
	sha256 string
	bytes  []byte
}

func (object labReplaySourceObject) CommitLabReplaySourceObject(
	context.Context,
	guestruntimeapplication.LabReplaySourceObjectCommit,
) (guestruntimedomain.LabReplaySourceObjectReceipt, error) {
	return guestruntimedomain.LabReplaySourceObjectReceipt{},
		errors.New("test object is read-only")
}

func (object labReplaySourceObject) OpenLabReplaySourceObject(
	_ context.Context,
	source guestruntimedomain.ResourceReference,
	expectedSHA256 string,
) (io.ReadCloser, error) {
	if source != object.source || expectedSHA256 != object.sha256 {
		return nil, errors.New("source object reference mismatch")
	}
	return io.NopCloser(bytes.NewReader(object.bytes)), nil
}

type failTrackDecodeTransitionOnce struct {
	guestruntimeapplication.GuestRuntimeLabReplayRepository
	failed bool
}

type labReplayEffectRunner struct {
	batches        map[string]guestruntimedomain.LabReplayMessageBatchReceipt
	sendFailure    error
	confirmFailure error
}

func (runner *labReplayEffectRunner) PrepareLabReplay(
	_ context.Context,
	effect guestruntimeapplication.LabReplayPrepareEffect,
) (guestruntimedomain.LabReplayPreparationReceipt, error) {
	return guestruntimedomain.LabReplayPreparationReceipt{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		ReplayID:            effect.ReplayID,
		RunnerSessionID:     "runner-replay-1",
		SpoolDatabaseSHA256: effect.SpoolReceipt.DatabaseSHA256,
		FrameCount:          effect.SpoolReceipt.DurationSeconds,
		OutputStartedAt:     200,
		PreparedAt:          "2030-07-24T15:00:03Z",
	}, nil
}

func (runner *labReplayEffectRunner) SendLabReplayMessageBatch(
	_ context.Context,
	effect guestruntimeapplication.LabReplayMessageBatchEffect,
) (guestruntimedomain.LabReplayMessageBatchReceipt, error) {
	if runner.sendFailure != nil {
		return guestruntimedomain.LabReplayMessageBatchReceipt{},
			runner.sendFailure
	}
	if runner.batches == nil {
		runner.batches = make(map[string]guestruntimedomain.LabReplayMessageBatchReceipt)
	}
	if receipt, ok := runner.batches[effect.BatchID]; ok {
		return receipt, nil
	}
	receipt := guestruntimedomain.LabReplayMessageBatchReceipt{
		SchemaVersion:     guestruntimedomain.SchemaVersion,
		ReplayID:          effect.ReplayID,
		RunnerSessionID:   effect.RunnerSessionID,
		BatchID:           effect.BatchID,
		StartOffsetSecond: effect.StartOffsetSecond,
		FrameCount:        len(effect.Frames),
		FinalBatch:        effect.FinalBatch,
		AcceptedAt:        "2030-07-24T15:00:03Z",
	}
	runner.batches[effect.BatchID] = receipt
	return receipt, nil
}

func (runner *labReplayEffectRunner) ConfirmLabReplayUpstreamDelivery(
	_ context.Context,
	effect guestruntimeapplication.LabReplayUpstreamDeliveryEffect,
) (guestruntimedomain.LabReplayUpstreamDeliveryReceipt, error) {
	if runner.confirmFailure != nil {
		return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{},
			runner.confirmFailure
	}
	return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		ReplayID:            effect.ReplayID,
		RunnerSessionID:     effect.RunnerSessionID,
		DeliveryReceiptID:   "runner-delivery-1",
		DeliveredFrameCount: effect.ExpectedFrameCount,
		DeliveryConfirmedAt: "2030-07-24T15:00:03Z",
	}, nil
}

func (repository *failTrackDecodeTransitionOnce) CommitLabReplayTransition(
	ctx context.Context,
	current guestruntimedomain.LabReplayOperation,
	next guestruntimedomain.LabReplayOperation,
	completedCommand string,
	nextCommand string,
) error {
	if current.State == guestruntimedomain.LabReplayPendingTrackDecodeState &&
		!repository.failed {
		repository.failed = true
		return errors.New("simulated operation commit ambiguity")
	}
	return repository.GuestRuntimeLabReplayRepository.CommitLabReplayTransition(
		ctx,
		current,
		next,
		completedCommand,
		nextCommand,
	)
}

func TestLabReplayRejectsFutureRequestedAtBeforeDurableAdmission(t *testing.T) {
	sourceBytes := applicationReplayVitalSource(t)
	repository := applicationReplayRepository(t)
	service := applicationReplayService(t, repository, sourceBytes)
	command := applicationReplayCommand(sourceBytes)
	command.RequestedAt = "2040-07-24T15:00:00Z"

	_, err := service.AdmitLabReplay(context.Background(), command)
	var rejection guestruntimedomain.LabReplayAdmissionRejectedError
	if !errors.As(err, &rejection) ||
		rejection.Issue.Code != "lab-replay-requested-at-in-future" {
		t.Fatalf("future requestedAt rejection=%#v", err)
	}
	if _, readErr := repository.ReadLabReplayOperationByRequestID(
		context.Background(),
		command.RequestID,
	); !errors.Is(
		readErr,
		guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound,
	) {
		t.Fatalf("future request must not create durable operation: %v", readErr)
	}
}

func TestLabReplayIdempotentRetryReturnsStoredOperationAfterClockRegression(t *testing.T) {
	sourceBytes := applicationReplayVitalSource(t)
	repository := applicationReplayRepository(t)
	clock := &labReplayClock{
		next: time.Date(2030, 7, 24, 15, 0, 1, 0, time.UTC),
	}
	service := applicationReplayServiceWithPolicyRunnerAndClock(
		t,
		repository,
		sourceBytes,
		guestruntimedomain.VitalFileStringTrackPolicySkip,
		&labReplayEffectRunner{},
		clock,
	)
	command := applicationReplayCommand(sourceBytes)
	first, err := service.AdmitLabReplay(context.Background(), command)
	if err != nil {
		t.Fatal(err)
	}

	clock.mutex.Lock()
	clock.next = time.Date(2020, 7, 24, 15, 0, 1, 0, time.UTC)
	clock.mutex.Unlock()
	retried, err := service.AdmitLabReplay(context.Background(), command)
	if err != nil {
		t.Fatalf("idempotent retry must return stored operation: %v", err)
	}
	if retried != first {
		t.Fatalf("idempotent retry=%+v want=%+v", retried, first)
	}
}

func TestLabReplayPersistsOutboxAndRecoversFinalizedSpoolAfterCommitAmbiguity(t *testing.T) {
	sourceBytes := applicationReplayVitalSource(t)
	repository := applicationReplayRepository(t)
	uncertainRepository := &failTrackDecodeTransitionOnce{
		GuestRuntimeLabReplayRepository: repository,
	}
	service := applicationReplayService(
		t,
		uncertainRepository,
		sourceBytes,
	)
	command := applicationReplayCommand(sourceBytes)
	operation, err := service.AdmitLabReplay(context.Background(), command)
	if err != nil {
		t.Fatal(err)
	}
	if operation.State != guestruntimedomain.LabReplayPendingFileValidationState {
		t.Fatalf("admitted operation = %+v", operation)
	}
	operation, ran, err := service.RunNextPendingLabReplayEffect(context.Background())
	if err != nil || !ran ||
		operation.State != guestruntimedomain.LabReplayPendingTrackDecodeState {
		t.Fatalf("file validation operation=%+v ran=%t err=%v", operation, ran, err)
	}
	operation, ran, err = service.RunNextPendingLabReplayEffect(context.Background())
	if err == nil || !ran ||
		operation.State != guestruntimedomain.LabReplayPendingTrackDecodeState {
		t.Fatalf("ambiguous decode operation=%+v ran=%t err=%v", operation, ran, err)
	}
	operation, ran, err = service.RunNextPendingLabReplayEffect(context.Background())
	if err != nil || !ran ||
		operation.State != guestruntimedomain.LabReplayPendingPreparationState ||
		operation.ValidationReceipt == nil {
		t.Fatalf("recovered decode operation=%+v ran=%t err=%v", operation, ran, err)
	}
	if operation.ValidationReceipt.SpoolReceipt.RecordCount != 3 ||
		operation.ValidationReceipt.GraphCompatibleSignalCount != 2 {
		t.Fatalf("validation receipt = %+v", operation.ValidationReceipt)
	}
	pending, err := repository.ListPendingLabReplayEffects(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 1 ||
		pending[0].Command != guestruntimedomain.LabReplayPrepareCommand {
		t.Fatalf("pending effects = %+v", pending)
	}
	operation, ran, err = service.RunNextPendingLabReplayEffect(context.Background())
	if err != nil || !ran || operation.State != guestruntimedomain.LabReplaySendingState {
		t.Fatalf("prepared operation=%+v ran=%t err=%v", operation, ran, err)
	}
	operation, ran, err = service.RunNextPendingLabReplayEffect(context.Background())
	if err != nil || !ran ||
		operation.State != guestruntimedomain.LabReplayAwaitingUpstreamDeliveryState ||
		operation.NextFrameOffsetSecond != 1 {
		t.Fatalf("final send operation=%+v ran=%t err=%v", operation, ran, err)
	}
	operation, ran, err = service.RunNextPendingLabReplayEffect(context.Background())
	if err != nil || !ran ||
		operation.State != guestruntimedomain.LabReplaySucceededState ||
		operation.UpstreamDeliveryReceipt == nil {
		t.Fatalf("delivery operation=%+v ran=%t err=%v", operation, ran, err)
	}
	persisted, err := repository.ReadLabReplayOperation(
		context.Background(),
		command.ReplayID,
	)
	if err != nil || persisted.State != guestruntimedomain.LabReplaySucceededState {
		t.Fatalf("persisted operation=%+v err=%v", persisted, err)
	}
}

func TestLabReplayPersistsTypedFileValidationFailure(t *testing.T) {
	sourceBytes := []byte("not-a-vital-gzip")
	repository := applicationReplayRepository(t)
	service := applicationReplayService(t, repository, sourceBytes)
	command := applicationReplayCommand(sourceBytes)
	if _, err := service.AdmitLabReplay(context.Background(), command); err != nil {
		t.Fatal(err)
	}
	operation, ran, err := service.RunNextPendingLabReplayEffect(context.Background())
	if err != nil || !ran {
		t.Fatalf("typed failure run operation=%+v ran=%t err=%v", operation, ran, err)
	}
	if operation.State != guestruntimedomain.LabReplayFailedState ||
		operation.Failure == nil ||
		operation.Failure.Stage != guestruntimedomain.LabReplayFileValidationFailureStage ||
		operation.Failure.Code != "decode-failed" ||
		operation.MessagesSent != 0 ||
		operation.LastSendState != guestruntimedomain.LabReplayLastSendNotAttemptedState {
		t.Fatalf("typed failure = %+v", operation)
	}
	pending, err := repository.ListPendingLabReplayEffects(context.Background(), 10)
	if err != nil || len(pending) != 0 {
		t.Fatalf("terminal failure pending=%+v err=%v", pending, err)
	}
	read := service.ReadLabReplay(context.Background(), command.ReplayID)
	readOperation, ok := read.Value.(guestruntimedomain.LabReplayOperation)
	if read.State != "available" ||
		!ok ||
		readOperation.Failure == nil ||
		readOperation.Failure.Code != "decode-failed" {
		t.Fatalf("typed failure read = %+v", read)
	}
}

func TestLabReplayPersistsTypedTrackCompatibilityFailures(t *testing.T) {
	for _, fixture := range []struct {
		name         string
		source       func(*testing.T) []byte
		stringPolicy string
		code         string
	}{
		{
			name: "no graph-compatible monitor",
			source: func(t *testing.T) []byte {
				return applicationReplaySingleTrackVitalSource(
					t,
					uint8(guestruntimedomain.VitalFileNumericTrack),
					255,
				)
			},
			stringPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
			code:         "no-vitalserver-graph-tracks",
		},
		{
			name: "unknown track kind",
			source: func(t *testing.T) []byte {
				return applicationReplaySingleTrackVitalSource(t, 4, 0)
			},
			stringPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
			code:         "unsupported-track-type",
		},
		{
			name: "explicit string rejection",
			source: func(t *testing.T) []byte {
				return applicationReplaySingleTrackVitalSource(
					t,
					uint8(guestruntimedomain.VitalFileStringTrack),
					0,
				)
			},
			stringPolicy: guestruntimedomain.VitalFileStringTrackPolicyReject,
			code:         "unsupported-string-track",
		},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			sourceBytes := fixture.source(t)
			repository := applicationReplayRepository(t)
			service := applicationReplayServiceWithPolicyAndRunner(
				t,
				repository,
				sourceBytes,
				fixture.stringPolicy,
				&labReplayEffectRunner{},
			)
			command := applicationReplayCommand(sourceBytes)
			if _, err := service.AdmitLabReplay(
				context.Background(),
				command,
			); err != nil {
				t.Fatal(err)
			}
			operation, ran, err := service.RunNextPendingLabReplayEffect(
				context.Background(),
			)
			if err != nil || !ran ||
				operation.State !=
					guestruntimedomain.LabReplayPendingTrackDecodeState {
				t.Fatalf(
					"validation operation=%+v ran=%t err=%v",
					operation,
					ran,
					err,
				)
			}
			operation, ran, err = service.RunNextPendingLabReplayEffect(
				context.Background(),
			)
			if err != nil || !ran ||
				operation.State != guestruntimedomain.LabReplayFailedState ||
				operation.Failure == nil ||
				operation.Failure.Stage !=
					guestruntimedomain.LabReplayTrackDecodeFailureStage ||
				operation.Failure.Code != fixture.code ||
				operation.MessagesSent != 0 ||
				operation.LastSendState !=
					guestruntimedomain.LabReplayLastSendNotAttemptedState {
				t.Fatalf(
					"track failure operation=%+v ran=%t err=%v",
					operation,
					ran,
					err,
				)
			}
		})
	}
}

func TestLabReplayPersistsTypedRunnerTerminalFailuresAtOwnedStage(t *testing.T) {
	for _, fixture := range []struct {
		name          string
		runner        *labReplayEffectRunner
		expectedStage string
		expectedCode  string
	}{
		{
			name: "message send",
			runner: &labReplayEffectRunner{
				sendFailure: guestruntimeapplication.LabReplayEffectRejectedError{
					Code:    "recorder-gateway-replay-rejected",
					Message: "Gateway rejected the replay frame",
				},
			},
			expectedStage: guestruntimedomain.LabReplayMessageSendFailureStage,
			expectedCode:  "recorder-gateway-replay-rejected",
		},
		{
			name: "upstream delivery",
			runner: &labReplayEffectRunner{
				confirmFailure: guestruntimeapplication.LabReplayEffectRejectedError{
					Code:    "vitalserver-delivery-terminal-failure",
					Message: "VitalServer delivery was exhausted",
				},
			},
			expectedStage: guestruntimedomain.LabReplayUpstreamDeliveryFailureStage,
			expectedCode:  "vitalserver-delivery-terminal-failure",
		},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			sourceBytes := applicationReplayVitalSource(t)
			repository := applicationReplayRepository(t)
			service := applicationReplayServiceWithPolicyAndRunner(
				t,
				repository,
				sourceBytes,
				guestruntimedomain.VitalFileStringTrackPolicySkip,
				fixture.runner,
			)
			command := applicationReplayCommand(sourceBytes)
			operation, err := service.AdmitLabReplay(
				context.Background(),
				command,
			)
			if err != nil {
				t.Fatal(err)
			}
			for attempts := 0; attempts < 8 &&
				operation.State != guestruntimedomain.LabReplayFailedState; attempts++ {
				var ran bool
				operation, ran, err =
					service.RunNextPendingLabReplayEffect(context.Background())
				if err != nil || !ran {
					t.Fatalf(
						"operation=%+v ran=%t err=%v",
						operation,
						ran,
						err,
					)
				}
			}
			if operation.State != guestruntimedomain.LabReplayFailedState ||
				operation.Failure == nil ||
				operation.Failure.Stage != fixture.expectedStage ||
				operation.Failure.Code != fixture.expectedCode {
				t.Fatalf("terminal runner failure=%+v", operation)
			}
		})
	}
}

func applicationReplayService(
	t *testing.T,
	repository guestruntimeapplication.GuestRuntimeLabReplayRepository,
	sourceBytes []byte,
) *guestruntimeapplication.GuestRuntimeLabReplayApplicationService {
	return applicationReplayServiceWithPolicyAndRunner(
		t,
		repository,
		sourceBytes,
		guestruntimedomain.VitalFileStringTrackPolicySkip,
		&labReplayEffectRunner{},
	)
}

func applicationReplayServiceWithPolicyAndRunner(
	t *testing.T,
	repository guestruntimeapplication.GuestRuntimeLabReplayRepository,
	sourceBytes []byte,
	stringTrackPolicy string,
	runner guestruntimeapplication.GuestRuntimeLabReplayEffectRunner,
) *guestruntimeapplication.GuestRuntimeLabReplayApplicationService {
	return applicationReplayServiceWithPolicyRunnerAndClock(
		t,
		repository,
		sourceBytes,
		stringTrackPolicy,
		runner,
		&labReplayClock{
			next: time.Date(2030, 7, 24, 15, 0, 1, 0, time.UTC),
		},
	)
}

func applicationReplayServiceWithPolicyRunnerAndClock(
	t *testing.T,
	repository guestruntimeapplication.GuestRuntimeLabReplayRepository,
	sourceBytes []byte,
	stringTrackPolicy string,
	runner guestruntimeapplication.GuestRuntimeLabReplayEffectRunner,
	clock guestruntimeapplication.GuestRuntimeClock,
) *guestruntimeapplication.GuestRuntimeLabReplayApplicationService {
	t.Helper()
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: stringTrackPolicy,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	spoolFactory, err := vitalfilereplayspoolsqlite.NewFactory(
		filepath.Join(t.TempDir(), "replay-spools"),
	)
	if err != nil {
		t.Fatal(err)
	}
	command := applicationReplayCommand(sourceBytes)
	service, err := guestruntimeapplication.NewGuestRuntimeLabReplayApplicationService(
		repository,
		labReplaySourceObject{
			source: command.SourceReference,
			sha256: command.SourceSHA256,
			bytes:  sourceBytes,
		},
		parser,
		spoolFactory,
		runner,
		1,
		guestruntimedomain.VitalFileReplayGapPolicyFailFrame,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	return service
}

func applicationReplaySingleTrackVitalSource(
	t *testing.T,
	kind uint8,
	monitorType uint8,
) []byte {
	t.Helper()
	format := uint8(0)
	name := "LABEL"
	value := []byte{}
	if kind == uint8(guestruntimedomain.VitalFileNumericTrack) {
		format = 1
		name = "UNKNOWN_NUMERIC"
		value = make([]byte, 4)
		binary.LittleEndian.PutUint32(value, math.Float32bits(72))
	}
	packets := [][]byte{
		applicationReplayTrackPacket(
			t,
			1,
			kind,
			format,
			name,
			0,
			monitorType,
		),
	}
	if len(value) > 0 {
		packets = append(
			packets,
			applicationReplayRecordPacket(t, 1, 100, value),
		)
	}
	var decompressed bytes.Buffer
	decompressed.WriteString("VITA")
	_ = binary.Write(&decompressed, binary.LittleEndian, uint32(3))
	_ = binary.Write(&decompressed, binary.LittleEndian, uint16(10))
	_ = binary.Write(&decompressed, binary.LittleEndian, int16(0))
	_ = binary.Write(&decompressed, binary.LittleEndian, uint32(1))
	decompressed.Write([]byte{1, 0, 0, 0})
	for _, packet := range packets {
		decompressed.Write(packet)
	}
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	if _, err := writer.Write(decompressed.Bytes()); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return compressed.Bytes()
}

func applicationReplayRepository(
	t *testing.T,
) *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository {
	t.Helper()
	root := t.TempDir()
	repository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(
		context.Background(),
		filepath.Join(root, "guest.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	return repository
}

func applicationReplayCommand(sourceBytes []byte) guestruntimedomain.LabReplayCommand {
	digest := sha256.Sum256(sourceBytes)
	return guestruntimedomain.LabReplayCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "lab-replay-request-1",
		ReplayID:      "lab-replay-1",
		SourceReference: guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.LabReplaySourceResourceType,
			ResourceID:   "lab-replay-source-1",
		},
		SourceSHA256:                hex.EncodeToString(digest[:]),
		RecorderGatewayRecorderCode: "LAB-01",
		RequestedAt:                 "2026-07-24T15:00:00Z",
	}
}

func applicationReplayVitalSource(t *testing.T) []byte {
	t.Helper()
	waveform := make([]byte, 12)
	binary.LittleEndian.PutUint32(waveform[:4], 2)
	binary.LittleEndian.PutUint32(waveform[4:8], math.Float32bits(1))
	binary.LittleEndian.PutUint32(waveform[8:12], math.Float32bits(2))
	numeric := make([]byte, 4)
	binary.LittleEndian.PutUint32(numeric, math.Float32bits(72))
	packets := [][]byte{
		applicationReplayTrackPacket(t, 1, uint8(guestruntimedomain.VitalFileWaveformTrack), 1, "PLETH", 2, uint8(guestruntimedomain.VitalServerMonitorPlethWaveform)),
		applicationReplayTrackPacket(t, 2, uint8(guestruntimedomain.VitalFileNumericTrack), 1, "PLETH_HR", 0, uint8(guestruntimedomain.VitalServerMonitorPlethHeartRate)),
		applicationReplayRecordPacket(t, 1, 100, waveform),
		applicationReplayRecordPacket(t, 2, 100, numeric),
		applicationReplayRecordPacket(t, 2, 101, numeric),
	}
	var decompressed bytes.Buffer
	decompressed.WriteString("VITA")
	_ = binary.Write(&decompressed, binary.LittleEndian, uint32(3))
	_ = binary.Write(&decompressed, binary.LittleEndian, uint16(10))
	_ = binary.Write(&decompressed, binary.LittleEndian, int16(0))
	_ = binary.Write(&decompressed, binary.LittleEndian, uint32(1))
	decompressed.Write([]byte{1, 0, 0, 0})
	for _, packet := range packets {
		decompressed.Write(packet)
	}
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	if _, err := writer.Write(decompressed.Bytes()); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return compressed.Bytes()
}

func applicationReplayTrackPacket(
	t *testing.T,
	trackID uint16,
	kind uint8,
	format uint8,
	name string,
	sampleRate float32,
	monitorType uint8,
) []byte {
	t.Helper()
	var payload bytes.Buffer
	_ = binary.Write(&payload, binary.LittleEndian, trackID)
	payload.WriteByte(kind)
	payload.WriteByte(format)
	applicationReplayString(t, &payload, name)
	applicationReplayString(t, &payload, "")
	_ = binary.Write(&payload, binary.LittleEndian, float32(0))
	_ = binary.Write(&payload, binary.LittleEndian, float32(100))
	_ = binary.Write(&payload, binary.LittleEndian, uint32(0))
	_ = binary.Write(&payload, binary.LittleEndian, sampleRate)
	_ = binary.Write(&payload, binary.LittleEndian, float64(0))
	_ = binary.Write(&payload, binary.LittleEndian, float64(0))
	payload.WriteByte(monitorType)
	_ = binary.Write(&payload, binary.LittleEndian, uint32(0))
	return applicationReplayPacket(0, payload.Bytes())
}

func applicationReplayRecordPacket(
	t *testing.T,
	trackID uint16,
	recordedAt float64,
	value []byte,
) []byte {
	t.Helper()
	var payload bytes.Buffer
	_ = binary.Write(&payload, binary.LittleEndian, uint16(10))
	_ = binary.Write(&payload, binary.LittleEndian, recordedAt)
	_ = binary.Write(&payload, binary.LittleEndian, trackID)
	payload.Write(value)
	return applicationReplayPacket(1, payload.Bytes())
}

func applicationReplayPacket(kind uint8, payload []byte) []byte {
	var packet bytes.Buffer
	packet.WriteByte(kind)
	_ = binary.Write(&packet, binary.LittleEndian, uint32(len(payload)))
	packet.Write(payload)
	return packet.Bytes()
}

func applicationReplayString(t *testing.T, target *bytes.Buffer, value string) {
	t.Helper()
	if err := binary.Write(target, binary.LittleEndian, uint32(len(value))); err != nil {
		t.Fatal(err)
	}
	target.WriteString(value)
}
