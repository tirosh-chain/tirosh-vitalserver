package vitalfilereplayparser

import (
	"compress/gzip"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"unicode/utf8"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	vitalHeaderPrefixBytes     = 10
	vitalBaseHeaderBytes       = 10
	vitalPacketHeaderBytes     = 5
	maximumMetadataPacketBytes = 1 << 20
	recordChunkBytes           = 64 << 10
)

type VitalFileReplayParser struct {
	policy guestruntimedomain.VitalFileReplayCompatibilityPolicy
}

type VitalFileReplayDecodeFailure struct {
	Code    string
	Message string
}

func (failure VitalFileReplayDecodeFailure) Error() string {
	return failure.Message
}

func (failure VitalFileReplayDecodeFailure) ReplayFailureCode() string {
	return failure.Code
}

func NewVitalFileReplayParser(
	policy guestruntimedomain.VitalFileReplayCompatibilityPolicy,
) (*VitalFileReplayParser, error) {
	if policy.StringTrackPolicy != guestruntimedomain.VitalFileStringTrackPolicyReject &&
		policy.StringTrackPolicy != guestruntimedomain.VitalFileStringTrackPolicySkip {
		return nil, fmt.Errorf("Vital file string track policy is invalid")
	}
	return &VitalFileReplayParser{policy: policy}, nil
}

func (parser *VitalFileReplayParser) Decode(
	source io.Reader,
) (guestruntimedomain.VitalFileReplayCompatibilityDecision, error) {
	result, err := parser.Scan(source, nil)
	if err != nil {
		return guestruntimedomain.VitalFileReplayCompatibilityDecision{}, err
	}
	return result.Compatibility, nil
}

func (parser *VitalFileReplayParser) Probe(
	source io.Reader,
) (guestruntimedomain.VitalFileReplayHeader, error) {
	if source == nil {
		return guestruntimedomain.VitalFileReplayHeader{},
			decodeFailure("source-unavailable", "Vital file source is unavailable")
	}
	stream, err := gzip.NewReader(source)
	if err != nil {
		return guestruntimedomain.VitalFileReplayHeader{},
			decodeFailure("decode-failed", "Vital file gzip header is invalid")
	}
	defer stream.Close()
	header, err := decodeHeader(stream)
	if err != nil {
		return guestruntimedomain.VitalFileReplayHeader{}, err
	}
	if _, supported := header.FormatVersion.ReplayContractName(); !supported {
		return guestruntimedomain.VitalFileReplayHeader{},
			guestruntimedomain.VitalFileReplayCompatibilityFailure{
				Code:    "unsupported-format-version",
				Message: "Vital file format version is unsupported (unsupported-format-version)",
			}
	}
	return header, nil
}

// Scan decodes one gzip .vital stream with bounded metadata and waveform
// chunk buffers. The sink owns persistence; scanner errors never imply that a
// partial sink is committed.
func (parser *VitalFileReplayParser) Scan(
	source io.Reader,
	sink guestruntimeapplication.GuestRuntimeVitalFileReplayRecordSink,
) (guestruntimedomain.VitalFileReplayScanResult, error) {
	if source == nil {
		return guestruntimedomain.VitalFileReplayScanResult{},
			decodeFailure("source-unavailable", "Vital file source is unavailable")
	}
	stream, err := gzip.NewReader(source)
	if err != nil {
		return guestruntimedomain.VitalFileReplayScanResult{},
			decodeFailure("decode-failed", "Vital file gzip header is invalid")
	}
	defer stream.Close()
	header, err := decodeHeader(stream)
	if err != nil {
		return guestruntimedomain.VitalFileReplayScanResult{}, err
	}
	if _, supported := header.FormatVersion.ReplayContractName(); !supported {
		return guestruntimedomain.VitalFileReplayScanResult{},
			guestruntimedomain.VitalFileReplayCompatibilityFailure{
				Code:    "unsupported-format-version",
				Message: "Vital file format version is unsupported (unsupported-format-version)",
			}
	}
	if sink != nil {
		if err := sink.AcceptHeader(header); err != nil {
			return guestruntimedomain.VitalFileReplayScanResult{}, err
		}
	}
	scan, err := scanPackets(stream, sink)
	if err != nil {
		return guestruntimedomain.VitalFileReplayScanResult{}, err
	}
	compatibility, err := guestruntimedomain.EvaluateVitalFileReplayCompatibility(
		parser.policy,
		guestruntimedomain.VitalFileReplayManifest{
			FormatVersion: header.FormatVersion,
			Tracks:        scan.trackMetadata,
		},
	)
	if err != nil {
		return guestruntimedomain.VitalFileReplayScanResult{}, err
	}
	return guestruntimedomain.VitalFileReplayScanResult{
		Compatibility: compatibility,
		Header:        header,
		ObservedStart: scan.observedStart,
		ObservedEnd:   scan.observedEnd,
		RecordCount:   scan.recordCount,
	}, nil
}

