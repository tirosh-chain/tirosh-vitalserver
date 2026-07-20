package platformctlcommand_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/platformctl/internal/platformctlcommand"
)

func TestParseGuestLifecycleCommandPreservesOperatorSuppliedCorrelation(t *testing.T) {
	invocation, err := platformctlcommand.Parse([]string{
		"--control-endpoint", "http://127.0.0.1:18280",
		"guest", "start",
		"--guest-runtime-control-endpoint-id", "guest-control-1",
		"--expected-resource-revision", "7",
		"--request-id", "operator-start-1",
	})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	if invocation.Method != http.MethodPost || invocation.Route != "/v1/platform/guest:start" {
		t.Fatalf("invocation = %#v", invocation)
	}
	var body map[string]any
	if err := json.Unmarshal(invocation.Body, &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["requestId"] != "operator-start-1" || body["guestRuntimeControlEndpointId"] != "guest-control-1" || body["expectedResourceRevision"] != float64(7) || body["action"] != "start" {
		t.Fatalf("command body = %#v", body)
	}
}

func TestParseRejectsLifecycleCommandWithoutCurrentEndpointRevision(t *testing.T) {
	_, err := platformctlcommand.Parse([]string{
		"--control-endpoint", "http://127.0.0.1:18280",
		"guest", "stop",
		"--request-id", "operator-stop-1",
		"--guest-runtime-control-endpoint-id", "guest-control-1",
	})
	if err == nil {
		t.Fatal("Parse() error = nil, want required revision error")
	}
}

func TestParseMapsOnlyPublishedRuntimeReads(t *testing.T) {
	invocation, err := platformctlcommand.Parse([]string{
		"--control-endpoint", "http://127.0.0.1:18280", "runtime", "readiness",
	})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	if invocation.Method != http.MethodGet || invocation.Route != "/v1/runtime/readiness" {
		t.Fatalf("invocation = %#v", invocation)
	}
}

func TestParseMapsOperationalOwnerReadsWithoutGenericPathEscape(t *testing.T) {
	testCases := []struct {
		arguments []string
		route     string
	}{
		{arguments: []string{"host-clock-quality"}, route: "/v1/platform/time/clock-quality"},
		{arguments: []string{"runtime", "guest-clock-quality"}, route: "/v1/time/clock-quality"},
		{arguments: []string{"runtime", "lab-recorders"}, route: "/v1/runtime/lab/recorders"},
		{arguments: []string{"runtime", "recorder-observations"}, route: "/v1/runtime/catalog/recorder-observations"},
		{arguments: []string{"runtime", "external-upstreams"}, route: "/v1/runtime/external-upstreams"},
	}
	for _, testCase := range testCases {
		invocation, err := platformctlcommand.Parse(append([]string{"--control-endpoint", "http://127.0.0.1:18280"}, testCase.arguments...))
		if err != nil {
			t.Fatalf("Parse(%v) error = %v", testCase.arguments, err)
		}
		if invocation.Method != http.MethodGet || invocation.Route != testCase.route {
			t.Fatalf("Parse(%v) = %#v, want GET %s", testCase.arguments, invocation, testCase.route)
		}
	}
	if _, err := platformctlcommand.Parse([]string{"--control-endpoint", "http://127.0.0.1:18280", "runtime", "arbitrary-path"}); err == nil {
		t.Fatal("Parse accepted an unpublished runtime read")
	}
}

func TestParsePreservesTheExplicitC52DescriptorPathWithoutEndpointDiscovery(t *testing.T) {
	invocation, err := platformctlcommand.Parse([]string{
		"--local-control-descriptor", "/Library/Application Support/VitalServerRuntimePlatform/control/host-agent.local.json", "installation",
	})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	if invocation.LocalControlDescriptorPath != "/Library/Application Support/VitalServerRuntimePlatform/control/host-agent.local.json" || invocation.ControlEndpoint != "" || invocation.Route != "/v1/platform/installation" {
		t.Fatalf("invocation = %#v", invocation)
	}
}

func TestParseMapsOnlyNamedHostUpdateBundleOperations(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	imported, err := platformctlcommand.Parse(append(endpoint, "update", "import", "--request-id", "operator-import-020", "--source-directory", "/operator/release"))
	if err != nil {
		t.Fatalf("parse import: %v", err)
	}
	if imported.Method != http.MethodPost || imported.Route != "/v1/platform/update-bundles:import" {
		t.Fatalf("import invocation=%+v", imported)
	}
	var importedBody map[string]any
	if err := json.Unmarshal(imported.Body, &importedBody); err != nil || importedBody["sourceDirectory"] != "/operator/release" || importedBody["requestId"] != "operator-import-020" {
		t.Fatalf("import body=%s err=%v", imported.Body, err)
	}
	read, err := platformctlcommand.Parse(append(endpoint, "update", "read", "--bundle-id", "release-bootstrap-020"))
	if err != nil || read.Method != http.MethodGet || read.Route != "/v1/platform/update-bundles/release-bootstrap-020" {
		t.Fatalf("read invocation=%+v err=%v", read, err)
	}
	applied, err := platformctlcommand.Parse(append(endpoint, "update", "apply", "--request-id", "operator-apply-020", "--installation-id", "platform-installation", "--expected-installation-revision", "4", "--bundle-id", "release-bootstrap-020"))
	if err != nil {
		t.Fatalf("parse apply: %v", err)
	}
	if applied.Method != http.MethodPost || applied.Route != "/v1/platform/update-bundles/release-bootstrap-020:apply" {
		t.Fatalf("apply invocation=%+v", applied)
	}
	if _, err := platformctlcommand.Parse(append(endpoint, "update", "read", "--bundle-id", "release/../../other")); err == nil {
		t.Fatal("path-like bundle identifier unexpectedly accepted")
	}
}

func TestParseMapsOnlyNamedLabOperations(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	created, err := platformctlcommand.Parse(append(endpoint,
		"lab", "create",
		"--request-id", "operator-lab-create-1",
		"--session-id", "lab-session-1",
		"--name", "baseline-monitoring",
		"--scenario", "baseline-monitoring",
		"--recorder-count", "3",
	))
	if err != nil {
		t.Fatalf("parse Lab create: %v", err)
	}
	if created.Method != http.MethodPost || created.Route != "/v1/runtime/lab/sessions" {
		t.Fatalf("Lab create invocation=%+v", created)
	}
	var createBody map[string]any
	if err := json.Unmarshal(created.Body, &createBody); err != nil {
		t.Fatalf("decode Lab create body: %v", err)
	}
	if createBody["expectedSessionRevision"] != float64(0) || createBody["recorderCount"] != float64(3) {
		t.Fatalf("Lab create body=%#v", createBody)
	}

	resource, err := platformctlcommand.Parse(append(endpoint,
		"lab", "resource",
		"--request-id", "operator-lab-stop-1",
		"--resource-type", "lab-session",
		"--resource-id", "lab-session-1",
		"--expected-resource-revision", "4",
		"--action", "stop",
	))
	if err != nil {
		t.Fatalf("parse Lab resource: %v", err)
	}
	if resource.Method != http.MethodPost || resource.Route != "/v1/runtime/lab/resources:command" {
		t.Fatalf("Lab resource invocation=%+v", resource)
	}

	deleted, err := platformctlcommand.Parse(append(endpoint,
		"lab", "resource",
		"--request-id", "operator-lab-delete-1",
		"--resource-type", "lab-session",
		"--resource-id", "lab-session-1",
		"--expected-resource-revision", "5",
		"--action", "delete",
		"--cascade", "owned-resources",
	))
	if err != nil {
		t.Fatalf("parse Lab delete: %v", err)
	}
	var deleteBody map[string]any
	if err := json.Unmarshal(deleted.Body, &deleteBody); err != nil || deleteBody["cascade"] != "owned-resources" {
		t.Fatalf("Lab delete body=%s err=%v", deleted.Body, err)
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"lab", "resource",
		"--request-id", "operator-lab-invalid-1",
		"--resource-type", "lab-bed",
		"--resource-id", "lab-bed-1",
		"--expected-resource-revision", "1",
		"--action", "start",
	)); err == nil {
		t.Fatal("Lab bed start was unexpectedly accepted")
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"lab", "create",
		"--request-id", "operator-lab-invalid-2",
		"--session-id", "lab-session-2",
		"--name", "name",
		"--scenario", "scenario",
		"--recorder-count", "1",
		"--raw-json", "forbidden",
	)); err == nil {
		t.Fatal("unpublished Lab option was unexpectedly accepted")
	}
}

