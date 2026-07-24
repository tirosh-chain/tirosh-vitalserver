package vitalfilereplayspoolsqlite

import (
	"bytes"
	"database/sql"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumReceiptBytes = 1 << 20

type Reader struct {
	receipt   VitalFileReplaySpoolReceipt
	database  *sql.DB
	gapPolicy string
}

type storedTrack struct {
	SourceTrackID  uint16
	OutputTrackID  uint32
	Kind           guestruntimedomain.VitalFileTrackKind
	FormatCode     uint8
	Name           string
	DeviceName     string
	Unit           string
	SampleRate     float64
	MinimumDisplay float64
	MaximumDisplay float64
	Gain           float64
	Offset         float64
	MonitorType    guestruntimedomain.VitalServerMonitorType
}

func OpenReader(
	rootDirectory string,
	replayID string,
	expected VitalFileReplaySpoolReceipt,
	gapPolicy string,
) (*Reader, error) {
	if rootDirectory == "" || !filepath.IsAbs(rootDirectory) ||
		!guestruntimedomain.ValidIdentifier(replayID) ||
		expected.ReplayID != replayID ||
		(gapPolicy != GapPolicyOmitTrack && gapPolicy != GapPolicyFailFrame) {
		return nil, spoolFailure("spool-reader-input-invalid", "Vital replay spool reader input is invalid", nil)
	}
	finalDirectory := filepath.Join(rootDirectory, replayID)
	receipt, err := readReceipt(filepath.Join(finalDirectory, spoolReceiptFileName))
	if err != nil {
		return nil, err
	}
	if receipt != expected {
		return nil, spoolFailure(
			"spool-receipt-mismatch",
			"Vital replay spool receipt does not match the owner-provided receipt",
			nil,
		)
	}
	if err := validateReceipt(receipt); err != nil {
		return nil, err
	}
	databasePath := filepath.Join(finalDirectory, spoolDatabaseFileName)
	actualSHA256, actualByteSize, err := digestFile(databasePath)
	if err != nil {
		return nil, spoolFailure("spool-read-digest-failed", "digest Vital replay spool database", err)
	}
	if actualSHA256 != receipt.DatabaseSHA256 ||
		actualByteSize != receipt.DatabaseByteSize {
		return nil, spoolFailure(
			"spool-database-mismatch",
			"Vital replay spool database does not match its receipt",
			nil,
		)
	}
	database, err := sql.Open("sqlite", fmt.Sprintf("file:%s?mode=ro", databasePath))
	if err != nil {
		return nil, spoolFailure("spool-read-open-failed", "open Vital replay spool database", err)
	}
	if err := verifyDatabaseMetadata(database, receipt); err != nil {
		_ = database.Close()
		return nil, err
	}
	return &Reader{
		receipt:   receipt,
		database:  database,
		gapPolicy: gapPolicy,
	}, nil
}

func (reader *Reader) Receipt() VitalFileReplaySpoolReceipt {
	return reader.receipt
}

func (reader *Reader) Close() error {
	if reader.database == nil {
		return nil
	}
	err := reader.database.Close()
	reader.database = nil
	return err
}

func (reader *Reader) Frame(
	offsetSeconds int,
	outputTime float64,
) (VitalFileReplayFrame, error) {
	if reader.database == nil {
		return VitalFileReplayFrame{},
			spoolFailure("spool-reader-closed", "Vital replay spool reader is closed", nil)
	}
	if offsetSeconds < 0 || offsetSeconds >= reader.receipt.DurationSeconds ||
		math.IsNaN(outputTime) || math.IsInf(outputTime, 0) {
		return VitalFileReplayFrame{},
			spoolFailure("frame-input-invalid", "Vital replay frame input is invalid", nil)
	}
	tracks, err := reader.readTracks()
	if err != nil {
		return VitalFileReplayFrame{}, err
	}
	frame := VitalFileReplayFrame{
		OffsetSeconds: offsetSeconds,
		OutputTime:    outputTime,
		Tracks:        make([]VitalFileReplayFrameTrack, 0, len(tracks)),
	}
	for _, track := range tracks {
		var frameTrack *VitalFileReplayFrameTrack
		switch track.Kind {
		case guestruntimedomain.VitalFileWaveformTrack:
			frameTrack, err = reader.waveformFrame(track, offsetSeconds)
		case guestruntimedomain.VitalFileNumericTrack:
			frameTrack, err = reader.numericFrame(track, offsetSeconds)
		default:
			continue
		}
		if err != nil {
			return VitalFileReplayFrame{}, err
		}
		if frameTrack != nil {
			frame.Tracks = append(frame.Tracks, *frameTrack)
		}
	}
	if len(frame.Tracks) == 0 {
		return VitalFileReplayFrame{},
			spoolFailure("no-finite-records", "Vital replay frame has no finite records", nil)
	}
	return frame, nil
}

func (reader *Reader) readTracks() ([]storedTrack, error) {
	rows, err := reader.database.Query(`
SELECT track_id, output_track_id, kind, format_code, name, device_name,
       unit, sample_rate, minimum_display, maximum_display, gain,
       value_offset, monitor_type
FROM tracks
WHERE kind IN (?, ?)
ORDER BY output_track_id`,
		guestruntimedomain.VitalFileWaveformTrack,
		guestruntimedomain.VitalFileNumericTrack,
	)
	if err != nil {
		return nil, spoolFailure("spool-track-read-failed", "read Vital replay tracks", err)
	}
	defer rows.Close()
	tracks := make([]storedTrack, 0)
	for rows.Next() {
		var track storedTrack
		if err := rows.Scan(
			&track.SourceTrackID,
			&track.OutputTrackID,
			&track.Kind,
			&track.FormatCode,
			&track.Name,
			&track.DeviceName,
			&track.Unit,
			&track.SampleRate,
			&track.MinimumDisplay,
			&track.MaximumDisplay,
			&track.Gain,
			&track.Offset,
			&track.MonitorType,
		); err != nil {
			return nil, spoolFailure("spool-track-decode-failed", "decode Vital replay track", err)
		}
		tracks = append(tracks, track)
	}
	if err := rows.Err(); err != nil {
		return nil, spoolFailure("spool-track-read-failed", "iterate Vital replay tracks", err)
	}
	return tracks, nil
}

func (reader *Reader) waveformFrame(
	track storedTrack,
	offsetSeconds int,
) (*VitalFileReplayFrameTrack, error) {
	sampleCount := int(math.Round(track.SampleRate))
	if sampleCount < 1 ||
		sampleCount > guestruntimedomain.VitalFileMaximumReplayFrameSamples {
		return nil, spoolFailure("spool-track-invalid", "Vital replay waveform track sample rate is invalid", nil)
	}
	frameStart := reader.receipt.StartedAt + float64(offsetSeconds)
	frameEnd := frameStart + 1
	targetBegin := int(math.Round(float64(offsetSeconds) * track.SampleRate))
	targetEnd := targetBegin + sampleCount
	values := make([]float64, sampleCount)
	for index := range values {
		values[index] = math.NaN()
	}
	rows, err := reader.database.Query(`
SELECT recorded_at, sample_offset, sample_count, raw_values
FROM waveform_chunks
WHERE track_id = ?
  AND recorded_at < ?
  AND recorded_at + ((sample_offset + sample_count) / ?) > ?
ORDER BY sequence`,
		track.SourceTrackID,
		frameEnd,
		track.SampleRate,
		frameStart,
	)
	if err != nil {
		return nil, spoolFailure("spool-waveform-read-failed", "read Vital replay waveform chunks", err)
	}
	defer rows.Close()
	valueBytes := numericFormatBytes(track.FormatCode)
	if valueBytes == 0 {
		return nil, spoolFailure("spool-track-invalid", "Vital replay waveform format is invalid", nil)
	}
	for rows.Next() {
		var recordedAt float64
		var sampleOffset int
		var storedCount int
		var rawValues []byte
		if err := rows.Scan(&recordedAt, &sampleOffset, &storedCount, &rawValues); err != nil {
			return nil, spoolFailure("spool-waveform-decode-failed", "decode Vital replay waveform chunk", err)
		}
		if len(rawValues) != storedCount*valueBytes {
			return nil, spoolFailure("spool-waveform-invalid", "Vital replay waveform chunk byte size is invalid", nil)
		}
		baseIndex := int(math.Ceil((recordedAt-reader.receipt.StartedAt)*track.SampleRate)) + sampleOffset
		for index := 0; index < storedCount; index++ {
			absoluteIndex := baseIndex + index
			if absoluteIndex < targetBegin || absoluteIndex >= targetEnd {
				continue
			}
			value := decodeStoredNumeric(
				rawValues[index*valueBytes:(index+1)*valueBytes],
				track.FormatCode,
			)
			if track.FormatCode > 2 {
				value = value*track.Gain + track.Offset
			}
			if math.IsInf(value, 0) || value > 4e9 {
				value = math.NaN()
			}
			values[absoluteIndex-targetBegin] = value
		}
	}
	if err := rows.Err(); err != nil {
		return nil, spoolFailure("spool-waveform-read-failed", "iterate Vital replay waveform chunks", err)
	}
	for _, value := range values {
		if math.IsNaN(value) || math.IsInf(value, 0) {
			return reader.missingTrack(track, offsetSeconds)
		}
	}
	return &VitalFileReplayFrameTrack{
		OutputTrackID:  track.OutputTrackID,
		SourceTrackID:  track.SourceTrackID,
		Kind:           track.Kind,
		Name:           track.Name,
		DeviceName:     replayDeviceName(track.DeviceName),
		Unit:           track.Unit,
		MonitorType:    track.MonitorType,
		SampleRate:     track.SampleRate,
		MinimumDisplay: track.MinimumDisplay,
		MaximumDisplay: track.MaximumDisplay,
		WaveformValues: values,
	}, nil
}

func (reader *Reader) numericFrame(
	track storedTrack,
	offsetSeconds int,
) (*VitalFileReplayFrameTrack, error) {
	frameStart := reader.receipt.StartedAt + float64(offsetSeconds)
	frameEnd := frameStart + 1
	comparison := "<"
	if offsetSeconds == reader.receipt.DurationSeconds-1 {
		comparison = "<="
	}
	row := reader.database.QueryRow(
		fmt.Sprintf(`
SELECT value
FROM numeric_records
WHERE track_id = ? AND recorded_at >= ? AND recorded_at %s ?
ORDER BY sequence DESC
LIMIT 1`, comparison),
		track.SourceTrackID,
		frameStart,
		frameEnd,
	)
	var value float64
	if err := row.Scan(&value); err == sql.ErrNoRows {
		return reader.missingTrack(track, offsetSeconds)
	} else if err != nil {
		return nil, spoolFailure("spool-numeric-read-failed", "read Vital replay numeric record", err)
	}
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return reader.missingTrack(track, offsetSeconds)
	}
	return &VitalFileReplayFrameTrack{
		OutputTrackID: track.OutputTrackID,
		SourceTrackID: track.SourceTrackID,
		Kind:          track.Kind,
		Name:          track.Name,
		DeviceName:    replayDeviceName(track.DeviceName),
		Unit:          track.Unit,
		MonitorType:   track.MonitorType,
		NumericValue:  &value,
	}, nil
}