func decodeHeader(stream io.Reader) (guestruntimedomain.VitalFileReplayHeader, error) {
	prefix := make([]byte, vitalHeaderPrefixBytes)
	if err := readExact(stream, prefix, "truncated-header"); err != nil {
		return guestruntimedomain.VitalFileReplayHeader{}, err
	}
	if string(prefix[:4]) != "VITA" {
		return guestruntimedomain.VitalFileReplayHeader{}, decodeFailure(
			"invalid-magic",
			"Vital file stream does not begin with VITA",
		)
	}
	formatVersion := guestruntimedomain.VitalFileFormatVersion(
		binary.LittleEndian.Uint32(prefix[4:8]),
	)
	headerLength := int(binary.LittleEndian.Uint16(prefix[8:10]))
	if headerLength < vitalBaseHeaderBytes {
		return guestruntimedomain.VitalFileReplayHeader{}, decodeFailure(
			"invalid-header-length",
			"Vital file header is shorter than the base header",
		)
	}
	headerBody := make([]byte, headerLength)
	if err := readExact(stream, headerBody, "truncated-header"); err != nil {
		return guestruntimedomain.VitalFileReplayHeader{}, err
	}
	header := guestruntimedomain.VitalFileReplayHeader{FormatVersion: formatVersion}
	if headerLength >= 26 {
		startedAt := math.Float64frombits(binary.LittleEndian.Uint64(headerBody[10:18]))
		endedAt := math.Float64frombits(binary.LittleEndian.Uint64(headerBody[18:26]))
		if !finite(startedAt) || !finite(endedAt) {
			return guestruntimedomain.VitalFileReplayHeader{}, decodeFailure(
				"invalid-header-time",
				"Vital file header timestamps are not finite",
			)
		}
		header.StartedAt = &startedAt
		header.EndedAt = &endedAt
	}
	if headerLength >= 27 && headerBody[26] > 1 {
		return guestruntimedomain.VitalFileReplayHeader{}, decodeFailure(
			"invalid-packed-flag",
			"Vital file packed flag is not 0 or 1",
		)
	}
	return header, nil
}

type vitalPacketScan struct {
	trackMetadata []guestruntimedomain.VitalFileReplayTrackMetadata
	observedStart *float64
	observedEnd   *float64
	recordCount   uint64
}

type vitalWireTrack struct {
	definition guestruntimedomain.VitalFileReplayTrackDefinition
	valueBytes int
}

func scanPackets(
	stream io.Reader,
	sink guestruntimeapplication.GuestRuntimeVitalFileReplayRecordSink,
) (vitalPacketScan, error) {
	scan := vitalPacketScan{
		trackMetadata: make([]guestruntimedomain.VitalFileReplayTrackMetadata, 0),
	}
	devices := make(map[uint32]string)
	tracks := make(map[uint16]vitalWireTrack)
	packetHeader := make([]byte, vitalPacketHeaderBytes)
	for {
		readCount, err := io.ReadFull(stream, packetHeader)
		if err == io.EOF && readCount == 0 {
			return scan, nil
		}
		if err != nil {
			return vitalPacketScan{}, decodeFailure(
				"truncated-packet",
				"Vital file packet header is truncated",
			)
		}
		packetType := packetHeader[0]
		packetLength := int64(binary.LittleEndian.Uint32(packetHeader[1:5]))
		switch packetType {
		case 0:
			if packetLength > maximumMetadataPacketBytes {
				return vitalPacketScan{}, decodeFailure(
					"invalid-track-metadata",
					"Vital file track metadata exceeds the explicit limit",
				)
			}
			payload := make([]byte, packetLength)
			if err := readExact(stream, payload, "truncated-packet"); err != nil {
				return vitalPacketScan{}, err
			}
			track, err := decodeTrackDefinition(payload, devices)
			if err != nil {
				return vitalPacketScan{}, err
			}
			if _, exists := tracks[track.definition.TrackID]; exists {
				return vitalPacketScan{}, decodeFailure(
					"invalid-track-metadata",
					"Vital file contains a duplicate track identifier",
				)
			}
			tracks[track.definition.TrackID] = track
			scan.trackMetadata = append(
				scan.trackMetadata,
				guestruntimedomain.VitalFileReplayTrackMetadata{
					TrackID:     track.definition.TrackID,
					Kind:        track.definition.Kind,
					SampleRate:  track.definition.SampleRate,
					MonitorType: track.definition.MonitorType,
				},
			)
			if sink != nil {
				if err := sink.AcceptTrack(track.definition); err != nil {
					return vitalPacketScan{}, err
				}
			}
		case 1:
			if err := scanRecord(
				stream,
				packetLength,
				tracks,
				sink,
				&scan,
			); err != nil {
				return vitalPacketScan{}, err
			}
		case 9:
			if packetLength > maximumMetadataPacketBytes {
				return vitalPacketScan{}, decodeFailure(
					"invalid-device-metadata",
					"Vital file device metadata exceeds the explicit limit",
				)
			}
			payload := make([]byte, packetLength)
			if err := readExact(stream, payload, "truncated-packet"); err != nil {
				return vitalPacketScan{}, err
			}
			deviceID, deviceName, err := decodeDeviceDefinition(payload)
			if err != nil {
				return vitalPacketScan{}, err
			}
			devices[deviceID] = deviceName
		default:
			if err := discardExact(stream, packetLength); err != nil {
				return vitalPacketScan{}, err
			}
		}
	}
}

