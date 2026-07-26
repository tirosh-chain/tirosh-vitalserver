package timeprovider

import (
	"context"
	"encoding/binary"
	"fmt"
	"math"
	"net"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const ntpEpochOffsetSeconds = 2208988800

// NTPUDPTimeAuthorityProvider measures one Host clock-quality sample against
// an explicitly declared NTP endpoint. It is portable across macOS, Windows,
// and Linux because it speaks NTP directly; it does not inspect an OS daemon
// or silently select a system time service. It also does not discipline the
// Host clock: its result is quality evidence only.
type NTPUDPTimeAuthorityProvider struct {
	serverAddress              string
	requestTimeout             time.Duration
	expectedSource             hostagentdomain.TimeSource
	maximumOffsetMilliseconds  float64
	maximumUncertaintyMillisec float64
}

func NewNTPUDPTimeAuthorityProvider(serverAddress string, requestTimeout time.Duration, expectedSource hostagentdomain.TimeSource, maximumOffsetMilliseconds float64, maximumUncertaintyMilliseconds float64) (*NTPUDPTimeAuthorityProvider, error) {
	if _, _, err := net.SplitHostPort(serverAddress); err != nil || strings.TrimSpace(serverAddress) != serverAddress {
		return nil, fmt.Errorf("NTP server address must be an explicit host:port")
	}
	if requestTimeout <= 0 {
		return nil, fmt.Errorf("NTP request timeout must be positive")
	}
	if (expectedSource.Profile != "enterprise-ntp" && expectedSource.Profile != "helper-ntp") || !hostagentdomain.ValidIdentifier(expectedSource.SourceID) {
		return nil, fmt.Errorf("NTP source identity must be explicit and valid")
	}
	if maximumOffsetMilliseconds < 0 || math.IsNaN(maximumOffsetMilliseconds) || math.IsInf(maximumOffsetMilliseconds, 0) || maximumUncertaintyMilliseconds < 0 || math.IsNaN(maximumUncertaintyMilliseconds) || math.IsInf(maximumUncertaintyMilliseconds, 0) {
		return nil, fmt.Errorf("NTP quality thresholds must be finite and non-negative")
	}
	return &NTPUDPTimeAuthorityProvider{serverAddress: serverAddress, requestTimeout: requestTimeout, expectedSource: expectedSource, maximumOffsetMilliseconds: maximumOffsetMilliseconds, maximumUncertaintyMillisec: maximumUncertaintyMilliseconds}, nil
}

func (provider *NTPUDPTimeAuthorityProvider) ObserveTimeAuthority(ctx context.Context, node hostagentdomain.NodeReference, spec hostagentdomain.TimeAuthoritySpec, observedAt string) (hostagentdomain.ClockQuality, error) {
	if provider == nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-provider-not-composed", "NTP UDP time authority provider is not composed", false), nil
	}
	if spec.Source != provider.expectedSource {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-source-does-not-match-deployment", "requested Time Authority source does not match the explicit Host NTP deployment source", false), nil
	}
	connection, err := (&net.Dialer{}).DialContext(ctx, "udp", provider.serverAddress)
	if err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-server-unavailable", "could not open UDP connection to configured NTP server: "+err.Error(), true), nil
	}
	defer connection.Close()
	deadline := time.Now().Add(provider.requestTimeout)
	if contextDeadline, hasDeadline := ctx.Deadline(); hasDeadline && contextDeadline.Before(deadline) {
		deadline = contextDeadline
	}
	if err := connection.SetDeadline(deadline); err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-request-deadline-failed", err.Error(), true), nil
	}
	request := make([]byte, 48)
	request[0] = 0x23 // LI=0, version=4, client mode=3.
	requestSentAt := time.Now()
	if _, err := connection.Write(request); err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-request-send-failed", err.Error(), true), nil
	}
	response := make([]byte, 48)
	count, err := connection.Read(response)
	responseReceivedAt := time.Now()
	if err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-server-unavailable", "configured NTP server did not return a response: "+err.Error(), true), nil
	}
	if count < 48 {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-response-invalid", "configured NTP server returned a truncated response", false), nil
	}
	li, mode, stratum := response[0]>>6, response[0]&0x7, int(response[1])
	if mode != 4 && mode != 5 {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-response-invalid", "configured NTP server response mode is not server or broadcast", false), nil
	}
	if li == 3 || stratum == 0 || stratum > 15 {
		return hostNTPUnsynchronizedQuality(node, spec.Source, observedAt, "ntp-server-unsynchronized", "configured NTP server did not report synchronized stratum evidence"), nil
	}
	referenceAt, err := decodeNTPTime(response[16:24])
	if err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-reference-time-invalid", err.Error(), false), nil
	}
	serverReceivedAt, err := decodeNTPTime(response[32:40])
	if err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-receive-time-invalid", err.Error(), false), nil
	}
	serverTransmittedAt, err := decodeNTPTime(response[40:48])
	if err != nil {
		return hostNTPFailedQuality(node, spec.Source, observedAt, "ntp-transmit-time-invalid", err.Error(), false), nil
	}
	offset := (serverReceivedAt.Sub(requestSentAt) + serverTransmittedAt.Sub(responseReceivedAt)).Seconds() * 500
	roundTrip := responseReceivedAt.Sub(requestSentAt) - serverTransmittedAt.Sub(serverReceivedAt)
	if roundTrip < 0 {
		roundTrip = 0
	}
	rootDispersion := float64(binary.BigEndian.Uint32(response[8:12])) / 65536.0 * 1000
	uncertainty := rootDispersion + roundTrip.Seconds()*500
	if math.Abs(offset) > provider.maximumOffsetMilliseconds || uncertainty > provider.maximumUncertaintyMillisec {
		return hostNTPUnsynchronizedQuality(node, spec.Source, observedAt, "ntp-quality-threshold-exceeded", "configured NTP sample exceeded the declared Host clock-quality threshold"), nil
	}
	lastSyncAt := referenceAt.UTC().Format(time.RFC3339Nano)
	return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "synchronized", Source: &spec.Source, Stratum: &stratum, OffsetMs: &offset, UncertaintyMs: &uncertainty, LastSyncAt: &lastSyncAt, ObservedAt: observedAt}, nil
}

