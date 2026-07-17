package guestruntimeapplication_test

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/externalupstreamobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/outboundrelayobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func integrationReference(kind string, id string) guestruntimedomain.IntegrationProviderReference {
	return guestruntimedomain.IntegrationProviderReference{Kind: kind, ID: id, CapabilityRevision: 1}
}

func externalCommand(requestID string, integrationID string, reference guestruntimedomain.IntegrationProviderReference) guestruntimedomain.ExternalUpstreamApplyCommand {
	return guestruntimedomain.ExternalUpstreamApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                requestID,
		IntegrationID:            integrationID,
		ExpectedResourceRevision: 0,
		Spec: guestruntimedomain.ExternalUpstreamSpec{
			Provider:          reference,
			EndpointReference: guestruntimedomain.ResourceReference{ResourceType: "external-endpoint", ResourceID: "vitalserver-primary"},
		},
	}
}

func relayCommand(requestID string, targetID string, reference guestruntimedomain.IntegrationProviderReference) guestruntimedomain.OutboundRelayApplyCommand {
	return guestruntimedomain.OutboundRelayApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                requestID,
		TargetID:                 targetID,
		ExpectedResourceRevision: 0,
		Spec: guestruntimedomain.OutboundRelayTargetSpec{
			Provider:          reference,
			EndpointReference: guestruntimedomain.ResourceReference{ResourceType: "relay-endpoint", ResourceID: "analytics-consumer"},
		},
	}
}

func newExternalFixture(t *testing.T, mode string) (*gueststatesqliterepository.GuestRuntimeStateSQLiteRepository, *guestruntimeapplication.GuestRuntimeExternalUpstreamApplicationService, *guestruntimeapplication.GuestRuntimeTopologyApplicationService, guestruntimedomain.IntegrationProviderReference) {
	t.Helper()
	repository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open sqlite repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	reference := integrationReference("external-capability-profile", "external-vitalserver")
	provider, err := externalupstreamobservationprovider.NewConfiguredExternalUpstreamObservationProfile(reference, mode)
	if err != nil {
		t.Fatalf("new external provider: %v", err)
	}
	clock := fixedClock{now: time.Date(2026, 7, 17, 8, 0, 0, 0, time.UTC)}
	identifiers := &sequentialIdentifiers{}
	external, err := guestruntimeapplication.NewGuestRuntimeExternalUpstreamApplicationService(repository, provider, clock, identifiers)
	if err != nil {
		t.Fatalf("new external service: %v", err)
	}
	topology, err := guestruntimeapplication.NewGuestRuntimeTopologyApplicationServiceWithExternalUpstreamReader(repository, external, clock, identifiers, "test", "guest-test")
	if err != nil {
		t.Fatalf("new topology service: %v", err)
	}
	return repository, external, topology, reference
}