func TestParseMapsManualArtifactExportFromExplicitOwnerReferences(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	providerRead, err := platformctlcommand.Parse(append(endpoint, "runtime", "archive-export-provider"))
	if err != nil || providerRead.Method != http.MethodGet || providerRead.Route != "/v1/runtime/archive/export-provider" {
		t.Fatalf("archive provider read invocation=%+v err=%v", providerRead, err)
	}
	export, err := platformctlcommand.Parse(append(endpoint,
		"archive", "export",
		"--request-id", "operator-archive-export-1",
		"--virtual-recorder-id", "lab-recorder-1",
		"--expected-resource-revision", "4",
		"--cold-path-finalization-receipt-id", "finalization-receipt-1",
		"--provider-kind", "archive-export-outcome-profile",
		"--provider-id", "bundled-archive",
		"--provider-capability-revision", "1",
	))
	if err != nil {
		t.Fatalf("parse archive export: %v", err)
	}
	if export.Method != http.MethodPost || export.Route != "/v1/runtime/archive/exports" {
		t.Fatalf("archive export invocation=%+v", export)
	}
	var body map[string]any
	if err := json.Unmarshal(export.Body, &body); err != nil {
		t.Fatalf("decode archive export body: %v", err)
	}
	if body["virtualRecorderId"] != "lab-recorder-1" || body["expectedResourceRevision"] != float64(4) {
		t.Fatalf("archive export body=%#v", body)
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"archive", "export",
		"--request-id", "operator-archive-export-1",
		"--virtual-recorder-id", "lab-recorder-1",
		"--expected-resource-revision", "4",
		"--provider-kind", "archive-export-outcome-profile",
		"--provider-id", "bundled-archive",
		"--provider-capability-revision", "1",
	)); err == nil {
		t.Fatal("archive export without the explicit Gateway finalization receipt was accepted")
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"archive", "export",
		"--request-id", "operator-archive-export-1",
		"--virtual-recorder-id", "lab-recorder-1",
		"--expected-resource-revision", "4",
		"--cold-path-finalization-receipt-id", "finalization-receipt-1",
		"--provider-kind", "archive-export-outcome-profile",
		"--provider-id", "bundled-archive",
		"--provider-capability-revision", "1",
		"--gateway-url", "http://127.0.0.1:8090",
	)); err == nil {
		t.Fatal("unpublished Gateway URL option was accepted")
	}
}

