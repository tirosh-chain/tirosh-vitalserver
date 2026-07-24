package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math"
	"time"
)

const (
	VitalFileReplayGapPolicyOmitTrack = "omit-track"
	VitalFileReplayGapPolicyFailFrame = "fail-frame"
)

type VitalFileReplaySpoolReceipt struct {
	SchemaVersion              string  `json:"schemaVersion"`
	ReplayID                   string  `json:"replayId"`
	FileFormatVersion          string  `json:"fileFormatVersion"`
	DatabaseSHA256             string  `json:"databaseSha256"`
	DatabaseByteSize           int64   `json:"databaseByteSize"`
	StartedAt                  float64 `json:"startedAt"`
	EndedAt                    float64 `json:"endedAt"`
	DurationSeconds            int     `json:"durationSeconds"`
	TrackCount                 int     `json:"trackCount"`
	RecordCount                uint64  `json:"recordCount"`
	GraphCompatibleSignalCount int     `json:"graphCompatibleSignalCount"`
	FinalizedAt                string  `json:"finalizedAt"`
}

type VitalFileReplayFrameTrack struct {
	OutputTrackID  uint32                 `json:"outputTrackId"`
	SourceTrackID  uint16                 `json:"sourceTrackId"`
	Kind           VitalFileTrackKind     `json:"kind"`
	Name           string                 `json:"name"`
	DeviceName     string                 `json:"deviceName"`
	Unit           string                 `json:"unit"`
	MonitorType    VitalServerMonitorType `json:"monitorType"`
	SampleRate     float64                `json:"sampleRate,omitempty"`
	MinimumDisplay float64                `json:"minimumDisplay,omitempty"`
	MaximumDisplay float64                `json:"maximumDisplay,omitempty"`
	WaveformValues []float64              `json:"waveformValues,omitempty"`
	NumericValue   *float64               `json:"numericValue,omitempty"`
}

type VitalFileReplayFrame struct {
	OffsetSeconds int                         `json:"offsetSeconds"`
	OutputTime    float64                     `json:"outputTime"`
	Tracks        []VitalFileReplayFrameTrack `json:"tracks"`
}

func ValidateVitalFileReplaySpoolReceipt(
	receipt VitalFileReplaySpoolReceipt,
) error {
	_, validFileFormatVersion := VitalFileFormatVersion(
		vitalFileFormatVersionCode(receipt.FileFormatVersion),
	).ReplayContractName()
	digest, digestErr := hex.DecodeString(receipt.DatabaseSHA256)
	_, finalizedAtErr := time.Parse(time.RFC3339Nano, receipt.FinalizedAt)
	if receipt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(receipt.ReplayID) ||
		!validFileFormatVersion ||
		digestErr != nil ||
		len(digest) != sha256.Size ||
		receipt.DatabaseByteSize < 1 ||
		!finiteVitalReplayTime(receipt.StartedAt) ||
		!finiteVitalReplayTime(receipt.EndedAt) ||
		receipt.EndedAt <= receipt.StartedAt ||
		receipt.DurationSeconds < 1 ||
		receipt.DurationSeconds != int(math.Ceil(receipt.EndedAt-receipt.StartedAt)) ||
		receipt.TrackCount < 1 ||
		receipt.RecordCount < 1 ||
		receipt.GraphCompatibleSignalCount < 1 ||
		receipt.GraphCompatibleSignalCount > receipt.TrackCount ||
		finalizedAtErr != nil {
		return fmt.Errorf("Vital file replay spool receipt is incomplete or invalid")
	}
	return nil
}

func ValidVitalFileReplayGapPolicy(policy string) bool {
	return policy == VitalFileReplayGapPolicyOmitTrack ||
		policy == VitalFileReplayGapPolicyFailFrame
}

func vitalFileFormatVersionCode(name string) uint32 {
	switch name {
	case "vital-v1":
		return 1
	case "vital-v2":
		return 2
	case "vital-v3":
		return 3
	default:
		return 0
	}
}

func finiteVitalReplayTime(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}
