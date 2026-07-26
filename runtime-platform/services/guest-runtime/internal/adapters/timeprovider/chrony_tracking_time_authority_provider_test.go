package timeprovider

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type fixedChronyTrackingCommandRunner struct {
	output []byte
	err    error
}

func (runner fixedChronyTrackingCommandRunner) Run(_ context.Context, executablePath string, arguments ...string) ([]byte, error) {
	if executablePath != "/usr/bin/chronyc" || len(arguments) != 2 || arguments[0] != "tracking" || arguments[1] != "-n" {
		return nil, errors.New("unexpected Chrony invocation")
	}
	return runner.output, runner.err
}

func TestChronyTrackingTimeAuthorityProviderReturnsCompleteSynchronizedEvidence(t *testing.T) {
	provider := newChronyTrackingTimeAuthorityProviderForTest("/usr/bin/chronyc", fixedChronyTrackingCommandRunner{output: []byte(`Reference ID    : 203.0.113.10 (ntp.example.test)
Stratum         : 2
Ref time (UTC)  : Sat Jul 19 01:02:03 2026
System time     : 0.000001234 seconds fast of NTP time
Last offset     : -0.000250000 seconds
RMS offset      : 0.000300000 seconds
Root delay      : 0.001000000 seconds
Root dispersion : 0.000750000 seconds
Leap status     : Normal
`)})
	quality, err := provider.ObserveTimeAuthority(context.Background(), chronyGuestNode(), chronyTimeAuthoritySpec(), "2026-07-19T01:02:04Z")
	if err != nil || quality.State != "synchronized" || quality.Source == nil || quality.Stratum == nil || *quality.Stratum != 2 || quality.OffsetMs == nil || *quality.OffsetMs != -0.25 || quality.UncertaintyMs == nil || *quality.UncertaintyMs != 0.75 || quality.LastSyncAt == nil || *quality.LastSyncAt != "2026-07-19T01:02:03Z" {
		t.Fatalf("Chrony quality=%+v error=%v", quality, err)
	}
}

func TestChronyTrackingTimeAuthorityProviderReportsUnsynchronizedWithoutInventingEvidence(t *testing.T) {
	provider := newChronyTrackingTimeAuthorityProviderForTest("/usr/bin/chronyc", fixedChronyTrackingCommandRunner{output: []byte(`Stratum         : 0
Ref time (UTC)  : Sat Jul 19 01:02:03 2026
Last offset     : 0.000250000 seconds
Root dispersion : 0.000750000 seconds
Leap status     : Not synchronised
`)})
	quality, err := provider.ObserveTimeAuthority(context.Background(), chronyGuestNode(), chronyTimeAuthoritySpec(), "2026-07-19T01:02:04Z")
	if err != nil || quality.State != "unsynchronized" || quality.Source != nil || quality.Stratum != nil || quality.Issue == nil || quality.Issue.Code != "ntp-source-unsynchronized" {
		t.Fatalf("unsynchronized Chrony quality=%+v error=%v", quality, err)
	}
}

func TestChronyTrackingTimeAuthorityProviderReportsMalformedEvidenceAsFailure(t *testing.T) {
	provider := newChronyTrackingTimeAuthorityProviderForTest("/usr/bin/chronyc", fixedChronyTrackingCommandRunner{output: []byte("Stratum : 2\n")})
	quality, err := provider.ObserveTimeAuthority(context.Background(), chronyGuestNode(), chronyTimeAuthoritySpec(), "2026-07-19T01:02:04Z")
	if err != nil || quality.State != "failed" || quality.Issue == nil || quality.Issue.Code != "ntp-probe-evidence-invalid" {
		t.Fatalf("malformed Chrony quality=%+v error=%v", quality, err)
	}
}

func TestNewChronyTrackingTimeAuthorityProviderRejectsImplicitExecutableLookup(t *testing.T) {
	for _, path := range []string{"", "chronyc", "/usr/bin/../bin/chronyc", "/"} {
		if _, err := NewChronyTrackingTimeAuthorityProvider(path, time.Second); err == nil {
			t.Fatalf("Chrony executable path %q was accepted", path)
		}
	}
	if _, err := NewChronyTrackingTimeAuthorityProvider("/usr/bin/chronyc", 0); err == nil {
		t.Fatal("non-positive Chrony timeout was accepted")
	}
}

func chronyGuestNode() guestruntimedomain.NodeReference {
	return guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-a"}
}

func chronyTimeAuthoritySpec() guestruntimedomain.TimeAuthoritySpec {
	return guestruntimedomain.TimeAuthoritySpec{Profile: "enterprise-ntp", Source: guestruntimedomain.TimeSource{Profile: "enterprise-ntp", SourceID: "ntp-primary"}}
}