func scanRecord(
	stream io.Reader,
	packetLength int64,
	tracks map[uint16]vitalWireTrack,
	sink guestruntimeapplication.GuestRuntimeVitalFileReplayRecordSink,
	scan *vitalPacketScan,
) error {
	if packetLength < 12 {
		if err := discardExact(stream, packetLength); err != nil {
			return err
		}
		return decodeFailure("invalid-record", "Vital file record packet is too short")
	}
	infoLengthBytes := make([]byte, 2)
	if err := readExact(stream, infoLengthBytes, "truncated-packet"); err != nil {
		return err
	}
	infoLength := int64(binary.LittleEndian.Uint16(infoLengthBytes))
	remaining := packetLength - 2
	if infoLength < 10 || infoLength > remaining {
		if err := discardExact(stream, remaining); err != nil {
			return err
		}
		return decodeFailure("invalid-record", "Vital file record info length is invalid")
	}
	info := make([]byte, infoLength)
	if err := readExact(stream, info, "truncated-packet"); err != nil {
		return err
	}
	remaining -= infoLength
	recordedAt := math.Float64frombits(binary.LittleEndian.Uint64(info[:8]))
	trackID := binary.LittleEndian.Uint16(info[8:10])
	if !finite(recordedAt) {
		if err := discardExact(stream, remaining); err != nil {
			return err
		}
		return decodeFailure("invalid-record", "Vital file record timestamp is not finite")
	}
	track, exists := tracks[trackID]
	if !exists {
		return discardExact(stream, remaining)
	}
	scan.observe(recordedAt)
	scan.recordCount++
	switch track.definition.Kind {
	case guestruntimedomain.VitalFileWaveformTrack:
		return scanWaveformRecord(
			stream,
			remaining,
			recordedAt,
			track,
			sink,
			scan,
		)
	case guestruntimedomain.VitalFileNumericTrack:
		if remaining != int64(track.valueBytes) {
			if err := discardExact(stream, remaining); err != nil {
				return err
			}
			return decodeFailure(
				"invalid-record",
				"Vital numeric record length does not match its format",
			)
		}
		rawValue := make([]byte, track.valueBytes)
		if err := readExact(stream, rawValue, "truncated-packet"); err != nil {
			return err
		}
		value := decodeNumericValue(rawValue, track.definition.FormatCode)
		if sink != nil {
			return sink.AcceptNumericRecord(guestruntimedomain.VitalFileReplayNumericRecord{
				TrackID:    trackID,
				RecordedAt: recordedAt,
				Value:      value,
			})
		}
		return nil
	case guestruntimedomain.VitalFileStringTrack:
		return scanStringRecord(stream, remaining, recordedAt, trackID, sink)
	default:
		return discardExact(stream, remaining)
	}
}

