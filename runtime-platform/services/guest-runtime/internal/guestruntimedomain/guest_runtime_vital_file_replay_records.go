package guestruntimedomain

import (
	"fmt"
	"math"
)

type VitalFileReplayHeader struct {
	FormatVersion VitalFileFormatVersion
	StartedAt     *float64
	EndedAt       *float64
}

type VitalFileReplayTrackDefinition struct {
	TrackID        uint16
	Kind           VitalFileTrackKind
	FormatCode     uint8
	Name           string
	DeviceName     string
	Unit           string
	SampleRate     float64
	MinimumDisplay float64
	MaximumDisplay float64
	Gain           float64
	Offset         float64
	MonitorType    VitalServerMonitorType
}

type VitalFileReplayWaveformChunk struct {
	TrackID      uint16
	RecordedAt   float64
	SampleOffset uint32
	SampleCount  uint32
	RawValues    []byte
}

type VitalFileReplayNumericRecord struct {
	TrackID    uint16
	RecordedAt float64
	Value      float64
}

type VitalFileReplayStringRecord struct {
	TrackID    uint16
	RecordedAt float64
	Value      string
}

type VitalFileReplayScanResult struct {
	Compatibility VitalFileReplayCompatibilityDecision
	Header        VitalFileReplayHeader
	ObservedStart *float64
	ObservedEnd   *float64
	RecordCount   uint64
}

func (result VitalFileReplayScanResult) TimeRange() (float64, float64, error) {
	startedAt := result.Header.StartedAt
	endedAt := result.Header.EndedAt
	if startedAt == nil {
		startedAt = result.ObservedStart
	}
	if endedAt == nil {
		endedAt = result.ObservedEnd
	}
	if startedAt == nil || endedAt == nil {
		return 0, 0, fmt.Errorf("Vital file replay source has no explicit time range")
	}
	if math.IsNaN(*startedAt) || math.IsInf(*startedAt, 0) ||
		math.IsNaN(*endedAt) || math.IsInf(*endedAt, 0) ||
		*endedAt < *startedAt {
		return 0, 0, fmt.Errorf("Vital file replay source time range is invalid")
	}
	return *startedAt, *endedAt, nil
}
