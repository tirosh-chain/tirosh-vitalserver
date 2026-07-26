package guestruntimedomain_test

import (
	"errors"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestVitalReplayCompatibilityPreservesNumericZeroSampleRate(t *testing.T) {
	for _, version := range []guestruntimedomain.VitalFileFormatVersion{
		guestruntimedomain.VitalFileFormatV1,
		guestruntimedomain.VitalFileFormatV2,
		guestruntimedomain.VitalFileFormatV3,
	} {
		decision, err := guestruntimedomain.EvaluateVitalFileReplayCompatibility(
			guestruntimedomain.VitalFileReplayCompatibilityPolicy{
				StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
			},
			guestruntimedomain.VitalFileReplayManifest{
				FormatVersion: version,
				Tracks: []guestruntimedomain.VitalFileReplayTrackMetadata{
					{
						TrackID:     1,
						Kind:        guestruntimedomain.VitalFileWaveformTrack,
						SampleRate:  500,
						MonitorType: guestruntimedomain.VitalServerMonitorPlethWaveform,
					},
					{
						TrackID:     2,
						Kind:        guestruntimedomain.VitalFileNumericTrack,
						SampleRate:  0,
						MonitorType: guestruntimedomain.VitalServerMonitorPlethHeartRate,
					},
					{
						TrackID:     3,
						Kind:        guestruntimedomain.VitalFileNumericTrack,
						SampleRate:  0,
						MonitorType: guestruntimedomain.VitalServerMonitorPlethSpO2,
					},
				},
			},
		)
		if err != nil {
			t.Fatalf("version %d: %v", version, err)
		}
		if decision.Tracks[1].Kind != guestruntimedomain.VitalFileNumericTrack ||
			decision.Tracks[1].SampleRate != 0 ||
			decision.GraphCompatibleSignalCount != 3 {
			t.Fatalf("version %d decision = %+v", version, decision)
		}
	}
}

func TestVitalReplayCompatibilityRejectsWaveformWithoutPositiveRate(t *testing.T) {
	assertVitalCompatibilityFailure(
		t,
		guestruntimedomain.VitalFileReplayManifest{
			FormatVersion: guestruntimedomain.VitalFileFormatV3,
			Tracks: []guestruntimedomain.VitalFileReplayTrackMetadata{{
				TrackID:     1,
				Kind:        guestruntimedomain.VitalFileWaveformTrack,
				SampleRate:  0,
				MonitorType: guestruntimedomain.VitalServerMonitorECGWaveform,
			}},
		},
		guestruntimedomain.VitalFileStringTrackPolicySkip,
		"invalid-waveform-sample-rate",
	)
}

func TestVitalReplayCompatibilityStringPolicyIsExplicit(t *testing.T) {
	manifest := guestruntimedomain.VitalFileReplayManifest{
		FormatVersion: guestruntimedomain.VitalFileFormatV3,
		Tracks: []guestruntimedomain.VitalFileReplayTrackMetadata{
			{
				TrackID:     1,
				Kind:        guestruntimedomain.VitalFileNumericTrack,
				SampleRate:  0,
				MonitorType: guestruntimedomain.VitalServerMonitorECGHeartRate,
			},
			{
				TrackID:    2,
				Kind:       guestruntimedomain.VitalFileStringTrack,
				SampleRate: 0,
			},
		},
	}
	assertVitalCompatibilityFailure(
		t,
		manifest,
		guestruntimedomain.VitalFileStringTrackPolicyReject,
		"unsupported-string-track",
	)
	decision, err := guestruntimedomain.EvaluateVitalFileReplayCompatibility(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: guestruntimedomain.VitalFileStringTrackPolicySkip,
		},
		manifest,
	)
	if err != nil {
		t.Fatal(err)
	}
	if decision.Tracks[1].Action != guestruntimedomain.VitalFileReplayTrackActionSkip {
		t.Fatalf("string track decision = %+v", decision.Tracks[1])
	}
}

func TestVitalReplayCompatibilityDoesNotInferUnknownMonitorType(t *testing.T) {
	assertVitalCompatibilityFailure(
		t,
		guestruntimedomain.VitalFileReplayManifest{
			FormatVersion: guestruntimedomain.VitalFileFormatV3,
			Tracks: []guestruntimedomain.VitalFileReplayTrackMetadata{{
				TrackID:     1,
				Kind:        guestruntimedomain.VitalFileNumericTrack,
				SampleRate:  0,
				MonitorType: 999,
			}},
		},
		guestruntimedomain.VitalFileStringTrackPolicySkip,
		"no-vitalserver-graph-tracks",
	)
}

func TestVitalReplayCompatibilityRejectsUnknownTrackKindAndFutureVersion(t *testing.T) {
	assertVitalCompatibilityFailure(
		t,
		guestruntimedomain.VitalFileReplayManifest{
			FormatVersion: guestruntimedomain.VitalFileFormatV3,
			Tracks: []guestruntimedomain.VitalFileReplayTrackMetadata{{
				TrackID:     1,
				Kind:        4,
				MonitorType: guestruntimedomain.VitalServerMonitorECGWaveform,
			}},
		},
		guestruntimedomain.VitalFileStringTrackPolicySkip,
		"unsupported-track-type",
	)
	assertVitalCompatibilityFailure(
		t,
		guestruntimedomain.VitalFileReplayManifest{
			FormatVersion: 4,
			Tracks: []guestruntimedomain.VitalFileReplayTrackMetadata{{
				TrackID:     1,
				Kind:        guestruntimedomain.VitalFileNumericTrack,
				MonitorType: guestruntimedomain.VitalServerMonitorECGHeartRate,
			}},
		},
		guestruntimedomain.VitalFileStringTrackPolicySkip,
		"unsupported-format-version",
	)
}

func assertVitalCompatibilityFailure(
	t *testing.T,
	manifest guestruntimedomain.VitalFileReplayManifest,
	stringTrackPolicy string,
	code string,
) {
	t.Helper()
	_, err := guestruntimedomain.EvaluateVitalFileReplayCompatibility(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: stringTrackPolicy,
		},
		manifest,
	)
	var failure guestruntimedomain.VitalFileReplayCompatibilityFailure
	if !errors.As(err, &failure) || failure.Code != code {
		t.Fatalf("failure = %#v, want code %s", err, code)
	}
}
