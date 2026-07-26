// Package vitalartifactformation adapts one finalized Recorder Gateway packet
// sequence into a VitalDB-compatible .vital media object.  It owns decoding
// the documented Lab recorder frame format and the binary format boundary; it
// does not read Gateway state, decide Lab lifecycle, upload, or index an
// artifact.
package vitalartifactformation

import (
	"bytes"
	"compress/gzip"
	"compress/zlib"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"
)

const VitalMediaType = "application/x-vital"

// RecorderColdPathVitalArtifactFormatter converts only the durable JSONL
// representation defined by Recorder Gateway.  It does not accept a file
// name, logs, or an arbitrary payload as a substitute for finalization.
type RecorderColdPathVitalArtifactFormatter struct{}

// FormVitalArtifact returns gzip-compressed VitalDB v3 bytes with the legacy
// ten-byte header layout that the bundled VitalServer parser accepts.  Every
// accepted raw packet must decode to a Lab frame; an invalid packet is a
// formation failure, never an empty successful artifact.
func (RecorderColdPathVitalArtifactFormatter) FormVitalArtifact(packetSequence []byte) ([]byte, error) {
	frames, err := decodeRecorderColdPathFrames(packetSequence)
	if err != nil {
		return nil, err
	}
	tracks, err := collectVitalTracks(frames)
	if err != nil {
		return nil, err
	}
	if len(tracks) == 0 {
		return nil, fmt.Errorf("finalized Recorder Gateway packet sequence has no exportable Vital tracks")
	}
	return encodeLegacyVitalArtifact(tracks)
}

type coldPathPacketLine struct {
	IngressReceiptID string `json:"ingressReceiptId"`
	PacketID         string `json:"packetId"`
	ReceivedAt       string `json:"receivedAt"`
	PayloadEncoding  string `json:"payloadEncoding"`
	PayloadBase64    string `json:"payloadBase64"`
}

type labFrame struct {
	Rooms map[string]labRoom `json:"rooms"`
}

type labRoom struct {
	RoomName string     `json:"roomname"`
	Tracks   []labTrack `json:"trks"`
}

type labTrack struct {
	Name       string           `json:"name"`
	Device     string           `json:"dname"`
	Kind       string           `json:"type"`
	Monitor    string           `json:"montype"`
	SampleRate float64          `json:"srate"`
	Unit       string           `json:"unit"`
	Minimum    float64          `json:"mindisp"`
	Maximum    float64          `json:"maxdisp"`
	Records    []labTrackRecord `json:"recs"`
}

type labTrackRecord struct {
	At    float64         `json:"dt"`
	Value json.RawMessage `json:"val"`
}

func decodeRecorderColdPathFrames(packetSequence []byte) ([]labFrame, error) {
	lines := bytes.Split(packetSequence, []byte{'\n'})
	frames := make([]labFrame, 0, len(lines))
	for index, line := range lines {
		if len(line) == 0 {
			continue
		}
		var packet coldPathPacketLine
		if err := json.Unmarshal(line, &packet); err != nil {
			return nil, fmt.Errorf("decode finalized cold-path packet line %d: %w", index+1, err)
		}
		if packet.PayloadBase64 == "" || (packet.PayloadEncoding != "binary" && packet.PayloadEncoding != "binary-string") {
			return nil, fmt.Errorf("finalized cold-path packet line %d has no supported Recorder payload", index+1)
		}
		encodedPayload, err := base64.StdEncoding.DecodeString(packet.PayloadBase64)
		if err != nil {
			return nil, fmt.Errorf("decode finalized cold-path packet payload %d: %w", index+1, err)
		}
		payload, err := decodeLabFramePayload(encodedPayload)
		if err != nil {
			return nil, fmt.Errorf("decode finalized cold-path packet payload %d: %w", index+1, err)
		}
		frames = append(frames, payload)
	}
	if len(frames) == 0 {
		return nil, fmt.Errorf("finalized Recorder Gateway packet sequence is empty")
	}
	return frames, nil
}

