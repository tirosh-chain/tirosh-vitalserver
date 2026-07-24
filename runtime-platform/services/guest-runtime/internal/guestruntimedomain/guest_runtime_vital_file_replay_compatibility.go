package guestruntimedomain

import (
	"fmt"
	"math"
)

const (
	VitalFileMaximumReplayTracks       = 4096
	VitalFileMaximumReplayFrameSamples = 100000

	VitalFileReplayTrackActionReplay = "replay"
	VitalFileReplayTrackActionSkip   = "skip"

	VitalFileStringTrackPolicyReject = "reject"
	VitalFileStringTrackPolicySkip   = "skip"
)

type VitalFileFormatVersion uint32

const (
	VitalFileFormatV1 VitalFileFormatVersion = 1
	VitalFileFormatV2 VitalFileFormatVersion = 2
	VitalFileFormatV3 VitalFileFormatVersion = 3
)

type VitalFileTrackKind uint8

const (
	VitalFileWaveformTrack VitalFileTrackKind = 1
	VitalFileNumericTrack  VitalFileTrackKind = 2
	VitalFileStringTrack   VitalFileTrackKind = 5
)

// VitalServerMonitorType is the published .vital TRACKINFO montype/realtime
// send_data wire identifier. It is an enum, not a display-name dictionary.
// Unknown values remain unknown and are never assigned a known display type.
type VitalServerMonitorType uint16