func decodeNTPTime(value []byte) (time.Time, error) {
	if len(value) != 8 {
		return time.Time{}, fmt.Errorf("NTP timestamp must contain eight bytes")
	}
	seconds := binary.BigEndian.Uint32(value[:4])
	fraction := binary.BigEndian.Uint32(value[4:])
	if seconds == 0 && fraction == 0 {
		return time.Time{}, fmt.Errorf("NTP timestamp must not be zero")
	}
	nanoseconds := (uint64(fraction) * uint64(time.Second)) >> 32
	return time.Unix(int64(seconds)-ntpEpochOffsetSeconds, int64(nanoseconds)).UTC(), nil
}

func hostNTPFailedQuality(node hostagentdomain.NodeReference, source hostagentdomain.TimeSource, observedAt string, code string, message string, retryable bool) hostagentdomain.ClockQuality {
	issue := hostagentdomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: source.SourceID}
	return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "failed", Source: &source, ObservedAt: observedAt, Issue: &issue}
}

func hostNTPUnsynchronizedQuality(node hostagentdomain.NodeReference, source hostagentdomain.TimeSource, observedAt string, code string, message string) hostagentdomain.ClockQuality {
	retryable := true
	issue := hostagentdomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: source.SourceID}
	return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "unsynchronized", Source: &source, ObservedAt: observedAt, Issue: &issue}
}

var _ hostagentapplication.HostTimeAuthorityProvider = (*NTPUDPTimeAuthorityProvider)(nil)