func decodeLabFramePayload(payload []byte) (labFrame, error) {
	frame, err := decodeJSONLabFrame(payload)
	if err == nil {
		return frame, nil
	}
	reader, zlibError := zlib.NewReader(bytes.NewReader(payload))
	if zlibError != nil {
		return labFrame{}, fmt.Errorf("payload is neither JSON nor zlib-compressed JSON: %w", err)
	}
	decompressed, readError := io.ReadAll(io.LimitReader(reader, 16<<20))
	closeError := reader.Close()
	if readError != nil {
		return labFrame{}, fmt.Errorf("read zlib-compressed Lab frame: %w", readError)
	}
	if closeError != nil {
		return labFrame{}, fmt.Errorf("close zlib-compressed Lab frame: %w", closeError)
	}
	return decodeJSONLabFrame(decompressed)
}

func decodeJSONLabFrame(payload []byte) (labFrame, error) {
	var frame labFrame
	if err := json.Unmarshal(payload, &frame); err != nil {
		return labFrame{}, err
	}
	if len(frame.Rooms) == 0 {
		return labFrame{}, fmt.Errorf("Lab frame has no rooms")
	}
	return frame, nil
}

type vitalTrackRecord struct {
	at       float64
	waveform []float32
	numeric  float64
}

type vitalTrack struct {
	key        string
	deviceName string
	name       string
	kind       byte
	unit       string
	monitor    byte
	sampleRate float32
	minimum    float32
	maximum    float32
	records    []vitalTrackRecord
}