const (
	VitalServerMonitorECGWaveform      VitalServerMonitorType = 1
	VitalServerMonitorECGHeartRate     VitalServerMonitorType = 2
	VitalServerMonitorECGPVC           VitalServerMonitorType = 3
	VitalServerMonitorIABPWaveform     VitalServerMonitorType = 4
	VitalServerMonitorIABPSystolic     VitalServerMonitorType = 5
	VitalServerMonitorIABPDiastolic    VitalServerMonitorType = 6
	VitalServerMonitorIABPMean         VitalServerMonitorType = 7
	VitalServerMonitorPlethWaveform    VitalServerMonitorType = 8
	VitalServerMonitorPlethHeartRate   VitalServerMonitorType = 9
	VitalServerMonitorPlethSpO2        VitalServerMonitorType = 10
	VitalServerMonitorRespWaveform     VitalServerMonitorType = 11
	VitalServerMonitorRespRate         VitalServerMonitorType = 12
	VitalServerMonitorCO2Waveform      VitalServerMonitorType = 13
	VitalServerMonitorCO2Rate          VitalServerMonitorType = 14
	VitalServerMonitorCO2Concentration VitalServerMonitorType = 15
	VitalServerMonitorNIBPSystolic     VitalServerMonitorType = 16
	VitalServerMonitorNIBPDiastolic    VitalServerMonitorType = 17
	VitalServerMonitorNIBPMean         VitalServerMonitorType = 18
	VitalServerMonitorBodyTemperature  VitalServerMonitorType = 19
	VitalServerMonitorCVPWaveform      VitalServerMonitorType = 20
	VitalServerMonitorCVP              VitalServerMonitorType = 21
	VitalServerMonitorBIS              VitalServerMonitorType = 22
	VitalServerMonitorTidalVolume      VitalServerMonitorType = 23
	VitalServerMonitorMinuteVolume     VitalServerMonitorType = 24
	VitalServerMonitorPIP              VitalServerMonitorType = 25
	VitalServerMonitorAgent1Name       VitalServerMonitorType = 26
	VitalServerMonitorAgent1Conc       VitalServerMonitorType = 27
	VitalServerMonitorAgent2Name       VitalServerMonitorType = 28
	VitalServerMonitorAgent2Conc       VitalServerMonitorType = 29
	VitalServerMonitorDrug1Name        VitalServerMonitorType = 30
	VitalServerMonitorDrug1CE          VitalServerMonitorType = 31
	VitalServerMonitorDrug2Name        VitalServerMonitorType = 32
	VitalServerMonitorDrug2CE          VitalServerMonitorType = 33
	VitalServerMonitorCardiacOutput    VitalServerMonitorType = 34
	VitalServerMonitorEEGSEF           VitalServerMonitorType = 36
	VitalServerMonitorPEEP             VitalServerMonitorType = 38
	VitalServerMonitorECGST            VitalServerMonitorType = 39
	VitalServerMonitorAgent3Name       VitalServerMonitorType = 40
	VitalServerMonitorAgent3Conc       VitalServerMonitorType = 41
	VitalServerMonitorSTO2Left         VitalServerMonitorType = 42
	VitalServerMonitorSTO2Right        VitalServerMonitorType = 43
	VitalServerMonitorEEGWaveform      VitalServerMonitorType = 44
	VitalServerMonitorFluidRate        VitalServerMonitorType = 45
	VitalServerMonitorFluidTotal       VitalServerMonitorType = 46
	VitalServerMonitorSVV              VitalServerMonitorType = 47
	VitalServerMonitorDrug3Name        VitalServerMonitorType = 49
	VitalServerMonitorDrug3CE          VitalServerMonitorType = 50
	VitalServerMonitorFilter11         VitalServerMonitorType = 52
	VitalServerMonitorFilter12         VitalServerMonitorType = 53
	VitalServerMonitorFilter21         VitalServerMonitorType = 54
	VitalServerMonitorFilter22         VitalServerMonitorType = 55
	VitalServerMonitorFilter31         VitalServerMonitorType = 56
	VitalServerMonitorFilter32         VitalServerMonitorType = 57
	VitalServerMonitorFilter41         VitalServerMonitorType = 58
	VitalServerMonitorFilter42         VitalServerMonitorType = 59
	VitalServerMonitorFilter51         VitalServerMonitorType = 60
	VitalServerMonitorFilter52         VitalServerMonitorType = 61
	VitalServerMonitorFilter61         VitalServerMonitorType = 62
	VitalServerMonitorFilter62         VitalServerMonitorType = 63
	VitalServerMonitorFilter71         VitalServerMonitorType = 64
	VitalServerMonitorFilter72         VitalServerMonitorType = 65
	VitalServerMonitorFilter81         VitalServerMonitorType = 66
	VitalServerMonitorFilter82         VitalServerMonitorType = 67
	VitalServerMonitorPSI              VitalServerMonitorType = 70
	VitalServerMonitorPVI              VitalServerMonitorType = 71
	VitalServerMonitorSpHb             VitalServerMonitorType = 72
	VitalServerMonitorORI              VitalServerMonitorType = 73
	VitalServerMonitorASKNA            VitalServerMonitorType = 75
	VitalServerMonitorPAPSystolic      VitalServerMonitorType = 76
	VitalServerMonitorPAPMean          VitalServerMonitorType = 77
	VitalServerMonitorPAPDiastolic     VitalServerMonitorType = 78
	VitalServerMonitorFemoralSystolic  VitalServerMonitorType = 79
	VitalServerMonitorFemoralMean      VitalServerMonitorType = 80
	VitalServerMonitorFemoralDiastolic VitalServerMonitorType = 81
	VitalServerMonitorEEGSEFLeft       VitalServerMonitorType = 82
	VitalServerMonitorEEGSEFRight      VitalServerMonitorType = 83
	VitalServerMonitorEEGSuppression   VitalServerMonitorType = 84
	VitalServerMonitorTOFRatio         VitalServerMonitorType = 85
	VitalServerMonitorTOFCount         VitalServerMonitorType = 86
	VitalServerMonitorSKNAWaveform     VitalServerMonitorType = 87
	VitalServerMonitorICP              VitalServerMonitorType = 88
	VitalServerMonitorCPP              VitalServerMonitorType = 89
	VitalServerMonitorICPWaveform      VitalServerMonitorType = 90
	VitalServerMonitorPAPWaveform      VitalServerMonitorType = 91
	VitalServerMonitorFemoralWaveform  VitalServerMonitorType = 92
	VitalServerMonitorAlarmLevel       VitalServerMonitorType = 93
	VitalServerMonitorEEGLeftWaveform  VitalServerMonitorType = 95
	VitalServerMonitorEEGRightWaveform VitalServerMonitorType = 96
	VitalServerMonitorANII             VitalServerMonitorType = 97
	VitalServerMonitorANIM             VitalServerMonitorType = 98
	VitalServerMonitorPostTetanicCount VitalServerMonitorType = 99
)

type VitalFileReplayCompatibilityPolicy struct {
	StringTrackPolicy string
}

type VitalFileReplayTrackMetadata struct {
	TrackID     uint16
	Kind        VitalFileTrackKind
	SampleRate  float64
	MonitorType VitalServerMonitorType
}

type VitalFileReplayManifest struct {
	FormatVersion VitalFileFormatVersion
	Tracks        []VitalFileReplayTrackMetadata
}

type VitalFileReplayTrackDecision struct {
	TrackID     uint16
	Kind        VitalFileTrackKind
	SampleRate  float64
	MonitorType VitalServerMonitorType
	Action      string
}

type VitalFileReplayCompatibilityDecision struct {
	FileFormatVersion          string
	Tracks                     []VitalFileReplayTrackDecision
	GraphCompatibleSignalCount int
}

type VitalFileReplayCompatibilityFailure struct {
	Code    string
	Message string
}

func (failure VitalFileReplayCompatibilityFailure) Error() string {
	return failure.Message
}

func (failure VitalFileReplayCompatibilityFailure) ReplayFailureCode() string {
	return failure.Code
}