func (reader *Reader) missingTrack(
	track storedTrack,
	offsetSeconds int,
) (*VitalFileReplayFrameTrack, error) {
	if reader.gapPolicy == GapPolicyOmitTrack {
		return nil, nil
	}
	return nil, spoolFailure(
		"missing-track-record",
		fmt.Sprintf(
			"Vital replay track %d has no complete finite frame at offset %d",
			track.SourceTrackID,
			offsetSeconds,
		),
		nil,
	)
}

func readReceipt(path string) (VitalFileReplaySpoolReceipt, error) {
	file, err := os.Open(path)
	if err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-receipt-read-failed", "open Vital replay spool receipt", err)
	}
	defer file.Close()
	encoded, err := io.ReadAll(io.LimitReader(file, maximumReceiptBytes+1))
	if err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-receipt-read-failed", "read Vital replay spool receipt", err)
	}
	if len(encoded) > maximumReceiptBytes {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-receipt-too-large", "Vital replay spool receipt exceeds its limit", nil)
	}
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	var receipt VitalFileReplaySpoolReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-receipt-decode-failed", "decode Vital replay spool receipt", err)
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		return VitalFileReplaySpoolReceipt{},
			spoolFailure("spool-receipt-decode-failed", "Vital replay spool receipt has trailing JSON", nil)
	}
	return receipt, nil
}

