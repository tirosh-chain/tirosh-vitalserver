package timeprovider

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// ChronyTrackingTimeAuthorityProvider reads complete synchronization evidence
// from the explicitly configured Chrony executable in the Linux Guest. It
// does not infer NTP state from the local wall clock or from command logs.
// Host nodes use their own platform-specific provider; this adapter owns only
// the Guest-side Chrony boundary.
type ChronyTrackingTimeAuthorityProvider struct {
	executablePath string
	requestTimeout time.Duration
	commandRunner  chronyTrackingCommandRunner
}

type chronyTrackingCommandRunner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type operatingSystemChronyTrackingCommandRunner struct{}

func (operatingSystemChronyTrackingCommandRunner) Run(ctx context.Context, executablePath string, arguments ...string) ([]byte, error) {
	return exec.CommandContext(ctx, executablePath, arguments...).Output()
}

// NewChronyTrackingTimeAuthorityProvider requires the absolute path selected
// by deployment. It does not search PATH and cannot silently choose an OS
// default NTP daemon.
func NewChronyTrackingTimeAuthorityProvider(executablePath string, requestTimeout time.Duration) (*ChronyTrackingTimeAuthorityProvider, error) {
	if !validChronyExecutablePath(executablePath) {
		return nil, fmt.Errorf("Chrony executable path must be an absolute non-traversing Guest path")
	}
	if requestTimeout <= 0 {
		return nil, fmt.Errorf("Chrony request timeout must be positive")
	}
	return &ChronyTrackingTimeAuthorityProvider{executablePath: executablePath, requestTimeout: requestTimeout, commandRunner: operatingSystemChronyTrackingCommandRunner{}}, nil
}

func newChronyTrackingTimeAuthorityProviderForTest(executablePath string, commandRunner chronyTrackingCommandRunner) *ChronyTrackingTimeAuthorityProvider {
	return &ChronyTrackingTimeAuthorityProvider{executablePath: executablePath, requestTimeout: time.Second, commandRunner: commandRunner}
}

func (provider *ChronyTrackingTimeAuthorityProvider) ObserveTimeAuthority(ctx context.Context, node guestruntimedomain.NodeReference, spec guestruntimedomain.TimeAuthoritySpec, observedAt string) (guestruntimedomain.ClockQuality, error) {
	if provider == nil || provider.commandRunner == nil || !validChronyExecutablePath(provider.executablePath) {
		issue := chronyIssue(spec, "ntp-probe-not-composed", "Chrony tracking provider is not composed", false)
		return failedChronyQuality(node, observedAt, issue), nil
	}
	if issue := guestruntimedomain.ValidateTimeAuthorityApplyCommand(guestruntimedomain.TimeAuthorityApplyCommand{SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "time-probe", AuthorityID: "time-authority", Node: node, Spec: spec}); issue != nil {
		resultIssue := chronyIssue(spec, "ntp-time-authority-spec-invalid", issue.Message, false)
		return failedChronyQuality(node, observedAt, resultIssue), nil
	}
	probeContext, cancel := context.WithTimeout(ctx, provider.requestTimeout)
	defer cancel()
	output, err := provider.commandRunner.Run(probeContext, provider.executablePath, "tracking", "-n")
	if err != nil {
		issue := chronyIssue(spec, "ntp-probe-execution-failed", fmt.Sprintf("Chrony tracking command failed: %v", err), ctx.Err() != nil)
		return failedChronyQuality(node, observedAt, issue), nil
	}
	evidence, err := parseChronyTrackingEvidence(string(output))
	if err != nil {
		issue := chronyIssue(spec, "ntp-probe-evidence-invalid", err.Error(), false)
		return failedChronyQuality(node, observedAt, issue), nil
	}
	source := spec.Source
	if evidence.leapStatus != "Normal" {
		issue := chronyIssue(spec, "ntp-source-unsynchronized", "Chrony leap status is "+evidence.leapStatus, true)
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "unsynchronized", ObservedAt: observedAt, Issue: &issue}, nil
	}
	if evidence.stratum < 1 || evidence.stratum > 15 {
		issue := chronyIssue(spec, "ntp-source-unsynchronized", fmt.Sprintf("Chrony stratum %d is not synchronized", evidence.stratum), true)
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "unsynchronized", ObservedAt: observedAt, Issue: &issue}, nil
	}
	stratum := evidence.stratum
	offsetMilliseconds := evidence.lastOffsetSeconds * 1000
	uncertaintyMilliseconds := evidence.rootDispersionSeconds * 1000
	lastSyncAt := guestruntimedomain.Timestamp(evidence.referenceTime)
	return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "synchronized", Source: &source, Stratum: &stratum, OffsetMs: &offsetMilliseconds, UncertaintyMs: &uncertaintyMilliseconds, LastSyncAt: &lastSyncAt, ObservedAt: observedAt}, nil
}

