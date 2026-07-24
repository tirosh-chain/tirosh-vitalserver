package vitalfilereplayspoolsqlite

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	spoolDatabaseFileName = "replay.sqlite"
	spoolReceiptFileName  = "receipt.json"

	GapPolicyOmitTrack = guestruntimedomain.VitalFileReplayGapPolicyOmitTrack
	GapPolicyFailFrame = guestruntimedomain.VitalFileReplayGapPolicyFailFrame
)

type VitalFileReplaySpoolReceipt = guestruntimedomain.VitalFileReplaySpoolReceipt
type VitalFileReplayFrameTrack = guestruntimedomain.VitalFileReplayFrameTrack
type VitalFileReplayFrame = guestruntimedomain.VitalFileReplayFrame

type VitalFileReplaySpoolFailure struct {
	Code    string
	Message string
}

func (failure VitalFileReplaySpoolFailure) Error() string {
	return failure.Message
}

func (failure VitalFileReplaySpoolFailure) ReplayFailureCode() string {
	return failure.Code
}

type Writer struct {
	rootDirectory       string
	replayID            string
	stagingDirectory    string
	finalDirectory      string
	databasePath        string
	database            *sql.DB
	transaction         *sql.Tx
	headerAccepted      bool
	nextWaveOutputID    uint32
	nextNumericOutputID uint32
	closed              bool
}

func NewWriter(rootDirectory string, replayID string) (*Writer, error) {
	if rootDirectory == "" || !filepath.IsAbs(rootDirectory) ||
		!guestruntimedomain.ValidIdentifier(replayID) {
		return nil, fmt.Errorf("Vital replay spool root and replay identifier are required")
	}
	if err := os.MkdirAll(rootDirectory, 0o700); err != nil {
		return nil, spoolFailure("spool-root-unavailable", "create Vital replay spool root", err)
	}
	stagingDirectory := filepath.Join(rootDirectory, replayID+".staging")
	finalDirectory := filepath.Join(rootDirectory, replayID)
	if _, err := os.Stat(finalDirectory); err == nil {
		return nil, spoolFailure("spool-already-finalized", "Vital replay spool already exists", nil)
	} else if !os.IsNotExist(err) {
		return nil, spoolFailure("spool-state-read-failed", "read Vital replay spool state", err)
	}
	if err := os.Mkdir(stagingDirectory, 0o700); err != nil {
		return nil, spoolFailure("spool-staging-conflict", "create Vital replay staging directory", err)
	}
	databasePath := filepath.Join(stagingDirectory, spoolDatabaseFileName)
	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return nil, failedWriterInitialization(
			stagingDirectory,
			nil,
			spoolFailure("spool-open-failed", "open Vital replay spool database", err),
		)
	}
	if _, err := database.Exec(`
PRAGMA journal_mode = DELETE;
PRAGMA synchronous = FULL;
PRAGMA foreign_keys = ON;
CREATE TABLE tracks (
    track_id INTEGER PRIMARY KEY,
    output_track_id INTEGER NOT NULL UNIQUE,
    kind INTEGER NOT NULL,
    format_code INTEGER NOT NULL,
    name TEXT NOT NULL,
    device_name TEXT NOT NULL,
    unit TEXT NOT NULL,
    sample_rate REAL NOT NULL,
    minimum_display REAL NOT NULL,
    maximum_display REAL NOT NULL,
    gain REAL NOT NULL,
    value_offset REAL NOT NULL,
    monitor_type INTEGER NOT NULL
);
CREATE TABLE waveform_chunks (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    track_id INTEGER NOT NULL REFERENCES tracks(track_id),
    recorded_at REAL NOT NULL,
    sample_offset INTEGER NOT NULL,
    sample_count INTEGER NOT NULL,
    raw_values BLOB NOT NULL
);
CREATE INDEX waveform_chunks_track_time
    ON waveform_chunks(track_id, recorded_at, sequence);
CREATE TABLE numeric_records (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    track_id INTEGER NOT NULL REFERENCES tracks(track_id),
    recorded_at REAL NOT NULL,
    value REAL NOT NULL
);
CREATE INDEX numeric_records_track_time
    ON numeric_records(track_id, recorded_at, sequence);
CREATE TABLE scan_metadata (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    file_format_version TEXT NOT NULL,
    started_at REAL NOT NULL,
    ended_at REAL NOT NULL,
    duration_seconds INTEGER NOT NULL,
    track_count INTEGER NOT NULL,
    record_count INTEGER NOT NULL,
    graph_compatible_signal_count INTEGER NOT NULL,
    finalized_at TEXT NOT NULL
);
`); err != nil {
		return nil, failedWriterInitialization(
			stagingDirectory,
			database,
			spoolFailure("spool-schema-failed", "initialize Vital replay spool schema", err),
		)
	}
	transaction, err := database.Begin()
	if err != nil {
		return nil, failedWriterInitialization(
			stagingDirectory,
			database,
			spoolFailure("spool-transaction-failed", "begin Vital replay spool transaction", err),
		)
	}
	return &Writer{
		rootDirectory:       rootDirectory,
		replayID:            replayID,
		stagingDirectory:    stagingDirectory,
		finalDirectory:      finalDirectory,
		databasePath:        databasePath,
		database:            database,
		transaction:         transaction,
		nextWaveOutputID:    1001,
		nextNumericOutputID: 2001,
	}, nil
}

