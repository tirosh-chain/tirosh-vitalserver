package guestruntimedomain

import (
	"fmt"
	"time"
)

type RecorderObservationFreshnessPolicy struct {
	MaxReportAgeSeconds int `json:"maxReportAgeSeconds"`
}

func ValidateRecorderObservationFreshnessPolicy(policy RecorderObservationFreshnessPolicy) error {
	if policy.MaxReportAgeSeconds < 1 || policy.MaxReportAgeSeconds > 86400 {
		return fmt.Errorf("Recorder observation max report age must be between 1 and 86400 seconds")
	}
	return nil
}

// ProjectRecorderReportFreshness derives only the Catalog-owned report axis
// from the Catalog-owned receivedAt timestamp, an explicit policy, and the
// caller-provided observation time. It never uses device time, packet gaps,
// UI refresh state, or absence to infer support or expectation.
func ProjectRecorderReportFreshness(
	summary RecorderObservabilitySummary,
	policy RecorderObservationFreshnessPolicy,
	observedAt time.Time,
) (RecorderObservabilitySummary, error) {
	if err := ValidateRecorderObservationFreshnessPolicy(policy); err != nil {
		return RecorderObservabilitySummary{}, err
	}
	if summary.ReportState == "never-reported" {
		if summary.LatestReceivedAt != nil {
			return RecorderObservabilitySummary{}, fmt.Errorf("never-reported summary must not contain latest received evidence")
		}
		return summary, nil
	}
	if summary.ReportState != "current" && summary.ReportState != "stale" {
		return RecorderObservabilitySummary{}, fmt.Errorf("Recorder report state is invalid")
	}
	if summary.LatestReceivedAt == nil {
		return RecorderObservabilitySummary{}, fmt.Errorf("reported summary requires latest received evidence")
	}
	receivedAt, err := time.Parse(time.RFC3339Nano, *summary.LatestReceivedAt)
	if err != nil {
		return RecorderObservabilitySummary{}, fmt.Errorf("Recorder latest received timestamp is invalid")
	}
	age := observedAt.Sub(receivedAt)
	if age < 0 {
		return RecorderObservabilitySummary{}, fmt.Errorf("Recorder latest received timestamp is later than Catalog observation time")
	}
	if age > time.Duration(policy.MaxReportAgeSeconds)*time.Second {
		summary.ReportState = "stale"
	} else {
		summary.ReportState = "current"
	}
	return summary, nil
}
