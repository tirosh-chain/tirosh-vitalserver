package vitalfilereplayparser_test

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayparser"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type captureSink struct {
	header         guestruntimedomain.VitalFileReplayHeader
	tracks         []guestruntimedomain.VitalFileReplayTrackDefinition
	waveformChunks []guestruntimedomain.VitalFileReplayWaveformChunk
	numericRecords []guestruntimedomain.VitalFileReplayNumericRecord
	stringRecords  []guestruntimedomain.VitalFileReplayStringRecord
}

func (sink *captureSink) AcceptHeader(header guestruntimedomain.VitalFileReplayHeader) error {
	sink.header = header
	return nil
}

func (sink *captureSink) AcceptTrack(track guestruntimedomain.VitalFileReplayTrackDefinition) error {
	sink.tracks = append(sink.tracks, track)
	return nil
}

func (sink *captureSink) AcceptWaveformChunk(chunk guestruntimedomain.VitalFileReplayWaveformChunk) error {
	sink.waveformChunks = append(sink.waveformChunks, chunk)
	return nil
}

func (sink *captureSink) AcceptNumericRecord(record guestruntimedomain.VitalFileReplayNumericRecord) error {
	sink.numericRecords = append(sink.numericRecords, record)
	return nil
}

func (sink *captureSink) AcceptStringRecord(record guestruntimedomain.VitalFileReplayStringRecord) error {
	sink.stringRecords = append(sink.stringRecords, record)
	return nil
}

func TestParserDecodesV1ThroughV3AndPreservesNumericZeroSampleRate(t *testing.T) {
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	corpus := []struct {
		version      uint32
		contractName string
		sha256       string
		expectedName string
	}{
		{1, "vital-v1", "f9dc67d48cd3aee653c90ec499522ec58e3b5d1db2101d918f5d308b510523f9", "synthetic-v1.vital.base64"},
		{2, "vital-v2", "f904fa7f0ba362370c028dde25dd0ee3b1a34ba99f9a8395bc527dff03adf49a", "synthetic-v2.vital.base64"},
		{3, "vital-v3", "800136c7fc650dbfa002a8f3ad43efc7aaebfe3a8b7fcb51e8314164cd7444eb", "synthetic-v3.vital.base64"},
	}
	for _, fixture := range corpus {
		source := readFrozenVitalFixture(t, fixture.expectedName, fixture.sha256)
		decision, err := parser.Decode(bytes.NewReader(source))
		if err != nil {
			t.Fatalf("version %d: %v", fixture.version, err)
		}
		if decision.FileFormatVersion != fixture.contractName ||
			decision.Tracks[1].Kind != guestruntimedomain.VitalFileNumericTrack ||
			decision.Tracks[1].SampleRate != 0 ||
			decision.GraphCompatibleSignalCount != 2 {
			t.Fatalf("version %d decision = %+v", fixture.version, decision)
		}
	}
}

func readFrozenVitalFixture(t *testing.T, name string, expectedSHA256 string) []byte {
	t.Helper()
	encoded, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	source, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(encoded)))
	if err != nil {
		t.Fatalf("decode fixture %s: %v", name, err)
	}
	actual := fmt.Sprintf("%x", sha256.Sum256(source))
	if actual != expectedSHA256 {
		t.Fatalf("fixture %s sha256 = %s, want %s", name, actual, expectedSHA256)
	}
	return source
}

func TestParserReportsTypedDecodeFailures(t *testing.T) {
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	for name, source := range map[string][]byte{
		"not-gzip": []byte("not-gzip"),
		"truncated-packet": vitalSource(
			t,
			3,
			[]byte{0, 20, 0, 0, 0, 1},
		),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := parser.Decode(bytes.NewReader(source))
			var failure vitalfilereplayparser.VitalFileReplayDecodeFailure
			if !errors.As(err, &failure) || failure.Code == "" {
				t.Fatalf("decode failure = %#v", err)
			}
		})
	}
}

func TestParserRejectsFutureFormatWithoutFallback(t *testing.T) {
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = parser.Decode(bytes.NewReader(vitalSource(
		t,
		4,
		trackPacket(
			t,
			1,
			uint8(guestruntimedomain.VitalFileNumericTrack),
			1,
			"HR",
			0,
			uint8(guestruntimedomain.VitalServerMonitorECGHeartRate),
		),
	)))
	var failure guestruntimedomain.VitalFileReplayCompatibilityFailure
	if !errors.As(err, &failure) || failure.Code != "unsupported-format-version" {
		t.Fatalf("compatibility failure = %#v", err)
	}
}