func (writer *Writer) AcceptHeader(
	header guestruntimedomain.VitalFileReplayHeader,
) error {
	if writer.closed || writer.headerAccepted {
		return spoolFailure("spool-header-conflict", "Vital replay spool header was already accepted or writer is closed", nil)
	}
	writer.headerAccepted = true
	return nil
}

func (writer *Writer) AcceptTrack(
	track guestruntimedomain.VitalFileReplayTrackDefinition,
) error {
	if writer.closed || !writer.headerAccepted {
		return spoolFailure("spool-write-order-invalid", "Vital replay track arrived before its header or after close", nil)
	}
	outputTrackID := uint32(0)
	switch track.Kind {
	case guestruntimedomain.VitalFileWaveformTrack:
		outputTrackID = writer.nextWaveOutputID
		writer.nextWaveOutputID++
	case guestruntimedomain.VitalFileNumericTrack:
		outputTrackID = writer.nextNumericOutputID
		writer.nextNumericOutputID++
	case guestruntimedomain.VitalFileStringTrack:
		// String tracks are decoded for validation but are not replay output.
		outputTrackID = uint32(track.TrackID) + 3000
	default:
		outputTrackID = uint32(track.TrackID) + 4000
	}
	_, err := writer.transaction.Exec(
		`INSERT INTO tracks(
			track_id, output_track_id, kind, format_code, name, device_name,
			unit, sample_rate, minimum_display, maximum_display, gain,
			value_offset, monitor_type
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		track.TrackID,
		outputTrackID,
		track.Kind,
		track.FormatCode,
		track.Name,
		track.DeviceName,
		track.Unit,
		track.SampleRate,
		track.MinimumDisplay,
		track.MaximumDisplay,
		track.Gain,
		track.Offset,
		track.MonitorType,
	)
	if err != nil {
		return spoolFailure("spool-track-write-failed", "persist Vital replay track", err)
	}
	return nil
}

func (writer *Writer) AcceptWaveformChunk(
	chunk guestruntimedomain.VitalFileReplayWaveformChunk,
) error {
	if writer.closed {
		return spoolFailure("spool-writer-closed", "Vital replay spool writer is closed", nil)
	}
	_, err := writer.transaction.Exec(
		`INSERT INTO waveform_chunks(
			track_id, recorded_at, sample_offset, sample_count, raw_values
		) VALUES (?, ?, ?, ?, ?)`,
		chunk.TrackID,
		chunk.RecordedAt,
		chunk.SampleOffset,
		chunk.SampleCount,
		chunk.RawValues,
	)
	if err != nil {
		return spoolFailure("spool-waveform-write-failed", "persist Vital replay waveform chunk", err)
	}
	return nil
}

func (writer *Writer) AcceptNumericRecord(
	record guestruntimedomain.VitalFileReplayNumericRecord,
) error {
	if writer.closed {
		return spoolFailure("spool-writer-closed", "Vital replay spool writer is closed", nil)
	}
	_, err := writer.transaction.Exec(
		`INSERT INTO numeric_records(track_id, recorded_at, value)
		 VALUES (?, ?, ?)`,
		record.TrackID,
		record.RecordedAt,
		record.Value,
	)
	if err != nil {
		return spoolFailure("spool-numeric-write-failed", "persist Vital replay numeric record", err)
	}
	return nil
}

func (writer *Writer) AcceptStringRecord(
	guestruntimedomain.VitalFileReplayStringRecord,
) error {
	if writer.closed {
		return spoolFailure("spool-writer-closed", "Vital replay spool writer is closed", nil)
	}
	return nil
}

func (writer *Writer) Commit(
	result guestruntimedomain.VitalFileReplayScanResult,
	finalizedAt string,
) (VitalFileReplaySpoolReceipt, error) {
	if writer.closed || !writer.headerAccepted {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-commit-invalid", "Vital replay spool cannot be committed", nil)
	}
	if _, err := time.Parse(time.RFC3339Nano, finalizedAt); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-finalized-at-invalid", "Vital replay spool finalizedAt is invalid", err)
	}
	startedAt, endedAt, err := result.TimeRange()
	if err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-time-range-invalid", "Vital replay spool time range is invalid", err)
	}
	durationSeconds := int(math.Ceil(endedAt - startedAt))
	if durationSeconds < 1 {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-duration-invalid", "Vital replay spool duration is not positive", nil)
	}
	if _, err := writer.transaction.Exec(
		`INSERT INTO scan_metadata(
			singleton, file_format_version, started_at, ended_at,
			duration_seconds, track_count, record_count,
			graph_compatible_signal_count, finalized_at
		) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)`,
		result.Compatibility.FileFormatVersion,
		startedAt,
		endedAt,
		durationSeconds,
		len(result.Compatibility.Tracks),
		result.RecordCount,
		result.Compatibility.GraphCompatibleSignalCount,
		finalizedAt,
	); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-metadata-write-failed", "persist Vital replay scan metadata", err)
	}
	if err := writer.transaction.Commit(); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-commit-failed", "commit Vital replay spool database", err)
	}
	writer.transaction = nil
	if err := writer.database.Close(); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-close-failed", "close Vital replay spool database", err)
	}
	writer.database = nil
	if err := syncRegularFile(writer.databasePath); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-database-sync-failed", "sync Vital replay spool database", err)
	}
	databaseSHA256, databaseByteSize, err := digestFile(writer.databasePath)
	if err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-digest-failed", "digest Vital replay spool database", err)
	}
	receipt := VitalFileReplaySpoolReceipt{
		SchemaVersion:              guestruntimedomain.SchemaVersion,
		ReplayID:                   writer.replayID,
		FileFormatVersion:          result.Compatibility.FileFormatVersion,
		DatabaseSHA256:             databaseSHA256,
		DatabaseByteSize:           databaseByteSize,
		StartedAt:                  startedAt,
		EndedAt:                    endedAt,
		DurationSeconds:            durationSeconds,
		TrackCount:                 len(result.Compatibility.Tracks),
		RecordCount:                result.RecordCount,
		GraphCompatibleSignalCount: result.Compatibility.GraphCompatibleSignalCount,
		FinalizedAt:                finalizedAt,
	}
	if err := writeReceipt(
		filepath.Join(writer.stagingDirectory, spoolReceiptFileName),
		receipt,
	); err != nil {
		return VitalFileReplaySpoolReceipt{}, err
	}
	if err := syncDirectory(writer.stagingDirectory); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-sync-failed", "sync Vital replay staging directory", err)
	}
	if err := os.Rename(writer.stagingDirectory, writer.finalDirectory); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-finalize-failed", "finalize Vital replay spool directory", err)
	}
	writer.closed = true
	if err := syncDirectory(writer.rootDirectory); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-root-sync-failed", "sync Vital replay spool root", err)
	}
	return receipt, nil
}

func (writer *Writer) Abort() error {
	if writer.closed {
		return nil
	}
	writer.closed = true
	if writer.transaction != nil {
		_ = writer.transaction.Rollback()
		writer.transaction = nil
	}
	if writer.database != nil {
		_ = writer.database.Close()
		writer.database = nil
	}
	if err := os.RemoveAll(writer.stagingDirectory); err != nil {
		return spoolFailure("spool-abort-failed", "remove operation-owned Vital replay staging spool", err)
	}
	return syncDirectory(writer.rootDirectory)
}

func digestFile(path string) (string, int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	digest := sha256.New()
	byteSize, err := io.Copy(digest, file)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(digest.Sum(nil)), byteSize, nil
}

func writeReceipt(path string, receipt VitalFileReplaySpoolReceipt) error {
	encoded, err := json.Marshal(receipt)
	if err != nil {
		return spoolFailure("spool-receipt-encode-failed", "encode Vital replay spool receipt", err)
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return spoolFailure("spool-receipt-write-failed", "create Vital replay spool receipt", err)
	}
	if _, err := file.Write(append(encoded, '\n')); err != nil {
		_ = file.Close()
		return spoolFailure("spool-receipt-write-failed", "write Vital replay spool receipt", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return spoolFailure("spool-receipt-sync-failed", "sync Vital replay spool receipt", err)
	}
	if err := file.Close(); err != nil {
		return spoolFailure("spool-receipt-close-failed", "close Vital replay spool receipt", err)
	}
	return nil
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

func syncRegularFile(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return file.Sync()
}

func failedWriterInitialization(
	stagingDirectory string,
	database *sql.DB,
	primary error,
) error {
	if database != nil {
		if err := database.Close(); err != nil {
			return spoolFailure(
				"spool-bootstrap-cleanup-failed",
				fmt.Sprintf("%v; close failed", primary),
				err,
			)
		}
	}
	if err := os.RemoveAll(stagingDirectory); err != nil {
		return spoolFailure(
			"spool-bootstrap-cleanup-failed",
			fmt.Sprintf("%v; staging cleanup failed", primary),
			err,
		)
	}
	return primary
}

func spoolFailure(code string, message string, cause error) VitalFileReplaySpoolFailure {
	if cause != nil {
		message = fmt.Sprintf("%s: %v", message, cause)
	}
	return VitalFileReplaySpoolFailure{Code: code, Message: message}
}

var _ guestruntimeapplication.GuestRuntimeVitalFileReplayRecordSink = (*Writer)(nil)
var _ guestruntimeapplication.GuestRuntimeVitalFileReplaySpoolWriter = (*Writer)(nil)
