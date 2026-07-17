package hostagentapplication_test

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hoststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type fixedClock struct{ now time.Time }

func (clock fixedClock) Now() time.Time { return clock.now }

type sequentialIdentifiers struct{ next int }

func (identifiers *sequentialIdentifiers) NewRequestCorrelationIdentifier(prefix string) (string, error) {
	identifiers.next++
	return fmt.Sprintf("%s-test-%d", prefix, identifiers.next), nil
}

type unavailableRequestCorrelationIdentifiers struct{}

func (unavailableRequestCorrelationIdentifiers) NewRequestCorrelationIdentifier(string) (string, error) {
	return "", errors.New("request correlation identifier source is unavailable")
}

type fakeProvider struct {
	results map[string]hostagentdomain.ProviderLifecycleResult
	calls   int
}

func (provider *fakeProvider) Execute(_ context.Context, invocation hostagentdomain.PlatformProviderLifecycleInvocation) hostagentdomain.ProviderLifecycleResult {
	request := invocation.Lifecycle
	provider.calls++
	if result, found := provider.results[request.Action]; found {
		return result
	}
	return hostagentdomain.FailedProviderResult(request, "2026-07-17T00:00:00Z", hostagentdomain.Issue{Code: "unexpected-action"})
}

type fakeGuestControl struct {
	probe        hostagentapplication.GuestRuntimeControlHTTPProbeResult
	response     hostagentapplication.GuestRuntimeControlHTTPForwardedResponse
	failure      *hostagentapplication.GuestRuntimeControlHTTPForwardingFailure
	probeCalls   int
	forwardCalls int
}

func (guest *fakeGuestControl) Probe(context.Context, hostagentdomain.GuestRuntimeControlEndpoint) hostagentapplication.GuestRuntimeControlHTTPProbeResult {
	guest.probeCalls++
	return guest.probe
}

func (guest *fakeGuestControl) Forward(_ context.Context, _ hostagentdomain.GuestRuntimeControlEndpoint, _ string, _ string, _ []byte, _ string) (hostagentapplication.GuestRuntimeControlHTTPForwardedResponse, *hostagentapplication.GuestRuntimeControlHTTPForwardingFailure) {
	guest.forwardCalls++
	return guest.response, guest.failure
}

func resultFor(action string, state string) hostagentdomain.ProviderLifecycleResult {
	requestID := "start-request"
	if action == "stop" {
		requestID = "stop-request"
	}
	if action == "reboot" {
		requestID = "reboot-request"
	}
	result := hostagentdomain.ProviderLifecycleResult{
		SchemaVersion: "v1",
		RequestID:     requestID,
		ProviderID:    "guest-vm",
		ObservedState: state,
		ObservedAt:    "2026-07-17T00:00:00Z",
	}
	if state == "failed" || state == "unavailable" {
		result.Issue = &hostagentdomain.Issue{Code: "provider-effect-failed"}
	}
	return result
}

func configuredRepository(t *testing.T) *hoststatesqliterepository.HostAgentStateSQLiteRepository {
	t.Helper()
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "host.sqlite"))
	if err != nil {
		t.Fatalf("open Host state database: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	return repository
}

func newServiceWithRepository(t *testing.T, repository hostagentapplication.HostAgentControlStateRepository, provider *fakeProvider, guest *fakeGuestControl) *hostagentapplication.HostAgentControlApplicationService {
	t.Helper()
	service, err := hostagentapplication.NewHostAgentControlApplicationService(repository, provider, guest, fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}, &sequentialIdentifiers{})
	if err != nil {
		t.Fatalf("new service: %v", err)
	}
	if err := service.InitializeHostAgentControlState(context.Background(), hostagentapplication.HostAgentControlStateInitialization{
		InstallationID:                "host-installation",
		ProductVersion:                "test",
		RuntimeVersion:                "test",
		DataDirectory:                 "/var/lib/vitalserver-helper",
		GuestRuntimeControlEndpointID: "guest-control",
		GuestRuntimeControlHTTPScheme: "http",
		GuestRuntimeControlHTTPHost:   "127.0.0.1",
		GuestRuntimeControlHTTPPort:   18443,
		ProviderKind:                  "macos-virtualization",
		ProviderID:                    "guest-vm",
	}); err != nil {
		t.Fatalf("configure service: %v", err)
	}
	return service
}