func validateReceipt(receipt VitalFileReplaySpoolReceipt) error {
	if err := guestruntimedomain.ValidateVitalFileReplaySpoolReceipt(receipt); err != nil {
		return spoolFailure("spool-receipt-invalid", "Vital replay spool receipt is incomplete or invalid", nil)
	}
	return nil
}

func verifyDatabaseMetadata(
	database *sql.DB,
	receipt VitalFileReplaySpoolReceipt,
) error {
	var fileFormatVersion string
	var startedAt float64
	var endedAt float64
	var durationSeconds int
	var trackCount int
	var recordCount uint64
	var graphCompatibleSignalCount int
	var finalizedAt string
	if err := database.QueryRow(`
SELECT file_format_version, started_at, ended_at, duration_seconds,
       track_count, record_count, graph_compatible_signal_count, finalized_at
FROM scan_metadata
WHERE singleton = 1`).Scan(
		&fileFormatVersion,
		&startedAt,
		&endedAt,
		&durationSeconds,
		&trackCount,
		&recordCount,
		&graphCompatibleSignalCount,
		&finalizedAt,
	); err != nil {
		return spoolFailure("spool-metadata-read-failed", "read Vital replay spool metadata", err)
	}
	if fileFormatVersion != receipt.FileFormatVersion ||
		startedAt != receipt.StartedAt ||
		endedAt != receipt.EndedAt ||
		durationSeconds != receipt.DurationSeconds ||
		trackCount != receipt.TrackCount ||
		recordCount != receipt.RecordCount ||
		graphCompatibleSignalCount != receipt.GraphCompatibleSignalCount ||
		finalizedAt != receipt.FinalizedAt {
		return spoolFailure("spool-metadata-mismatch", "Vital replay spool metadata does not match its receipt", nil)
	}
	return nil
}

func numericFormatBytes(formatCode uint8) int {
	switch formatCode {
	case 1, 7, 8:
		return 4
	case 2:
		return 8
	case 3, 4:
		return 1
	case 5, 6:
		return 2
	default:
		return 0
	}
}

func decodeStoredNumeric(raw []byte, formatCode uint8) float64 {
	switch formatCode {
	case 1:
		return float64(math.Float32frombits(binary.LittleEndian.Uint32(raw)))
	case 2:
		return math.Float64frombits(binary.LittleEndian.Uint64(raw))
	case 3:
		return float64(int8(raw[0]))
	case 4:
		return float64(raw[0])
	case 5:
		return float64(int16(binary.LittleEndian.Uint16(raw)))
	case 6:
		return float64(binary.LittleEndian.Uint16(raw))
	case 7:
		return float64(int32(binary.LittleEndian.Uint32(raw)))
	case 8:
		return float64(binary.LittleEndian.Uint32(raw))
	default:
		panic("stored numeric format was verified")
	}
}

func replayDeviceName(deviceName string) string {
	if deviceName == "" {
		return "Vital File"
	}
	return deviceName
}