func EvaluateVitalFileReplayCompatibility(
	policy VitalFileReplayCompatibilityPolicy,
	manifest VitalFileReplayManifest,
) (VitalFileReplayCompatibilityDecision, error) {
	fileFormatVersion, ok := manifest.FormatVersion.ReplayContractName()
	if !ok {
		return VitalFileReplayCompatibilityDecision{}, vitalCompatibilityFailure(
			"unsupported-format-version",
			"Vital file format version is unsupported",
		)
	}
	if policy.StringTrackPolicy != VitalFileStringTrackPolicyReject &&
		policy.StringTrackPolicy != VitalFileStringTrackPolicySkip {
		return VitalFileReplayCompatibilityDecision{}, vitalCompatibilityFailure(
			"invalid-string-track-policy",
			"Vital file string track policy is invalid",
		)
	}
	if len(manifest.Tracks) < 1 {
		return VitalFileReplayCompatibilityDecision{}, vitalCompatibilityFailure(
			"no-tracks",
			"Vital file contains no tracks",
		)
	}
	if len(manifest.Tracks) > VitalFileMaximumReplayTracks {
		return VitalFileReplayCompatibilityDecision{}, vitalCompatibilityFailure(
			"too-many-tracks",
			"Vital file contains more tracks than the replay limit",
		)
	}

	decision := VitalFileReplayCompatibilityDecision{
		FileFormatVersion: fileFormatVersion,
		Tracks:            make([]VitalFileReplayTrackDecision, 0, len(manifest.Tracks)),
	}
	trackIDs := make(map[uint16]struct{}, len(manifest.Tracks))
	for _, track := range manifest.Tracks {
		if _, exists := trackIDs[track.TrackID]; exists {
			return VitalFileReplayCompatibilityDecision{}, vitalCompatibilityFailure(
				"duplicate-track-id",
				"Vital file contains a duplicate track identifier",
			)
		}
		trackIDs[track.TrackID] = struct{}{}
		trackDecision, failure := evaluateVitalFileReplayTrackCompatibility(
			policy,
			track,
		)
		if failure != nil {
			return VitalFileReplayCompatibilityDecision{}, *failure
		}
		decision.Tracks = append(decision.Tracks, trackDecision)
		if trackDecision.Action == VitalFileReplayTrackActionReplay &&
			trackDecision.MonitorType.Known() {
			decision.GraphCompatibleSignalCount++
		}
	}
	if decision.GraphCompatibleSignalCount < 1 {
		return VitalFileReplayCompatibilityDecision{}, vitalCompatibilityFailure(
			"no-vitalserver-graph-tracks",
			"Vital file contains no graph-compatible replay signal",
		)
	}
	return decision, nil
}

func evaluateVitalFileReplayTrackCompatibility(
	policy VitalFileReplayCompatibilityPolicy,
	track VitalFileReplayTrackMetadata,
) (VitalFileReplayTrackDecision, *VitalFileReplayCompatibilityFailure) {
	decision := VitalFileReplayTrackDecision{
		TrackID:     track.TrackID,
		Kind:        track.Kind,
		SampleRate:  track.SampleRate,
		MonitorType: track.MonitorType,
		Action:      VitalFileReplayTrackActionReplay,
	}
	switch track.Kind {
	case VitalFileWaveformTrack:
		if math.IsNaN(track.SampleRate) ||
			math.IsInf(track.SampleRate, 0) ||
			track.SampleRate <= 0 {
			failure := vitalCompatibilityFailure(
				"invalid-waveform-sample-rate",
				"Vital waveform track requires a positive finite sample rate",
			)
			return VitalFileReplayTrackDecision{}, &failure
		}
		if math.Round(track.SampleRate) > VitalFileMaximumReplayFrameSamples {
			failure := vitalCompatibilityFailure(
				"replay-frame-too-large",
				"Vital waveform track exceeds the one-second replay frame limit",
			)
			return VitalFileReplayTrackDecision{}, &failure
		}
	case VitalFileNumericTrack:
		if math.IsNaN(track.SampleRate) ||
			math.IsInf(track.SampleRate, 0) ||
			track.SampleRate < 0 {
			failure := vitalCompatibilityFailure(
				"invalid-numeric-sample-rate",
				"Vital numeric track sample rate must be finite and non-negative",
			)
			return VitalFileReplayTrackDecision{}, &failure
		}
	case VitalFileStringTrack:
		if policy.StringTrackPolicy == VitalFileStringTrackPolicyReject {
			failure := vitalCompatibilityFailure(
				"unsupported-string-track",
				"Vital string track replay is explicitly rejected",
			)
			return VitalFileReplayTrackDecision{}, &failure
		}
		decision.Action = VitalFileReplayTrackActionSkip
	default:
		failure := vitalCompatibilityFailure(
			"unsupported-track-type",
			"Vital file contains an unsupported track type",
		)
		return VitalFileReplayTrackDecision{}, &failure
	}
	return decision, nil
}