func newService(t *testing.T, provider *fakeProvider, guest *fakeGuestControl) *hostagentapplication.HostAgentControlApplicationService {
	t.Helper()
	return newServiceWithRepository(t, configuredRepository(t), provider, guest)
}

func endpoint(t *testing.T, service *hostagentapplication.HostAgentControlApplicationService) hostagentdomain.GuestRuntimeControlEndpoint {
	t.Helper()
	result := service.ReadGuestRuntimeControlEndpoint(context.Background())
	if result.State != "available" {
		t.Fatalf("endpoint read = %+v", result)
	}
	value, ok := result.Value.(hostagentdomain.GuestRuntimeControlEndpoint)
	if !ok {
		t.Fatalf("endpoint value type = %T", result.Value)
	}
	return value
}

func lifecycleCommand(action string, requestID string, revision int) hostagentdomain.GuestLifecycleCommand {
	return hostagentdomain.GuestLifecycleCommand{
		SchemaVersion:                 "v1",
		RequestID:                     requestID,
		GuestRuntimeControlEndpointID: "guest-control",
		ExpectedResourceRevision:      revision,
		Action:                        action,
	}
}

func TestLifecycleAndFacadeKeepProviderAndTransportObservationsSeparate(t *testing.T) {
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{
		"start":  resultFor("start", "running"),
		"stop":   resultFor("stop", "stopped"),
		"reboot": resultFor("reboot", "running"),
	}}
	guest := &fakeGuestControl{
		probe:    hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true},
		response: hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{StatusCode: 200, ContentType: "application/json", Body: []byte("{\n  \"guest\": \"unchanged\"\n}")},
	}
	service := newService(t, provider, guest)

	start, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("start", "start-request", 1))
	if admissionFailure != nil || rejection != nil || start.State != "succeeded" {
		t.Fatalf("start admissionFailure=%+v rejection=%+v operation=%+v", admissionFailure, rejection, start)
	}
	afterStart := endpoint(t, service)
	if afterStart.Provider.State != "running" || afterStart.Transport.State != "not-checked" {
		t.Fatalf("start must only establish provider result: %+v", afterStart)
	}

	forwarded, err := service.ForwardGuestRuntimeControlRead(context.Background(), "/v1/runtime/readiness")
	if err != nil || forwarded.Response == nil || string(forwarded.Response.Body) != "{\n  \"guest\": \"unchanged\"\n}" {
		t.Fatalf("forward outcome err=%v outcome=%+v", err, forwarded)
	}
	afterForward := endpoint(t, service)
	if afterForward.Transport.State != "reachable" || afterForward.Provider.State != "running" {
		t.Fatalf("forward must record only Host transport reachability: %+v", afterForward)
	}

	stop, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("stop", "stop-request", afterForward.ResourceRevision))
	if admissionFailure != nil || rejection != nil || stop.State != "succeeded" {
		t.Fatalf("stop admissionFailure=%+v rejection=%+v operation=%+v", admissionFailure, rejection, stop)
	}
	forwardCallsBeforeStopRead := guest.forwardCalls
	stoppedRead, err := service.ForwardGuestRuntimeControlRead(context.Background(), "/v1/runtime/readiness")
	if err != nil || stoppedRead.ReadResult == nil || stoppedRead.ReadResult.State != "unavailable" {
		t.Fatalf("stopped read err=%v outcome=%+v", err, stoppedRead)
	}
	if guest.forwardCalls != forwardCallsBeforeStopRead {
		t.Fatalf("Host forwarded despite direct provider stopped observation")
	}

	afterStop := endpoint(t, service)
	reboot, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("reboot", "reboot-request", afterStop.ResourceRevision))
	if admissionFailure != nil || rejection != nil || reboot.State != "succeeded" {
		t.Fatalf("reboot admissionFailure=%+v rejection=%+v operation=%+v", admissionFailure, rejection, reboot)
	}
	recovered, err := service.ForwardGuestRuntimeControlRead(context.Background(), "/v1/runtime/readiness")
	if err != nil || recovered.Response == nil {
		t.Fatalf("recovered read err=%v outcome=%+v", err, recovered)
	}
}