type chronyTrackingEvidence struct {
	stratum               int
	lastOffsetSeconds     float64
	rootDispersionSeconds float64
	referenceTime         time.Time
	leapStatus            string
}

func parseChronyTrackingEvidence(output string) (chronyTrackingEvidence, error) {
	values := map[string]string{}
	for _, line := range strings.Split(output, "\n") {
		key, value, found := strings.Cut(line, ":")
		if found {
			values[strings.TrimSpace(key)] = strings.TrimSpace(value)
		}
	}
	stratum, err := strconv.Atoi(values["Stratum"])
	if err != nil {
		return chronyTrackingEvidence{}, fmt.Errorf("Chrony tracking evidence has no valid Stratum")
	}
	lastOffset, err := parseChronySeconds(values["Last offset"])
	if err != nil {
		return chronyTrackingEvidence{}, fmt.Errorf("Chrony tracking evidence has no valid Last offset: %w", err)
	}
	rootDispersion, err := parseChronySeconds(values["Root dispersion"])
	if err != nil {
		return chronyTrackingEvidence{}, fmt.Errorf("Chrony tracking evidence has no valid Root dispersion: %w", err)
	}
	referenceTime, err := parseChronyReferenceTime(values["Ref time (UTC)"])
	if err != nil {
		return chronyTrackingEvidence{}, fmt.Errorf("Chrony tracking evidence has no valid Ref time (UTC): %w", err)
	}
	leapStatus := values["Leap status"]
	if leapStatus == "" {
		return chronyTrackingEvidence{}, fmt.Errorf("Chrony tracking evidence has no Leap status")
	}
	return chronyTrackingEvidence{stratum: stratum, lastOffsetSeconds: lastOffset, rootDispersionSeconds: rootDispersion, referenceTime: referenceTime, leapStatus: leapStatus}, nil
}

func parseChronySeconds(value string) (float64, error) {
	fields := strings.Fields(value)
	if len(fields) != 2 || fields[1] != "seconds" {
		return 0, fmt.Errorf("expected seconds value")
	}
	return strconv.ParseFloat(fields[0], 64)
}

func parseChronyReferenceTime(value string) (time.Time, error) {
	for _, layout := range []string{"Mon Jan 2 15:04:05 2006", "Mon Jan _2 15:04:05 2006"} {
		if parsed, err := time.ParseInLocation(layout, value, time.UTC); err == nil {
			return parsed, nil
		}
	}
	return time.Time{}, fmt.Errorf("unsupported Chrony UTC reference time %q", value)
}

func validChronyExecutablePath(value string) bool {
	return filepath.IsAbs(value) && filepath.Clean(value) == value && value != "/"
}

func chronyIssue(spec guestruntimedomain.TimeAuthoritySpec, code string, message string, retryable bool) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: spec.Source.SourceID}
}

func failedChronyQuality(node guestruntimedomain.NodeReference, observedAt string, issue guestruntimedomain.Issue) guestruntimedomain.ClockQuality {
	return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "failed", ObservedAt: observedAt, Issue: &issue}
}

var _ guestruntimeapplication.GuestRuntimeTimeAuthorityProvider = (*ChronyTrackingTimeAuthorityProvider)(nil)
