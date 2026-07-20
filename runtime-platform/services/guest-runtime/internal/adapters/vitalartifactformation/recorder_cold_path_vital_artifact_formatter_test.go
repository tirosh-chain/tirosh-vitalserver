package vitalartifactformation

import (
	"bytes"
	"compress/gzip"
	"compress/zlib"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"io"
	"testing"
)

func TestRecorderColdPathVitalArtifactFormatterFormsLegacyParserCompatibleVitalBytes(t *testing.T) {
	packetSequence := coldPathSequenceForTest(t, `{
  "vrcode":"LAB-recorder-a",
  "rooms":{"Lab bed":{"roomname":"Lab bed","trks":[
    {"name":"HR","dname":"VitalServer Lab","montype":"ECG_HR","type":"num","unit":"/min","recs":[{"dt":1710000000,"val":75}]},
    {"name":"ECG","dname":"VitalServer Lab","montype":"ECG_WAV","type":"wav","srate":2,"unit":"mV","mindisp":-1,"maxdisp":1,"recs":[{"dt":1710000000,"val":[0.1,0.2]}]}
  ]}}
}`, true)

	artifact, err := (RecorderColdPathVitalArtifactFormatter{}).FormVitalArtifact(packetSequence)
	if err != nil {
		t.Fatalf("FormVitalArtifact() error = %v", err)
	}
	if len(artifact) == 0 {
		t.Fatal("FormVitalArtifact() returned no Vital bytes")
	}
	payload := decompressedVitalPayload(t, artifact)
	if got := string(payload[:4]); got != "VITA" {
		t.Fatalf("Vital signature = %q, want VITA", got)
	}
	if got := binary.LittleEndian.Uint32(payload[4:8]); got != 3 {
		t.Fatalf("Vital version = %d, want 3", got)
	}
	if got := binary.LittleEndian.Uint16(payload[8:10]); got != 10 {
		t.Fatalf("Vital header length = %d, want legacy 10", got)
	}
	packets := parseVitalPackets(t, payload[20:])
	if packets.trackInformation != 2 || packets.records != 2 || packets.devices != 1 {
		t.Fatalf("Vital packet counts = %#v, want 1 device, 2 track definitions, 2 records", packets)
	}
}

func TestRecorderColdPathVitalArtifactFormatterRejectsUnparseablePacketInsteadOfCreatingAnEmptyArtifact(t *testing.T) {
	packetSequence := coldPathSequenceForTest(t, "not-a-Lab-frame", false)
	artifact, err := (RecorderColdPathVitalArtifactFormatter{}).FormVitalArtifact(packetSequence)
	if err == nil {
		t.Fatalf("FormVitalArtifact() artifact = %x, want error", artifact)
	}
}

func coldPathSequenceForTest(t *testing.T, rawFrame string, compress bool) []byte {
	t.Helper()
	payload := []byte(rawFrame)
	if compress {
		var encoded bytes.Buffer
		writer := zlib.NewWriter(&encoded)
		if _, err := writer.Write(payload); err != nil {
			t.Fatalf("write compressed test frame: %v", err)
		}
		if err := writer.Close(); err != nil {
			t.Fatalf("close compressed test frame: %v", err)
		}
		payload = encoded.Bytes()
	}
	line := map[string]string{
		"ingressReceiptId": "ingress-test-1",
		"packetId":         "packet-test-1",
		"receivedAt":       "2026-07-19T00:00:00Z",
		"payloadEncoding":  "binary",
		"payloadBase64":    base64.StdEncoding.EncodeToString(payload),
	}
	encoded, err := json.Marshal(line)
	if err != nil {
		t.Fatalf("encode test packet sequence: %v", err)
	}
	return append(encoded, '\n')
}

func decompressedVitalPayload(t *testing.T, artifact []byte) []byte {
	t.Helper()
	reader, err := gzip.NewReader(bytes.NewReader(artifact))
	if err != nil {
		t.Fatalf("open generated Vital gzip: %v", err)
	}
	payload, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("read generated Vital gzip: %v", err)
	}
	if err := reader.Close(); err != nil {
		t.Fatalf("close generated Vital gzip: %v", err)
	}
	return payload
}

type vitalPacketCounts struct {
	devices          int
	trackInformation int
	records          int
}

func parseVitalPackets(t *testing.T, payload []byte) vitalPacketCounts {
	t.Helper()
	counts := vitalPacketCounts{}
	for len(payload) > 0 {
		if len(payload) < 5 {
			t.Fatal("generated Vital packet header is truncated")
		}
		kind := payload[0]
		length := int(binary.LittleEndian.Uint32(payload[1:5]))
		payload = payload[5:]
		if length > len(payload) {
			t.Fatal("generated Vital packet payload is truncated")
		}
		switch kind {
		case 9:
			counts.devices++
		case 0:
			counts.trackInformation++
		case 1:
			counts.records++
		}
		payload = payload[length:]
	}
	return counts
}