func TestGuestCommandForwardFailurePreservesUnknownDelivery(t *testing.T) {
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{}}
	guest := &fakeGuestControl{
		probe:   hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true},
		failure: &hostagentapplication.GuestRuntimeControlHTTPForwardingFailure{Issue: &hostagentdomain.Issue{Code: "guest-control-forward-failed", Retryable: hostagentdomain.Bool(true), Dependency: "guest-control"}},
	}
	service := newService(t, provider, guest)
	outcome, err := service.ForwardGuestRuntimeControlCommand(context.Background(), "/v1/runtime/topology:apply", []byte(`{"schemaVersion":"v1"}`), "application/json", "command-request")
	if err != nil || outcome.Failure == nil {
		t.Fatalf("forward command err=%v outcome=%+v", err, outcome)
	}
	if outcome.Failure.DeliveryDisposition != "unknown" || outcome.Failure.State != "failed" {
		t.Fatalf("forward failure = %+v", outcome.Failure)
	}
	if after := endpoint(t, service); after.Transport.State != "unavailable" {
		t.Fatalf("failed forward did not persist Host transport observation: %+v", after.Transport)
	}
}

func TestLifecycleRevisionConflictDoesNotRunProvider(t *testing.T) {
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{}}
	guest := &fakeGuestControl{probe: hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true}}
	service := newService(t, provider, guest)
	_, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("start", "start-request", 2))
	if admissionFailure != nil || rejection == nil {
		t.Fatalf("revision conflict admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	if rejection.Issue.Code != "resource-revision-conflict" || provider.calls != 0 {
		t.Fatalf("conflict rejection=%+v providerCalls=%d", rejection, provider.calls)
	}
}

func TestMalformedGuestLifecycleCommandPreservesCorrelationIdentifierFailureMeaning(t *testing.T) {
	service, err := hostagentapplication.NewHostAgentControlApplicationService(
		configuredRepository(t),
		&fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{}},
		&fakeGuestControl{},
		fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)},
		unavailableRequestCorrelationIdentifiers{},
	)
	if err != nil {
		t.Fatalf("create Host Agent Control application service: %v", err)
	}

	operation, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(
		context.Background(),
		hostagentdomain.GuestLifecycleCommand{},
	)
	if operation.ID != "" || rejection != nil || admissionFailure == nil {
		t.Fatalf("operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if admissionFailure.AdmissionState != "not-admitted" || admissionFailure.Issue.Code != "host-rejection-correlation-unavailable" {
		t.Fatalf("correlation identifier failure meaning = %+v", admissionFailure)
	}
}

func TestConfigureRejectsAnUnknownProviderInsteadOfSelectingFallback(t *testing.T) {
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{}}
	guest := &fakeGuestControl{}
	repository := configuredRepository(t)
	service, err := hostagentapplication.NewHostAgentControlApplicationService(repository, provider, guest, fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}, &sequentialIdentifiers{})
	if err != nil {
		t.Fatal(err)
	}
	err = service.InitializeHostAgentControlState(context.Background(), hostagentapplication.HostAgentControlStateInitialization{
		InstallationID: "host-installation", ProductVersion: "test", RuntimeVersion: "test", DataDirectory: "/var/lib/vitalserver-helper",
		GuestRuntimeControlEndpointID: "guest-control", GuestRuntimeControlHTTPScheme: "http", GuestRuntimeControlHTTPHost: "127.0.0.1", GuestRuntimeControlHTTPPort: 18443,
		ProviderKind: "unknown-provider", ProviderID: "guest-vm",
	})
	if err == nil || !strings.Contains(err.Error(), "unsupported") {
		t.Fatalf("unknown provider configuration error = %v", err)
	}
}