func TestParseMapsArchiveCredentialMaterialReadAndStdinOnlyProvisioning(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	read, err := platformctlcommand.Parse(append(endpoint, "archive", "credential-material"))
	if err != nil {
		t.Fatalf("parse credential-material read: %v", err)
	}
	if read.Method != http.MethodGet || read.Route != "/v1/runtime/archive/credential-material" || read.ReadsPasswordFromStandardInput {
		t.Fatalf("credential-material read invocation=%+v", read)
	}

	provision, err := platformctlcommand.Parse(append(endpoint,
		"archive", "credential-material", "provision",
		"--credential-kind", "vitalserver-library-credential",
		"--credential-id", "external-vitalserver-primary-library",
		"--user-id", "archive-operator",
		"--password-stdin", "true",
	))
	if err != nil {
		t.Fatalf("parse credential-material provisioning: %v", err)
	}
	if provision.Method != http.MethodPost || provision.Route != "/v1/runtime/archive/credential-material" || !provision.ReadsPasswordFromStandardInput {
		t.Fatalf("credential-material provision invocation=%+v", provision)
	}
	var body map[string]any
	if err := json.Unmarshal(provision.Body, &body); err != nil {
		t.Fatalf("decode credential-material provisioning body: %v", err)
	}
	if body["userId"] != "archive-operator" || body["password"] != nil {
		t.Fatalf("credential-material provisioning body=%#v", body)
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"archive", "credential-material", "provision",
		"--credential-kind", "vitalserver-library-credential",
		"--credential-id", "external-vitalserver-primary-library",
		"--user-id", "archive-operator",
		"--password", "must-not-appear-in-argv",
	)); err == nil {
		t.Fatal("raw password argument was unexpectedly accepted")
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"archive", "credential-material", "provision",
		"--credential-kind", "vitalserver-library-credential",
		"--credential-id", "external-vitalserver-primary-library",
		"--user-id", "archive-operator",
		"--password-stdin", "false",
	)); err == nil {
		t.Fatal("credential provisioning accepted a disabled stdin grant")
	}
}

