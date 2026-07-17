package hostagentcontrolhttpapi

import "testing"

func TestRuntimeFacadeAllowlistIncludesOnlyPublishedOperationalRoutes(t *testing.T) {
	for _, path := range []string{
		"/v1/runtime/lab/sessions",
		"/v1/runtime/lab/sessions/lab-session-1",
		"/v1/runtime/lab/beds",
		"/v1/runtime/lab/beds/lab-bed-1",
		"/v1/runtime/lab/recorders",
		"/v1/runtime/lab/recorders/lab-recorder-1",
		"/v1/runtime/lab/deletion-receipts/deletion-receipt-1",
		"/v1/runtime/archive/manifests/artifact-manifest-1",
		"/v1/runtime/archive/export-receipts/export-receipt-1",
		"/v1/runtime/external-upstreams",
		"/v1/runtime/external-upstreams/external-upstream-1",
		"/v1/runtime/relay-targets",
		"/v1/runtime/relay-targets/relay-target-1",
		"/v1/time/clock-quality",
		"/v1/time/authorities/time-authority-1",
		"/v1/runtime/catalog/recorder-observations",
		"/v1/runtime/catalog/recorder-observations/catalog-observation-1",
		"/v1/runtime/telemetry/pipelines/telemetry-pipeline-1",
		"/v1/runtime/telemetry/receipts/telemetry-receipt-1",
	} {
		if !allowedRuntimeRead(path) {
			t.Fatalf("published Lab and operational read route %q was not allowlisted", path)
		}
	}
	for _, path := range []string{
		"/v1/runtime/lab/sessions/extra/path",
		"/v1/runtime/archive/manifests/extra/path",
		"/v1/runtime/lab/unknown",
		"/v1/runtime/archive/objects/artifact-1",
		"/v1/runtime/telemetry/signals",
		"/v1/time/authorities/one/two",
	} {
		if allowedRuntimeRead(path) {
			t.Fatalf("unpublished runtime read route %q was allowlisted", path)
		}
	}
	for _, path := range []string{
		"/v1/runtime/lab/sessions",
		"/v1/runtime/lab/resources:command",
		"/v1/runtime/archive/exports",
		"/v1/runtime/external-upstreams",
		"/v1/runtime/relay-targets",
		"/v1/time/authorities",
		"/v1/runtime/catalog/recorder-observations",
		"/v1/runtime/telemetry/pipelines",
		"/v1/runtime/telemetry/signals",
	} {
		if !allowedRuntimeCommand(path) {
			t.Fatalf("published Lab and operational command route %q was not allowlisted", path)
		}
	}
	for _, path := range []string{
		"/v1/runtime/lab/recorders:delete",
		"/v1/runtime/archive/manifests/artifact-1",
		"/v1/runtime/archive/objects",
	} {
		if allowedRuntimeCommand(path) {
			t.Fatalf("unpublished runtime command route %q was allowlisted", path)
		}
	}
}
