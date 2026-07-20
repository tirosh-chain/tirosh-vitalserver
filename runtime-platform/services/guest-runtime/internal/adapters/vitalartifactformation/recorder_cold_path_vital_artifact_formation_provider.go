package vitalartifactformation

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const recorderGatewayColdPathPacketSequenceMediaType = "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl"

// RecorderColdPathVitalArtifactFormationProvider is the adapter that owns the
// binary Vital format boundary. Its sole input is a receipt-verified Gateway
// sequence supplied by the application service.
type RecorderColdPathVitalArtifactFormationProvider struct {
	formatter RecorderColdPathVitalArtifactFormatter
}

func NewRecorderColdPathVitalArtifactFormationProvider() *RecorderColdPathVitalArtifactFormationProvider {
	return &RecorderColdPathVitalArtifactFormationProvider{}
}

func (provider *RecorderColdPathVitalArtifactFormationProvider) FormVitalArtifact(_ context.Context, source guestruntimedomain.StoppedRecorderSource, packetSequence guestruntimedomain.FinalizedRecorderColdPathPacketSequence) ([]byte, guestruntimedomain.EvidenceReference, error) {
	if provider == nil || source.RecorderGatewayRecorderID == "" || packetSequence.FinalizationReceiptID == "" || packetSequence.RecorderID != source.RecorderGatewayRecorderID || packetSequence.MediaType != recorderGatewayColdPathPacketSequenceMediaType || len(packetSequence.Bytes) == 0 {
		return nil, guestruntimedomain.EvidenceReference{}, fmt.Errorf("Recorder Gateway cold-path source is not complete for Vital artifact formation")
	}
	payload, err := provider.formatter.FormVitalArtifact(packetSequence.Bytes)
	if err != nil {
		return nil, guestruntimedomain.EvidenceReference{}, err
	}
	return payload, guestruntimedomain.EvidenceReference{Kind: "recorder-gateway-cold-path-finalization-receipt", ID: packetSequence.FinalizationReceiptID}, nil
}

var _ guestruntimeapplication.GuestRuntimeVitalArtifactFormationProvider = (*RecorderColdPathVitalArtifactFormationProvider)(nil)