func TestExternalIntegrationPublishesIndependentCapabilityAndTopologyConsumesIt(t *testing.T) {
	repository, external, topology, reference := newExternalFixture(t, externalupstreamobservationprovider.ModeAvailable)
	operation, rejection, admissionFailure := external.ApplyExternalUpstreamIntegration(context.Background(), externalCommand("external-apply-1", "external-primary", reference))
	if rejection != nil || admissionFailure != nil || operation.State != "succeeded" {
		t.Fatalf("external apply operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	integrationRead := external.ReadExternalUpstreamIntegrationDocument(context.Background(), "external-primary")
	if integrationRead.State != "available" {
		t.Fatalf("integration read=%+v", integrationRead)
	}
	integration := integrationRead.Value.(guestruntimedomain.ExternalUpstreamIntegration)
	if integration.Status.State != "available" || integration.Status.Connection.State != "reachable" || integration.Status.CapabilityDocumentReference == nil {
		t.Fatalf("integration status=%+v", integration.Status)
	}
	capability, err := repository.ReadExternalUpstreamCapabilityDocument(context.Background(), integration.ID)
	if err != nil {
		t.Fatalf("read external capability: %v", err)
	}
	assertCapabilityState(t, capability.Commands, "upstream.lifecycle.start", "unsupported")
	assertCapabilityState(t, capability.Commands, "upstream.lifecycle.stop", "unsupported")
	assertCapabilityState(t, capability.Commands, "upstream.update", "unsupported")
	assertCapabilityState(t, capability.Commands, "upstream.backup", "unsupported")

	topologyCommand := guestruntimedomain.TopologyApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                "topology-apply-1",
		TopologyID:               "primary-topology",
		ExpectedResourceRevision: 0,
		Spec: guestruntimedomain.RuntimeTopologySpec{
			ProfileKind:         "external-upstream",
			ProviderKind:        "vitalserver",
			EndpointReference:   guestruntimedomain.ResourceReference{ResourceType: guestruntimedomain.ExternalUpstreamIntegrationResourceType, ResourceID: integration.ID},
			CredentialReference: nil,
		},
	}
	topologyOperation, rejection, admissionFailure := topology.ApplyRuntimeTopology(context.Background(), topologyCommand)
	if rejection != nil || admissionFailure != nil || topologyOperation.State != "succeeded" {
		t.Fatalf("topology apply operation=%+v rejection=%+v admissionFailure=%+v", topologyOperation, rejection, admissionFailure)
	}
	capabilityRead := topology.ReadRuntimeTopologyCapabilityDocument(context.Background())
	if capabilityRead.State != "available" {
		t.Fatalf("topology capability read=%+v", capabilityRead)
	}
	published := capabilityRead.Value.(guestruntimedomain.CapabilityDocument)
	if published.ID != capability.ID || published.Provider.ID != reference.ID {
		t.Fatalf("external capability=%+v published=%+v", capability, published)
	}
}

func TestRelayIsIndependentFromExternalTopology(t *testing.T) {
	repository, external, topology, externalReference := newExternalFixture(t, externalupstreamobservationprovider.ModeUnavailable)
	externalOperation, rejection, admissionFailure := external.ApplyExternalUpstreamIntegration(context.Background(), externalCommand("external-unavailable-1", "external-primary", externalReference))
	if rejection != nil || admissionFailure != nil || externalOperation.State != "succeeded" {
		t.Fatalf("external unavailable operation=%+v rejection=%+v admissionFailure=%+v", externalOperation, rejection, admissionFailure)
	}
	topologyOperation, rejection, admissionFailure := topology.ApplyRuntimeTopology(context.Background(), guestruntimedomain.TopologyApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                "topology-unavailable-1",
		TopologyID:               "primary-topology",
		ExpectedResourceRevision: 0,
		Spec: guestruntimedomain.RuntimeTopologySpec{
			ProfileKind:       "external-upstream",
			ProviderKind:      "vitalserver",
			EndpointReference: guestruntimedomain.ResourceReference{ResourceType: guestruntimedomain.ExternalUpstreamIntegrationResourceType, ResourceID: "external-primary"},
		},
	})
	if rejection != nil || admissionFailure != nil || topologyOperation.State != "succeeded" {
		t.Fatalf("unavailable topology operation=%+v rejection=%+v admissionFailure=%+v", topologyOperation, rejection, admissionFailure)
	}
	before := topology.ReadRuntimeTopology(context.Background()).Value.(guestruntimedomain.RuntimeTopology)
	if before.Status.ReadState != "unavailable" {
		t.Fatalf("topology must retain explicit unavailable integration observation=%+v", before.Status)
	}

	// The relay has its own provider and its own state owner. It is available
	// even while the upstream is explicitly unavailable.
	relayReference := integrationReference("outbound-relay-profile", "analytics-relay")
	relayProvider, err := outboundrelayobservationprovider.NewConfiguredOutboundRelayObservationProfile(relayReference, outboundrelayobservationprovider.ModeAvailable)
	if err != nil {
		t.Fatal(err)
	}
	// The services share a SQLite file but only receive their own repository
	// interfaces. Relay never receives ExternalUpstreamIntegration state.
	relay, err := guestruntimeapplication.NewGuestRuntimeOutboundRelayApplicationService(repository, relayProvider, fixedClock{now: time.Date(2026, 7, 17, 8, 1, 0, 0, time.UTC)}, guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{})
	if err != nil {
		t.Fatal(err)
	}
	relayOperation, rejection, admissionFailure := relay.ApplyOutboundRelayTarget(context.Background(), relayCommand("relay-apply-1", "analytics-relay-target", relayReference))
	if rejection != nil || admissionFailure != nil || relayOperation.State != "succeeded" {
		t.Fatalf("relay apply operation=%+v rejection=%+v admissionFailure=%+v", relayOperation, rejection, admissionFailure)
	}
	relayRead := relay.ReadOutboundRelayTarget(context.Background(), "analytics-relay-target")
	if relayRead.State != "available" {
		t.Fatalf("relay read=%+v", relayRead)
	}
	target := relayRead.Value.(guestruntimedomain.OutboundRelayTarget)
	if target.Status.State != "available" || target.Status.AcknowledgementReference == nil {
		t.Fatalf("relay target=%+v", target)
	}
	externalRead := external.ReadExternalUpstreamIntegrationDocument(context.Background(), "external-primary")
	integration := externalRead.Value.(guestruntimedomain.ExternalUpstreamIntegration)
	if integration.Status.State != "unavailable" {
		t.Fatalf("relay changed external integration=%+v", integration.Status)
	}
	after := topology.ReadRuntimeTopology(context.Background()).Value.(guestruntimedomain.RuntimeTopology)
	if after.Status.ReadState != "unavailable" || after.ResourceRevision != before.ResourceRevision || after.Status.ObservedAt != before.Status.ObservedAt {
		t.Fatalf("relay changed RuntimeTopology observation before=%+v after=%+v", before, after)
	}
}

func TestExternalProviderOutcomeUnknownLeavesOnlyDurableRunningOperation(t *testing.T) {
	repository, external, _, reference := newExternalFixture(t, externalupstreamobservationprovider.ModeOutcomeUnknown)
	operation, rejection, admissionFailure := external.ApplyExternalUpstreamIntegration(context.Background(), externalCommand("external-unknown-1", "external-primary", reference))
	if rejection != nil || admissionFailure != nil || operation.State != "running" {
		t.Fatalf("operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if read := external.ReadExternalUpstreamIntegrationDocument(context.Background(), "external-primary"); read.State != "missing" {
		t.Fatalf("unknown provider outcome wrote integration state=%+v", read)
	}
	persisted, err := repository.ReadExternalUpstreamIntegrationOperationByRequestID(context.Background(), "external-unknown-1")
	if err != nil || persisted.State != "running" {
		t.Fatalf("persisted unknown operation=%+v err=%v", persisted, err)
	}
}

func assertCapabilityState(t *testing.T, capabilities []guestruntimedomain.Capability, name string, state string) {
	t.Helper()
	for _, capability := range capabilities {
		if capability.Name == name {
			if capability.State != state {
				t.Fatalf("capability %s state=%s want=%s", name, capability.State, state)
			}
			return
		}
	}
	t.Fatalf("capability %s is missing", name)
}