func TestParseMapsExternalUpstreamThenTopologyWithoutEndpointOrSecretEscape(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	external, err := platformctlcommand.Parse(append(endpoint,
		"external-upstream", "apply",
		"--request-id", "operator-external-1",
		"--integration-id", "external-vitalserver-primary",
		"--expected-resource-revision", "0",
		"--provider-kind", "external-vitalserver",
		"--provider-id", "external-vitalserver-primary",
		"--provider-capability-revision", "1",
		"--endpoint-resource-type", "external-vitalserver-delivery-configuration",
		"--endpoint-resource-id", "external-vitalserver-primary-delivery",
		"--credential-kind", "vitalserver-library-credential",
		"--credential-id", "external-vitalserver-primary-library",
	))
	if err != nil {
		t.Fatalf("parse external upstream apply: %v", err)
	}
	if external.Method != http.MethodPost || external.Route != "/v1/runtime/external-upstreams" {
		t.Fatalf("external upstream invocation=%+v", external)
	}
	var externalBody map[string]any
	if err := json.Unmarshal(external.Body, &externalBody); err != nil {
		t.Fatalf("decode external upstream body: %v", err)
	}
	if externalBody["integrationId"] != "external-vitalserver-primary" {
		t.Fatalf("external upstream body=%#v", externalBody)
	}

	topology, err := platformctlcommand.Parse(append(endpoint,
		"topology", "apply",
		"--request-id", "operator-topology-1",
		"--topology-id", "primary-topology",
		"--expected-resource-revision", "0",
		"--profile-kind", "external-upstream",
		"--endpoint-resource-type", "external-upstream-integration",
		"--endpoint-resource-id", "external-vitalserver-primary",
	))
	if err != nil {
		t.Fatalf("parse topology apply: %v", err)
	}
	if topology.Method != http.MethodPost || topology.Route != "/v1/runtime/topology:apply" {
		t.Fatalf("topology invocation=%+v", topology)
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"topology", "apply",
		"--request-id", "operator-topology-invalid-1",
		"--topology-id", "primary-topology",
		"--expected-resource-revision", "0",
		"--profile-kind", "external-upstream",
		"--endpoint-resource-type", "bundle",
		"--endpoint-resource-id", "bundled-vitalserver",
	)); err == nil {
		t.Fatal("topology external reference without ExternalUpstreamIntegration was accepted")
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"external-upstream", "apply",
		"--request-id", "operator-external-invalid-1",
		"--integration-id", "external-vitalserver-primary",
		"--expected-resource-revision", "0",
		"--provider-kind", "external-vitalserver",
		"--provider-id", "external-vitalserver-primary",
		"--provider-capability-revision", "1",
		"--endpoint-resource-type", "external-vitalserver-delivery-configuration",
		"--endpoint-resource-id", "external-vitalserver-primary-delivery",
		"--endpoint-url", "https://secret.example.test",
	)); err == nil {
		t.Fatal("unpublished external endpoint option was accepted")
	}
}