type commitFailingRepository struct {
	hostagentapplication.HostAgentControlStateRepository
}

func (repository commitFailingRepository) CommitGuestLifecycleOutcome(context.Context, hostagentdomain.GuestRuntimeControlEndpoint, hostagentdomain.Operation) error {
	return errors.New("simulated terminal outcome persistence failure")
}

type createFailingRepository struct {
	hostagentapplication.HostAgentControlStateRepository
}

func (repository createFailingRepository) PersistNewHostOperation(context.Context, hostagentdomain.Operation) error {
	return errors.New("simulated admission persistence failure")
}

func TestLifecycleOutcomePersistenceFailureReturnsDurableRunningOperation(t *testing.T) {
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{
		"start": resultFor("start", "running"),
	}}
	guest := &fakeGuestControl{probe: hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true}}
	repository := configuredRepository(t)
	service := newServiceWithRepository(t, commitFailingRepository{HostAgentControlStateRepository: repository}, provider, guest)

	operation, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("start", "start-request", 1))
	if rejection != nil || admissionFailure != nil || operation.State != "running" {
		t.Fatalf("operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if provider.calls != 1 {
		t.Fatalf("provider calls = %d, want 1", provider.calls)
	}
	persisted := service.ReadHostGuestLifecycleOperation(context.Background(), operation.ID)
	if persisted.State != "available" {
		t.Fatalf("persisted operation read = %+v", persisted)
	}
	persistedOperation, ok := persisted.Value.(hostagentdomain.Operation)
	if !ok || persistedOperation.State != "running" {
		t.Fatalf("persisted operation = %#v", persisted.Value)
	}
	endpointAfterFailure := endpoint(t, service)
	if endpointAfterFailure.ResourceRevision != 1 || endpointAfterFailure.Provider.State != "not-observed" {
		t.Fatalf("uncommitted outcome changed endpoint: %+v", endpointAfterFailure)
	}

	retry, retryRejection, retryAdmissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("start", "start-request", 1))
	if retryRejection != nil || retryAdmissionFailure != nil || retry.ID != operation.ID || retry.State != "running" {
		t.Fatalf("retry=%+v rejection=%+v admissionFailure=%+v", retry, retryRejection, retryAdmissionFailure)
	}
	if provider.calls != 1 {
		t.Fatalf("same requestId replayed provider after uncertain terminal persistence: calls=%d", provider.calls)
	}
}

func TestLifecycleAdmissionWriteFailurePreservesUnknownOperationExistence(t *testing.T) {
	provider := &fakeProvider{results: map[string]hostagentdomain.ProviderLifecycleResult{
		"start": resultFor("start", "running"),
	}}
	guest := &fakeGuestControl{probe: hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true}}
	service := newServiceWithRepository(t, createFailingRepository{HostAgentControlStateRepository: configuredRepository(t)}, provider, guest)

	operation, rejection, admissionFailure := service.ExecuteGuestLifecycleCommand(context.Background(), lifecycleCommand("start", "start-request", 1))
	if operation.ID != "" || rejection != nil || admissionFailure == nil {
		t.Fatalf("operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if admissionFailure.State != "failed" || admissionFailure.AdmissionState != "unknown" || admissionFailure.Issue.Code != "host-state-store-write-outcome-unknown" {
		t.Fatalf("admission failure = %+v", admissionFailure)
	}
	if provider.calls != 0 {
		t.Fatalf("provider called before durable lifecycle admission: calls=%d", provider.calls)
	}
}