func scanWaveformRecord(
	stream io.Reader,
	remaining int64,
	recordedAt float64,
	track vitalWireTrack,
	sink guestruntimeapplication.GuestRuntimeVitalFileReplayRecordSink,
	scan *vitalPacketScan,
) error {
	if remaining < 4 {
		if err := discardExact(stream, remaining); err != nil {
			return err
		}
		return decodeFailure(
			"invalid-record",
			"Vital waveform record has no sample count",
		)
	}
	sampleCountBytes := make([]byte, 4)
	if err := readExact(stream, sampleCountBytes, "truncated-packet"); err != nil {
		return err
	}
	sampleCount := binary.LittleEndian.Uint32(sampleCountBytes)
	remaining -= 4
	expected := int64(sampleCount) * int64(track.valueBytes)
	if remaining != expected {
		if err := discardExact(stream, remaining); err != nil {
			return err
		}
		return decodeFailure(
			"invalid-record",
			"Vital waveform record length does not match its sample count",
		)
	}
	samplesPerChunk := uint32(recordChunkBytes / track.valueBytes)
	if samplesPerChunk < 1 {
		samplesPerChunk = 1
	}
	for sampleOffset := uint32(0); sampleOffset < sampleCount; {
		chunkCount := samplesPerChunk
		if remainingSamples := sampleCount - sampleOffset; remainingSamples < chunkCount {
			chunkCount = remainingSamples
		}
		rawValues := make([]byte, int(chunkCount)*track.valueBytes)
		if err := readExact(stream, rawValues, "truncated-packet"); err != nil {
			return err
		}
		if sink != nil {
			if err := sink.AcceptWaveformChunk(guestruntimedomain.VitalFileReplayWaveformChunk{
				TrackID:      track.definition.TrackID,
				RecordedAt:   recordedAt,
				SampleOffset: sampleOffset,
				SampleCount:  chunkCount,
				RawValues:    rawValues,
			}); err != nil {
				return err
			}
		}
		sampleOffset += chunkCount
	}
	if track.definition.SampleRate > 0 {
		scan.observe(recordedAt + float64(sampleCount)/track.definition.SampleRate)
	}
	return nil
}

func scanStringRecord(
	stream io.Reader,
	remaining int64,
	recordedAt float64,
	trackID uint16,
	sink guestruntimeapplication.GuestRuntimeVitalFileReplayRecordSink,
) error {
	if remaining < 8 {
		if err := discardExact(stream, remaining); err != nil {
			return err
		}
		return decodeFailure("invalid-record", "Vital string record is too short")
	}
	prefix := make([]byte, 8)
	if err := readExact(stream, prefix, "truncated-packet"); err != nil {
		return err
	}
	stringLength := int64(binary.LittleEndian.Uint32(prefix[4:8]))
	remaining -= 8
	if remaining != stringLength {
		if err := discardExact(stream, remaining); err != nil {
			return err
		}
		return decodeFailure("invalid-record", "Vital string record length is invalid")
	}
	encoded := make([]byte, stringLength)
	if err := readExact(stream, encoded, "truncated-packet"); err != nil {
		return err
	}
	if !utf8.Valid(encoded) {
		return decodeFailure("invalid-record", "Vital string record is not UTF-8")
	}
	if sink != nil {
		return sink.AcceptStringRecord(guestruntimedomain.VitalFileReplayStringRecord{
			TrackID:    trackID,
			RecordedAt: recordedAt,
			Value:      string(encoded),
		})
	}
	return nil
}

func (scan *vitalPacketScan) observe(timestamp float64) {
	if scan.observedStart == nil || timestamp < *scan.observedStart {
		value := timestamp
		scan.observedStart = &value
	}
	if scan.observedEnd == nil || timestamp > *scan.observedEnd {
		value := timestamp
		scan.observedEnd = &value
	}
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func readExact(reader io.Reader, target []byte, code string) error {
	if _, err := io.ReadFull(reader, target); err != nil {
		return decodeFailure(code, "Vital file stream is truncated")
	}
	return nil
}

func discardExact(reader io.Reader, size int64) error {
	buffer := make([]byte, recordChunkBytes)
	for size > 0 {
		chunkSize := int64(len(buffer))
		if size < chunkSize {
			chunkSize = size
		}
		if _, err := io.ReadFull(reader, buffer[:chunkSize]); err != nil {
			return decodeFailure(
				"truncated-packet",
				"Vital file packet payload is truncated",
			)
		}
		size -= chunkSize
	}
	return nil
}

func decodeFailure(code string, message string) VitalFileReplayDecodeFailure {
	return VitalFileReplayDecodeFailure{
		Code:    code,
		Message: fmt.Sprintf("%s (%s)", message, code),
	}
}

var _ guestruntimeapplication.GuestRuntimeVitalFileReplayParser = (*VitalFileReplayParser)(nil)