func (version VitalFileFormatVersion) ReplayContractName() (string, bool) {
	switch version {
	case VitalFileFormatV1:
		return "vital-v1", true
	case VitalFileFormatV2:
		return "vital-v2", true
	case VitalFileFormatV3:
		return "vital-v3", true
	default:
		return "", false
	}
}

func (monitorType VitalServerMonitorType) Known() bool {
	switch monitorType {
	case VitalServerMonitorECGWaveform,
		VitalServerMonitorECGHeartRate,
		VitalServerMonitorECGPVC,
		VitalServerMonitorIABPWaveform,
		VitalServerMonitorIABPSystolic,
		VitalServerMonitorIABPDiastolic,
		VitalServerMonitorIABPMean,
		VitalServerMonitorPlethWaveform,
		VitalServerMonitorPlethHeartRate,
		VitalServerMonitorPlethSpO2,
		VitalServerMonitorRespWaveform,
		VitalServerMonitorRespRate,
		VitalServerMonitorCO2Waveform,
		VitalServerMonitorCO2Rate,
		VitalServerMonitorCO2Concentration,
		VitalServerMonitorNIBPSystolic,
		VitalServerMonitorNIBPDiastolic,
		VitalServerMonitorNIBPMean,
		VitalServerMonitorBodyTemperature,
		VitalServerMonitorCVPWaveform,
		VitalServerMonitorCVP,
		VitalServerMonitorBIS,
		VitalServerMonitorTidalVolume,
		VitalServerMonitorMinuteVolume,
		VitalServerMonitorPIP,
		VitalServerMonitorAgent1Name,
		VitalServerMonitorAgent1Conc,
		VitalServerMonitorAgent2Name,
		VitalServerMonitorAgent2Conc,
		VitalServerMonitorDrug1Name,
		VitalServerMonitorDrug1CE,
		VitalServerMonitorDrug2Name,
		VitalServerMonitorDrug2CE,
		VitalServerMonitorCardiacOutput,
		VitalServerMonitorEEGSEF,
		VitalServerMonitorPEEP,
		VitalServerMonitorECGST,
		VitalServerMonitorAgent3Name,
		VitalServerMonitorAgent3Conc,
		VitalServerMonitorSTO2Left,
		VitalServerMonitorSTO2Right,
		VitalServerMonitorEEGWaveform,
		VitalServerMonitorFluidRate,
		VitalServerMonitorFluidTotal,
		VitalServerMonitorSVV,
		VitalServerMonitorDrug3Name,
		VitalServerMonitorDrug3CE,
		VitalServerMonitorFilter11,
		VitalServerMonitorFilter12,
		VitalServerMonitorFilter21,
		VitalServerMonitorFilter22,
		VitalServerMonitorFilter31,
		VitalServerMonitorFilter32,
		VitalServerMonitorFilter41,
		VitalServerMonitorFilter42,
		VitalServerMonitorFilter51,
		VitalServerMonitorFilter52,
		VitalServerMonitorFilter61,
		VitalServerMonitorFilter62,
		VitalServerMonitorFilter71,
		VitalServerMonitorFilter72,
		VitalServerMonitorFilter81,
		VitalServerMonitorFilter82,
		VitalServerMonitorPSI,
		VitalServerMonitorPVI,
		VitalServerMonitorSpHb,
		VitalServerMonitorORI,
		VitalServerMonitorASKNA,
		VitalServerMonitorPAPSystolic,
		VitalServerMonitorPAPMean,
		VitalServerMonitorPAPDiastolic,
		VitalServerMonitorFemoralSystolic,
		VitalServerMonitorFemoralMean,
		VitalServerMonitorFemoralDiastolic,
		VitalServerMonitorEEGSEFLeft,
		VitalServerMonitorEEGSEFRight,
		VitalServerMonitorEEGSuppression,
		VitalServerMonitorTOFRatio,
		VitalServerMonitorTOFCount,
		VitalServerMonitorSKNAWaveform,
		VitalServerMonitorICP,
		VitalServerMonitorCPP,
		VitalServerMonitorICPWaveform,
		VitalServerMonitorPAPWaveform,
		VitalServerMonitorFemoralWaveform,
		VitalServerMonitorAlarmLevel,
		VitalServerMonitorEEGLeftWaveform,
		VitalServerMonitorEEGRightWaveform,
		VitalServerMonitorANII,
		VitalServerMonitorANIM,
		VitalServerMonitorPostTetanicCount:
		return true
	default:
		return false
	}
}

func vitalCompatibilityFailure(
	code string,
	message string,
) VitalFileReplayCompatibilityFailure {
	return VitalFileReplayCompatibilityFailure{
		Code:    code,
		Message: fmt.Sprintf("%s (%s)", message, code),
	}
}