func TestParseMapsOwnerScopedTimeAuthorityWithoutNTPAddressEscape(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	host, err := platformctlcommand.Parse(append(endpoint,
		"time", "apply",
		"--scope", "host",
		"--request-id", "operator-host-time-1",
		"--authority-id", "host-time-authority",
		"--expected-resource-revision", "0",
		"--node-kind", "host",
		"--node-id", "vitalserver-host",
		"--profile", "enterprise-ntp",
		"--source-profile", "enterprise-ntp",
		"--source-id", "hospital-ntp-primary",
	))
	if err != nil {
		t.Fatalf("parse Host time authority: %v", err)
	}
	if host.Method != http.MethodPost || host.Route != "/v1/platform/time/authorities" {
		t.Fatalf("Host time authority invocation=%+v", host)
	}
	guest, err := platformctlcommand.Parse(append(endpoint,
		"time", "apply",
		"--scope", "guest",
		"--request-id", "operator-guest-time-1",
		"--authority-id", "guest-time-authority",
		"--expected-resource-revision", "2",
		"--node-kind", "guest",
		"--node-id", "vitalserver-guest",
		"--profile", "enterprise-ntp",
		"--source-profile", "enterprise-ntp",
		"--source-id", "hospital-ntp-primary",
	))
	if err != nil || guest.Route != "/v1/time/authorities" {
		t.Fatalf("Guest time authority invocation=%+v err=%v", guest, err)
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"time", "apply",
		"--scope", "host", "--request-id", "operator-host-time-invalid-1", "--authority-id", "host-time-authority",
		"--expected-resource-revision", "0", "--node-kind", "host", "--node-id", "vitalserver-host",
		"--profile", "enterprise-ntp", "--source-profile", "enterprise-ntp", "--source-id", "hospital-ntp-primary",
		"--ntp-server", "ntp.example.test:123",
	)); err == nil {
		t.Fatal("unpublished NTP endpoint option was accepted")
	}
}

func TestParseMapsOwnerScopedTelemetryPipelineWithFixedSignalSet(t *testing.T) {
	endpoint := []string{"--control-endpoint", "http://127.0.0.1:18280"}
	guest, err := platformctlcommand.Parse(append(endpoint,
		"telemetry", "apply",
		"--scope", "guest",
		"--request-id", "operator-guest-telemetry-1",
		"--pipeline-id", "guest-telemetry",
		"--expected-resource-revision", "0",
		"--node-kind", "guest",
		"--node-id", "vitalserver-guest",
		"--collector-resource-type", "otel-collector",
		"--collector-resource-id", "platform-collector",
		"--allowed-attribute-keys", "operation.kind,outcome.code",
		"--max-attributes", "8",
		"--max-value-length", "128",
		"--max-distinct-values-per-key", "32",
	))
	if err != nil {
		t.Fatalf("parse Guest telemetry pipeline: %v", err)
	}
	if guest.Method != http.MethodPost || guest.Route != "/v1/runtime/telemetry/pipelines" {
		t.Fatalf("Guest telemetry invocation=%+v", guest)
	}
	var body map[string]any
	if err := json.Unmarshal(guest.Body, &body); err != nil {
		t.Fatalf("decode telemetry body: %v", err)
	}
	spec, ok := body["spec"].(map[string]any)
	if !ok || spec["protocol"] != "otlp-http" {
		t.Fatalf("telemetry spec=%#v", body["spec"])
	}
	if _, err := platformctlcommand.Parse(append(endpoint,
		"telemetry", "apply",
		"--scope", "host", "--request-id", "operator-host-telemetry-invalid-1", "--pipeline-id", "host-telemetry",
		"--expected-resource-revision", "0", "--node-kind", "host", "--node-id", "vitalserver-host",
		"--collector-resource-type", "otel-collector", "--collector-resource-id", "platform-collector",
		"--allowed-attribute-keys", "authorization", "--max-attributes", "1", "--max-value-length", "1", "--max-distinct-values-per-key", "1",
	)); err == nil {
		t.Fatal("sensitive telemetry attribute was accepted")
	}
}