func TestScannerStreamsBoundedWaveformChunksAndTimestampedNumericRecords(t *testing.T) {
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	const sampleCount = 20000
	waveform := make([]byte, 4+sampleCount*4)
	binary.LittleEndian.PutUint32(waveform[:4], sampleCount)
	for index := 0; index < sampleCount; index++ {
		binary.LittleEndian.PutUint32(
			waveform[4+index*4:],
			math.Float32bits(float32(index)),
		)
	}
	var numeric bytes.Buffer
	_ = binary.Write(&numeric, binary.LittleEndian, float32(72))
	var stringValue bytes.Buffer
	_ = binary.Write(&stringValue, binary.LittleEndian, uint32(0))
	writeString(t, &stringValue, "ready")
	sink := &captureSink{}
	result, err := parser.Scan(
		bytes.NewReader(vitalSource(
			t,
			3,
			trackPacket(t, 1, uint8(guestruntimedomain.VitalFileWaveformTrack), 1, "PLETH", 500, uint8(guestruntimedomain.VitalServerMonitorPlethWaveform)),
			trackPacket(t, 2, uint8(guestruntimedomain.VitalFileNumericTrack), 1, "PLETH_HR", 0, uint8(guestruntimedomain.VitalServerMonitorPlethHeartRate)),
			trackPacket(t, 3, uint8(guestruntimedomain.VitalFileStringTrack), 0, "LABEL", 0, 0),
			recordPacket(t, 1, 100, waveform),
			recordPacket(t, 2, 101, numeric.Bytes()),
			recordPacket(t, 3, 102, stringValue.Bytes()),
		)),
		sink,
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(sink.waveformChunks) != 2 ||
		sink.waveformChunks[0].SampleCount != 16384 ||
		sink.waveformChunks[1].SampleOffset != 16384 ||
		sink.waveformChunks[1].SampleCount != 3616 {
		t.Fatalf("waveform chunks = %+v", sink.waveformChunks)
	}
	if len(sink.numericRecords) != 1 ||
		sink.numericRecords[0].RecordedAt != 101 ||
		sink.numericRecords[0].Value != 72 {
		t.Fatalf("numeric records = %+v", sink.numericRecords)
	}
	if len(sink.stringRecords) != 1 || sink.stringRecords[0].Value != "ready" {
		t.Fatalf("string records = %+v", sink.stringRecords)
	}
	startedAt, endedAt, err := result.TimeRange()
	if err != nil {
		t.Fatal(err)
	}
	if startedAt != 100 || endedAt != 140 || result.RecordCount != 3 {
		t.Fatalf("scan result = %+v range=%f..%f", result, startedAt, endedAt)
	}
}

func TestScannerReturnsSinkFailureWithoutConvertingItToDecodeSuccess(t *testing.T) {
	parser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	expected := errors.New("spool unavailable")
	_, err = parser.Scan(
		bytes.NewReader(vitalSource(
			t,
			3,
			trackPacket(t, 1, uint8(guestruntimedomain.VitalFileNumericTrack), 1, "HR", 0, uint8(guestruntimedomain.VitalServerMonitorECGHeartRate)),
		)),
		failingSink{err: expected},
	)
	if !errors.Is(err, expected) {
		t.Fatalf("sink failure = %v", err)
	}
}

type failingSink struct{ err error }

func (sink failingSink) AcceptHeader(guestruntimedomain.VitalFileReplayHeader) error {
	return sink.err
}
func (failingSink) AcceptTrack(guestruntimedomain.VitalFileReplayTrackDefinition) error {
	return nil
}
func (failingSink) AcceptWaveformChunk(guestruntimedomain.VitalFileReplayWaveformChunk) error {
	return nil
}
func (failingSink) AcceptNumericRecord(guestruntimedomain.VitalFileReplayNumericRecord) error {
	return nil
}
func (failingSink) AcceptStringRecord(guestruntimedomain.VitalFileReplayStringRecord) error {
	return nil
}

func vitalSource(t *testing.T, version uint32, packets ...[]byte) []byte {
	t.Helper()
	var decompressed bytes.Buffer
	decompressed.WriteString("VITA")
	_ = binary.Write(&decompressed, binary.LittleEndian, version)
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

func trackPacket(
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
	writeString(t, &payload, name)
	writeString(t, &payload, "")
	_ = binary.Write(&payload, binary.LittleEndian, float32(0))
	_ = binary.Write(&payload, binary.LittleEndian, float32(0))
	_ = binary.Write(&payload, binary.LittleEndian, uint32(0))
	_ = binary.Write(&payload, binary.LittleEndian, sampleRate)
	_ = binary.Write(&payload, binary.LittleEndian, float64(0))
	_ = binary.Write(&payload, binary.LittleEndian, float64(0))
	payload.WriteByte(monitorType)
	_ = binary.Write(&payload, binary.LittleEndian, uint32(0))
	var packet bytes.Buffer
	packet.WriteByte(0)
	_ = binary.Write(&packet, binary.LittleEndian, uint32(payload.Len()))
	packet.Write(payload.Bytes())
	return packet.Bytes()
}

func recordPacket(
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
	var packet bytes.Buffer
	packet.WriteByte(1)
	_ = binary.Write(&packet, binary.LittleEndian, uint32(payload.Len()))
	packet.Write(payload.Bytes())
	return packet.Bytes()
}

func writeString(t *testing.T, target *bytes.Buffer, value string) {
	t.Helper()
	if err := binary.Write(target, binary.LittleEndian, uint32(len(value))); err != nil {
		t.Fatal(err)
	}
	target.WriteString(value)
}
