package timeprovider

import (
	"context"
	"encoding/binary"
	"net"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

func TestNTPUDPTimeAuthorityProviderReportsMeasuredSynchronizedQuality(t *testing.T) {
	server := startNTPTestServer(t, func(response []byte) {
		response[0], response[1] = 0x24, 2
		putNTPTime(response[16:24], time.Date(2026, 7, 19, 0, 0, 0, 0, time.UTC))
		putNTPTime(response[32:40], time.Now().UTC())
		putNTPTime(response[40:48], time.Now().UTC())
	})
	defer server.Close()
	provider, err := NewNTPUDPTimeAuthorityProvider(server.LocalAddr().String(), time.Second, hostNTPTestSource(), 10_000, 10_000)
	if err != nil {
		t.Fatal(err)
	}
	quality, err := provider.ObserveTimeAuthority(context.Background(), hostagentdomain.NodeReference{Kind: "host", ID: "host-a"}, hostNTPTestSpec(), "2026-07-19T00:00:00Z")
	if err != nil || quality.State != "synchronized" || quality.Source == nil || *quality.Source != hostNTPTestSource() || quality.Stratum == nil || *quality.Stratum != 2 || quality.OffsetMs == nil || quality.UncertaintyMs == nil || quality.LastSyncAt == nil {
		t.Fatalf("quality=%+v error=%v", quality, err)
	}
}

func TestNTPUDPTimeAuthorityProviderDoesNotClaimSynchronizedForBadServerEvidence(t *testing.T) {
	server := startNTPTestServer(t, func(response []byte) { response[0], response[1] = 0xe4, 0 })
	defer server.Close()
	provider, err := NewNTPUDPTimeAuthorityProvider(server.LocalAddr().String(), time.Second, hostNTPTestSource(), 10_000, 10_000)
	if err != nil {
		t.Fatal(err)
	}
	quality, err := provider.ObserveTimeAuthority(context.Background(), hostagentdomain.NodeReference{Kind: "host", ID: "host-a"}, hostNTPTestSpec(), "2026-07-19T00:00:00Z")
	if err != nil || quality.State != "unsynchronized" || quality.Issue == nil || quality.Issue.Code != "ntp-server-unsynchronized" {
		t.Fatalf("quality=%+v error=%v", quality, err)
	}
}

func TestNTPUDPTimeAuthorityProviderRejectsImplicitEndpointAndSource(t *testing.T) {
	if _, err := NewNTPUDPTimeAuthorityProvider("pool.ntp.org", time.Second, hostNTPTestSource(), 1, 1); err == nil {
		t.Fatal("accepted endpoint without port")
	}
	if _, err := NewNTPUDPTimeAuthorityProvider("127.0.0.1:123", 0, hostNTPTestSource(), 1, 1); err == nil {
		t.Fatal("accepted zero timeout")
	}
	provider, err := NewNTPUDPTimeAuthorityProvider("127.0.0.1:123", time.Second, hostNTPTestSource(), 1, 1)
	if err != nil {
		t.Fatal(err)
	}
	quality, err := provider.ObserveTimeAuthority(context.Background(), hostagentdomain.NodeReference{Kind: "host", ID: "host-a"}, hostagentdomain.TimeAuthoritySpec{Profile: "enterprise-ntp", Source: hostagentdomain.TimeSource{Profile: "enterprise-ntp", SourceID: "different-source"}}, "2026-07-19T00:00:00Z")
	if err != nil || quality.State != "failed" || quality.Issue == nil || quality.Issue.Code != "ntp-source-does-not-match-deployment" {
		t.Fatalf("quality=%+v error=%v", quality, err)
	}
}

func hostNTPTestSource() hostagentdomain.TimeSource {
	return hostagentdomain.TimeSource{Profile: "enterprise-ntp", SourceID: "host-ntp-primary"}
}
func hostNTPTestSpec() hostagentdomain.TimeAuthoritySpec {
	return hostagentdomain.TimeAuthoritySpec{Profile: "enterprise-ntp", Source: hostNTPTestSource()}
}

func startNTPTestServer(t *testing.T, populate func([]byte)) *net.UDPConn {
	t.Helper()
	server, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		request := make([]byte, 48)
		count, remote, err := server.ReadFromUDP(request)
		if err != nil || count < 48 {
			return
		}
		response := make([]byte, 48)
		populate(response)
		_, _ = server.WriteToUDP(response, remote)
	}()
	return server
}

func putNTPTime(destination []byte, value time.Time) {
	seconds := uint64(value.UTC().Unix() + ntpEpochOffsetSeconds)
	fraction := uint64(value.UTC().Nanosecond()) << 32 / uint64(time.Second)
	binary.BigEndian.PutUint32(destination[:4], uint32(seconds))
	binary.BigEndian.PutUint32(destination[4:], uint32(fraction))
}
