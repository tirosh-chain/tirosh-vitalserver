package vitalfilereplayparser

import (
	"encoding/binary"
	"math"
	"unicode/utf8"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

var vitalNumericFormatBytes = map[uint8]int{
	1: 4,
	2: 8,
	3: 1,
	4: 1,
	5: 2,
	6: 2,
	7: 4,
	8: 4,
}

func decodeDeviceDefinition(payload []byte) (uint32, string, error) {
	cursor := vitalMetadataCursor{payload: payload, failureCode: "invalid-device-metadata"}
	deviceID, err := cursor.u32()
	if err != nil {
		return 0, "", err
	}
	deviceType, err := cursor.requiredString()
	if err != nil {
		return 0, "", err
	}
	name, err := cursor.requiredString()
	if err != nil {
		return 0, "", err
	}
	if cursor.remaining() > 0 {
		if _, err := cursor.requiredString(); err != nil {
			return 0, "", err
		}
	}
	if cursor.remaining() > 0 {
		if _, err := cursor.requiredString(); err != nil {
			return 0, "", err
		}
	}
	if cursor.remaining() != 0 {
		return 0, "", decodeFailure(
			"invalid-device-metadata",
			"Vital device metadata contains trailing bytes",
		)
	}
	if name == "" {
		name = deviceType
	}
	return deviceID, name, nil
}

func decodeTrackDefinition(
	payload []byte,
	devices map[uint32]string,
) (vitalWireTrack, error) {
	cursor := vitalMetadataCursor{payload: payload, failureCode: "invalid-track-metadata"}
	trackID, err := cursor.u16()
	if err != nil {
		return vitalWireTrack{}, err
	}
	trackKind, err := cursor.u8()
	if err != nil {
		return vitalWireTrack{}, err
	}
	formatCode, err := cursor.u8()
	if err != nil {
		return vitalWireTrack{}, err
	}
	valueBytes := vitalNumericFormatBytes[formatCode]
	kind := guestruntimedomain.VitalFileTrackKind(trackKind)
	if (kind == guestruntimedomain.VitalFileWaveformTrack ||
		kind == guestruntimedomain.VitalFileNumericTrack) &&
		valueBytes == 0 {
		return vitalWireTrack{}, decodeFailure(
			"invalid-track-metadata",
			"Vital numeric track format is unsupported",
		)
	}
	name, err := cursor.requiredString()
	if err != nil {
		return vitalWireTrack{}, err
	}
	unit := ""
	minimumDisplay := float32(0)
	maximumDisplay := float32(0)
	sampleRate := float32(0)
	gain := float64(0)
	offset := float64(0)
	monitorType := uint8(0)
	deviceID := uint32(0)
	if cursor.remaining() > 0 {
		unit, err = cursor.requiredString()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		minimumDisplay, err = cursor.f32()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		maximumDisplay, err = cursor.f32()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		if _, err := cursor.u32(); err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		sampleRate, err = cursor.f32()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		gain, err = cursor.f64()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		offset, err = cursor.f64()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		monitorType, err = cursor.u8()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		deviceID, err = cursor.u32()
		if err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		if _, err := cursor.u32(); err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		if _, err := cursor.f64(); err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() > 0 {
		if _, err := cursor.f64(); err != nil {
			return vitalWireTrack{}, err
		}
	}
	if cursor.remaining() != 0 {
		return vitalWireTrack{}, decodeFailure(
			"invalid-track-metadata",
			"Vital track metadata contains trailing bytes",
		)
	}
	deviceName := ""
	if deviceID != 0 {
		var exists bool
		deviceName, exists = devices[deviceID]
		if !exists {
			return vitalWireTrack{}, decodeFailure(
				"invalid-track-metadata",
				"Vital track references an undefined device",
			)
		}
	}
	return vitalWireTrack{
		definition: guestruntimedomain.VitalFileReplayTrackDefinition{
			TrackID:        trackID,
			Kind:           kind,
			FormatCode:     formatCode,
			Name:           name,
			DeviceName:     deviceName,
			Unit:           unit,
			SampleRate:     float64(sampleRate),
			MinimumDisplay: float64(minimumDisplay),
			MaximumDisplay: float64(maximumDisplay),
			Gain:           gain,
			Offset:         offset,
			MonitorType:    guestruntimedomain.VitalServerMonitorType(monitorType),
		},
		valueBytes: valueBytes,
	}, nil
}

func decodeNumericValue(raw []byte, formatCode uint8) float64 {
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
		panic("numeric format was not validated")
	}
}

type vitalMetadataCursor struct {
	payload     []byte
	position    int
	failureCode string
}

func (cursor *vitalMetadataCursor) remaining() int {
	return len(cursor.payload) - cursor.position
}

func (cursor *vitalMetadataCursor) take(size int) ([]byte, error) {
	if size < 0 || size > cursor.remaining() {
		return nil, decodeFailure(
			cursor.failureCode,
			"Vital metadata is truncated",
		)
	}
	value := cursor.payload[cursor.position : cursor.position+size]
	cursor.position += size
	return value, nil
}

func (cursor *vitalMetadataCursor) u8() (uint8, error) {
	value, err := cursor.take(1)
	if err != nil {
		return 0, err
	}
	return value[0], nil
}

func (cursor *vitalMetadataCursor) u16() (uint16, error) {
	value, err := cursor.take(2)
	if err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint16(value), nil
}

func (cursor *vitalMetadataCursor) u32() (uint32, error) {
	value, err := cursor.take(4)
	if err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint32(value), nil
}

func (cursor *vitalMetadataCursor) f32() (float32, error) {
	value, err := cursor.u32()
	if err != nil {
		return 0, err
	}
	return math.Float32frombits(value), nil
}

func (cursor *vitalMetadataCursor) f64() (float64, error) {
	value, err := cursor.take(8)
	if err != nil {
		return 0, err
	}
	return math.Float64frombits(binary.LittleEndian.Uint64(value)), nil
}

func (cursor *vitalMetadataCursor) requiredString() (string, error) {
	length, err := cursor.u32()
	if err != nil {
		return "", err
	}
	value, err := cursor.take(int(length))
	if err != nil {
		return "", err
	}
	if !utf8.Valid(value) {
		return "", decodeFailure(
			cursor.failureCode,
			"Vital metadata string is not UTF-8",
		)
	}
	return string(value), nil
}
