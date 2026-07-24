package vitalfilereplayspoolsqlite_test

import (
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"errors"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayparser"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayspoolsqlite"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestScannerSpoolAndReaderPreserveTwoSecondWaveformAndNumericFrames(t *testing.T) {
	parser := replayParser(t)
	root := t.TempDir()
	writer, err := vitalfilereplayspoolsqlite.NewWriter(root, "replay-1")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = writer.Abort() })
	result, err := parser.Scan(
		bytes.NewReader(twoSecondVitalSource(t, true)),
		writer,
	)
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := writer.Commit(result, "2026-07-24T18:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.DurationSeconds != 2 ||
		receipt.RecordCount != 4 ||
		receipt.GraphCompatibleSignalCount != 2 {
		t.Fatalf("receipt = %+v", receipt)
	}
	reader, err := vitalfilereplayspoolsqlite.OpenReader(
		root,
		"replay-1",
		receipt,
		vitalfilereplayspoolsqlite.GapPolicyFailFrame,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	first, err := reader.Frame(0, 1000)
	if err != nil {
		t.Fatal(err)
	}
	second, err := reader.Frame(1, 1001)
	if err != nil {
		t.Fatal(err)
	}
	assertFrame(t, first, []float64{1, 2}, 70)
	assertFrame(t, second, []float64{3, 4}, 71)
}

func TestReaderGapPolicyAndReceiptVerificationAreExplicit(t *testing.T) {
	parser := replayParser(t)
	root := t.TempDir()
	writer, err := vitalfilereplayspoolsqlite.NewWriter(root, "replay-gap")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = writer.Abort() })
	result, err := parser.Scan(
		bytes.NewReader(twoSecondVitalSource(t, false)),
		writer,
	)
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := writer.Commit(result, "2026-07-24T18:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	failReader, err := vitalfilereplayspoolsqlite.OpenReader(
		root,
		"replay-gap",
		receipt,
		vitalfilereplayspoolsqlite.GapPolicyFailFrame,
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = failReader.Frame(1, 1001)
	_ = failReader.Close()
	var failure vitalfilereplayspoolsqlite.VitalFileReplaySpoolFailure
	if !errors.As(err, &failure) || failure.Code != "missing-track-record" {
		t.Fatalf("missing record failure = %#v", err)
	}
	omitReader, err := vitalfilereplayspoolsqlite.OpenReader(
		root,
		"replay-gap",
		receipt,
		vitalfilereplayspoolsqlite.GapPolicyOmitTrack,
	)
	if err != nil {
		t.Fatal(err)
	}
	frame, err := omitReader.Frame(1, 1001)
	_ = omitReader.Close()
	if err != nil {
		t.Fatal(err)
	}
	if len(frame.Tracks) != 1 ||
		frame.Tracks[0].Kind != guestruntimedomain.VitalFileWaveformTrack {
		t.Fatalf("omit-track frame = %+v", frame)
	}

	databasePath := filepath.Join(root, "replay-gap", "replay.sqlite")
	file, err := os.OpenFile(databasePath, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := file.Write([]byte("tamper")); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	_, err = vitalfilereplayspoolsqlite.OpenReader(
		root,
		"replay-gap",
		receipt,
		vitalfilereplayspoolsqlite.GapPolicyOmitTrack,
	)
	if !errors.As(err, &failure) || failure.Code != "spool-database-mismatch" {
		t.Fatalf("tamper failure = %#v", err)
	}
}

func replayParser(t *testing.T) *vitalfilereplayparser.VitalFileReplayParser {
	t.Helper()
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	return parser
}

func twoSecondVitalSource(t *testing.T, includeSecondNumeric bool) []byte {
	t.Helper()
	waveform := make([]byte, 4+4*4)
	binary.LittleEndian.PutUint32(waveform[:4], 4)
	for index, value := range []float32{1, 2, 3, 4} {
		binary.LittleEndian.PutUint32(
			waveform[4+index*4:],
			math.Float32bits(value),
		)
	}
	firstNumeric := make([]byte, 4)
	secondNumeric := make([]byte, 4)
	binary.LittleEndian.PutUint32(firstNumeric, math.Float32bits(70))
	binary.LittleEndian.PutUint32(secondNumeric, math.Float32bits(71))
	packets := [][]byte{
		spoolTrackPacket(t, 1, uint8(guestruntimedomain.VitalFileWaveformTrack), 1, "PLETH", 2, uint8(guestruntimedomain.VitalServerMonitorPlethWaveform)),
		spoolTrackPacket(t, 2, uint8(guestruntimedomain.VitalFileNumericTrack), 1, "PLETH_HR", 0, uint8(guestruntimedomain.VitalServerMonitorPlethHeartRate)),
		spoolTrackPacket(t, 3, uint8(guestruntimedomain.VitalFileStringTrack), 0, "LABEL", 0, 0),
		spoolRecordPacket(t, 1, 100, waveform),
		spoolRecordPacket(t, 2, 100, firstNumeric),
		spoolStringRecordPacket(t, 3, 100, "ready"),
	}
	if includeSecondNumeric {
		packets = append(packets, spoolRecordPacket(t, 2, 101, secondNumeric))
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

func spoolTrackPacket(
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
	spoolString(t, &payload, name)
	spoolString(t, &payload, "")
	_ = binary.Write(&payload, binary.LittleEndian, float32(0))
	_ = binary.Write(&payload, binary.LittleEndian, float32(100))
	_ = binary.Write(&payload, binary.LittleEndian, uint32(0))
	_ = binary.Write(&payload, binary.LittleEndian, sampleRate)
	_ = binary.Write(&payload, binary.LittleEndian, float64(0))
	_ = binary.Write(&payload, binary.LittleEndian, float64(0))
	payload.WriteByte(monitorType)
	_ = binary.Write(&payload, binary.LittleEndian, uint32(0))
	return spoolPacket(0, payload.Bytes())
}

func spoolRecordPacket(
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
	return spoolPacket(1, payload.Bytes())
}

func spoolStringRecordPacket(
	t *testing.T,
	trackID uint16,
	recordedAt float64,
	value string,
) []byte {
	t.Helper()
	var encoded bytes.Buffer
	_ = binary.Write(&encoded, binary.LittleEndian, uint32(0))
	spoolString(t, &encoded, value)
	return spoolRecordPacket(t, trackID, recordedAt, encoded.Bytes())
}

func spoolPacket(kind uint8, payload []byte) []byte {
	var packet bytes.Buffer
	packet.WriteByte(kind)
	_ = binary.Write(&packet, binary.LittleEndian, uint32(len(payload)))
	packet.Write(payload)
	return packet.Bytes()
}

func spoolString(t *testing.T, target *bytes.Buffer, value string) {
	t.Helper()
	if err := binary.Write(target, binary.LittleEndian, uint32(len(value))); err != nil {
		t.Fatal(err)
	}
	target.WriteString(value)
}

func assertFrame(
	t *testing.T,
	frame vitalfilereplayspoolsqlite.VitalFileReplayFrame,
	waveform []float64,
	numeric float64,
) {
	t.Helper()
	if len(frame.Tracks) != 2 {
		t.Fatalf("frame tracks = %+v", frame.Tracks)
	}
	if !equalFloatSlices(frame.Tracks[0].WaveformValues, waveform) {
		t.Fatalf("waveform = %+v", frame.Tracks[0].WaveformValues)
	}
	if frame.Tracks[1].NumericValue == nil ||
		*frame.Tracks[1].NumericValue != numeric ||
		frame.Tracks[1].SampleRate != 0 {
		t.Fatalf("numeric = %+v", frame.Tracks[1])
	}
}

func equalFloatSlices(left []float64, right []float64) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