func collectVitalTracks(frames []labFrame) ([]vitalTrack, error) {
	byKey := map[string]*vitalTrack{}
	for frameIndex, frame := range frames {
		roomKeys := make([]string, 0, len(frame.Rooms))
		for roomKey := range frame.Rooms {
			roomKeys = append(roomKeys, roomKey)
		}
		sort.Strings(roomKeys)
		for _, roomKey := range roomKeys {
			room := frame.Rooms[roomKey]
			if room.RoomName == "" {
				room.RoomName = roomKey
			}
			for trackIndex, source := range room.Tracks {
				track, err := newVitalTrack(room.RoomName, source)
				if err != nil {
					return nil, fmt.Errorf("Lab frame %d room %q track %d: %w", frameIndex+1, room.RoomName, trackIndex+1, err)
				}
				existing := byKey[track.key]
				if existing == nil {
					byKey[track.key] = &track
					continue
				}
				if !sameVitalTrackDefinition(*existing, track) {
					return nil, fmt.Errorf("Lab frame %d changes the Vital track definition for %q", frameIndex+1, track.key)
				}
				existing.records = append(existing.records, track.records...)
			}
		}
	}
	keys := make([]string, 0, len(byKey))
	for key := range byKey {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := make([]vitalTrack, 0, len(keys))
	for _, key := range keys {
		track := *byKey[key]
		sort.Slice(track.records, func(left, right int) bool { return track.records[left].at < track.records[right].at })
		if len(track.records) == 0 {
			continue
		}
		result = append(result, track)
	}
	return result, nil
}

func newVitalTrack(roomName string, source labTrack) (vitalTrack, error) {
	if strings.TrimSpace(source.Name) == "" || strings.TrimSpace(source.Device) == "" {
		return vitalTrack{}, fmt.Errorf("track name and device name are required")
	}
	track := vitalTrack{
		key:        safeVitalName(roomName) + "_" + safeVitalName(source.Device) + "/" + safeVitalName(source.Name),
		deviceName: safeVitalName(roomName) + "_" + safeVitalName(source.Device),
		name:       safeVitalName(source.Name),
		unit:       source.Unit,
		monitor:    vitalMonitorType(source.Monitor),
		minimum:    float32(source.Minimum),
		maximum:    float32(source.Maximum),
	}
	switch source.Kind {
	case "wav":
		if source.SampleRate <= 0 || math.IsNaN(source.SampleRate) || math.IsInf(source.SampleRate, 0) {
			return vitalTrack{}, fmt.Errorf("waveform sample rate must be finite and positive")
		}
		track.kind = 1
		track.sampleRate = float32(source.SampleRate)
	case "num":
		track.kind = 2
	default:
		return vitalTrack{}, fmt.Errorf("track type %q is unsupported", source.Kind)
	}
	for recordIndex, sourceRecord := range source.Records {
		if math.IsNaN(sourceRecord.At) || math.IsInf(sourceRecord.At, 0) || sourceRecord.At <= 0 {
			return vitalTrack{}, fmt.Errorf("record %d has an invalid timestamp", recordIndex+1)
		}
		record := vitalTrackRecord{at: sourceRecord.At}
		if track.kind == 1 {
			if err := json.Unmarshal(sourceRecord.Value, &record.waveform); err != nil || len(record.waveform) == 0 {
				return vitalTrack{}, fmt.Errorf("waveform record %d must contain a non-empty numeric array", recordIndex+1)
			}
			for _, value := range record.waveform {
				if math.IsNaN(float64(value)) || math.IsInf(float64(value), 0) {
					return vitalTrack{}, fmt.Errorf("waveform record %d contains a non-finite sample", recordIndex+1)
				}
			}
		} else if err := json.Unmarshal(sourceRecord.Value, &record.numeric); err != nil || math.IsNaN(record.numeric) || math.IsInf(record.numeric, 0) {
			return vitalTrack{}, fmt.Errorf("numeric record %d must contain one finite number", recordIndex+1)
		}
		track.records = append(track.records, record)
	}
	return track, nil
}

func sameVitalTrackDefinition(left, right vitalTrack) bool {
	return left.key == right.key && left.kind == right.kind && left.unit == right.unit && left.monitor == right.monitor && left.sampleRate == right.sampleRate && left.minimum == right.minimum && left.maximum == right.maximum
}

func safeVitalName(value string) string {
	value = strings.TrimSpace(value)
	var result strings.Builder
	for _, character := range value {
		if character >= 'a' && character <= 'z' || character >= 'A' && character <= 'Z' || character >= '0' && character <= '9' || character == '-' || character == '_' {
			result.WriteRune(character)
		} else {
			result.WriteByte('_')
		}
	}
	if result.Len() == 0 {
		return "unknown"
	}
	return result.String()
}

func vitalMonitorType(value string) byte {
	return map[string]byte{
		"ECG_WAV": 1, "ECG_HR": 2, "IABP_SBP": 5, "IABP_DBP": 6, "IABP_MBP": 7,
		"PLETH_WAV": 8, "PLETH_SPO2": 10, "CO2_WAV": 13, "CO2_RR": 14, "CO2_CONC": 15,
		"BT": 19,
	}[value]
}

func encodeLegacyVitalArtifact(tracks []vitalTrack) ([]byte, error) {
	var encoded bytes.Buffer
	gzipWriter, err := gzip.NewWriterLevel(&encoded, gzip.BestCompression)
	if err != nil {
		return nil, fmt.Errorf("open Vital gzip writer: %w", err)
	}
	// This is precisely the legacy header produced by the previous writer's
	// tested rewrite: VITA, v3, header length 10, timezone/instance/program.
	// The legacy parser obtains time from records rather than v3 header fields.
	writeBytes(gzipWriter, []byte("VITA"))
	writeUint32(gzipWriter, 3)
	writeUint16(gzipWriter, 10)
	writeUint16(gzipWriter, 0)
	writeUint32(gzipWriter, 0)
	writeUint32(gzipWriter, 0)

	deviceIDs := map[string]uint32{}
	for _, track := range tracks {
		if _, exists := deviceIDs[track.deviceName]; exists {
			continue
		}
		deviceID := uint32(len(deviceIDs) + 1)
		deviceIDs[track.deviceName] = deviceID
		var device bytes.Buffer
		writeUint32(&device, deviceID)
		writeString(&device, track.deviceName)
		writeString(&device, track.deviceName)
		writeString(&device, "")
		writePacket(gzipWriter, 9, device.Bytes())
	}

	for index, track := range tracks {
		if index+1 > math.MaxUint16 {
			return nil, fmt.Errorf("too many Vital tracks")
		}
		trackID := uint16(index + 1)
		var information bytes.Buffer
		writeUint16(&information, trackID)
		information.WriteByte(track.kind)
		information.WriteByte(1) // IEEE-754 float32
		writeString(&information, track.name)
		writeString(&information, track.unit)
		writeFloat32(&information, track.minimum)
		writeFloat32(&information, track.maximum)
		writeUint32(&information, vitalTrackColor(track.monitor))
		writeFloat32(&information, track.sampleRate)
		writeFloat64(&information, 1)
		writeFloat64(&information, 0)
		information.WriteByte(track.monitor)
		writeUint32(&information, deviceIDs[track.deviceName])
		writeUint32(&information, uint32(vitalTrackRecordLength(track)))
		writeFloat64(&information, track.records[0].at)
		writeFloat64(&information, vitalTrackEnd(track))
		writePacket(gzipWriter, 0, information.Bytes())
	}

	for index, track := range tracks {
		trackID := uint16(index + 1)
		for _, record := range track.records {
			var payload bytes.Buffer
			writeUint16(&payload, 10)
			writeFloat64(&payload, record.at)
			writeUint16(&payload, trackID)
			if track.kind == 1 {
				writeUint32(&payload, uint32(len(record.waveform)))
				for _, sample := range record.waveform {
					writeFloat32(&payload, sample)
				}
			} else {
				writeFloat32(&payload, float32(record.numeric))
			}
			writePacket(gzipWriter, 1, payload.Bytes())
		}
	}
	if err := gzipWriter.Close(); err != nil {
		return nil, fmt.Errorf("close Vital gzip writer: %w", err)
	}
	return encoded.Bytes(), nil
}

func vitalTrackRecordLength(track vitalTrack) int {
	length := 0
	for _, record := range track.records {
		length += 17 // packet type, length, record info, timestamp, track id
		if track.kind == 1 {
			length += 4 + 4*len(record.waveform)
		} else {
			length += 4
		}
	}
	return length
}

func vitalTrackEnd(track vitalTrack) float64 {
	last := track.records[len(track.records)-1]
	if track.kind == 1 && track.sampleRate > 0 {
		return last.at + float64(len(last.waveform))/float64(track.sampleRate)
	}
	return last.at
}

func vitalTrackColor(monitor byte) uint32 {
	switch monitor {
	case 1, 2:
		return 4278255360
	case 5, 6, 7:
		return 4294901760
	case 8, 10:
		return 4287090426
	case 13, 14, 15:
		return 4294967040
	default:
		return 0xFFFFFF
	}
}

func writePacket(writer io.Writer, kind byte, payload []byte) {
	_, _ = writer.Write([]byte{kind})
	writeUint32(writer, uint32(len(payload)))
	writeBytes(writer, payload)
}

func writeString(writer io.Writer, value string) {
	writeUint32(writer, uint32(len([]byte(value))))
	writeBytes(writer, []byte(value))
}

func writeBytes(writer io.Writer, value []byte) { _, _ = writer.Write(value) }
func writeUint16(writer io.Writer, value uint16) {
	var data [2]byte
	binary.LittleEndian.PutUint16(data[:], value)
	writeBytes(writer, data[:])
}
func writeUint32(writer io.Writer, value uint32) {
	var data [4]byte
	binary.LittleEndian.PutUint32(data[:], value)
	writeBytes(writer, data[:])
}
func writeFloat32(writer io.Writer, value float32) { writeUint32(writer, math.Float32bits(value)) }
func writeFloat64(writer io.Writer, value float64) {
	var data [8]byte
	binary.LittleEndian.PutUint64(data[:], math.Float64bits(value))
	writeBytes(writer, data[:])
}
