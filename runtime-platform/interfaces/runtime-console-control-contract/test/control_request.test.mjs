import assert from "node:assert/strict";
import test from "node:test";

import {
  assertRuntimeConsoleControlRequest,
  composeHostAgentControlHTTPRequest,
} from "../dist/index.js";

test("maps only named public reads", () => {
  assert.deepEqual(
    composeHostAgentControlHTTPRequest({ kind: "read", resource: "runtime-readiness" }),
    { method: "GET", path: "/v1/runtime/readiness" },
  );
  assert.deepEqual(
    composeHostAgentControlHTTPRequest({ kind: "read", resource: "host-clock-quality" }),
    { method: "GET", path: "/v1/platform/time/clock-quality" },
  );
  assert.throws(
    () => assertRuntimeConsoleControlRequest({ kind: "read", resource: "raw-control-path" }),
    /not published/,
  );
});

test("maps Lab replay command and operation read without inventing source state", () => {
  const request = assertRuntimeConsoleControlRequest({
    kind: "lab-replay-create",
    requestId: "lab-replay-request-1",
    replayId: "lab-replay-1",
    sourceReference: {
      resourceType: "lab-replay-source",
      resourceId: "lab-replay-source-1",
    },
    sourceSha256: "a".repeat(64),
    recorderGatewayRecorderCode: "LAB-RECORDER-01",
    requestedAt: "2026-07-24T16:00:00Z",
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(request), {
    method: "POST",
    path: "/v1/runtime/lab/replays",
    body: {
      schemaVersion: "v1",
      requestId: "lab-replay-request-1",
      replayId: "lab-replay-1",
      sourceReference: {
        resourceType: "lab-replay-source",
        resourceId: "lab-replay-source-1",
      },
      sourceSha256: "a".repeat(64),
      recorderGatewayRecorderCode: "LAB-RECORDER-01",
      requestedAt: "2026-07-24T16:00:00Z",
    },
  });
  assert.deepEqual(
    composeHostAgentControlHTTPRequest({
      kind: "lab-replay-read",
      replayId: "lab-replay-1",
    }),
    { method: "GET", path: "/v1/runtime/lab/replays/lab-replay-1" },
  );
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      ...request,
      sourceReference: {
        resourceType: "recorder-vital-upload",
        resourceId: "lab-replay-source-1",
      },
    }),
    /lab-replay-source reference/,
  );
});

test("maps only bounded named Recorder detail reads", () => {
  assert.deepEqual(
    composeHostAgentControlHTTPRequest(assertRuntimeConsoleControlRequest({
      kind: "recorder-list-read",
      limit: 25,
      cursor: "cursor-1",
    })),
    { method: "GET", path: "/v1/runtime/recorders?limit=25&cursor=cursor-1" },
  );
  assert.deepEqual(
    composeHostAgentControlHTTPRequest(assertRuntimeConsoleControlRequest({
      kind: "recorder-detail-read",
      resource: "observability-summary",
      recorderId: "recorder-lab-1",
    })),
    { method: "GET", path: "/v1/runtime/recorders/recorder-lab-1/observability" },
  );
  assert.deepEqual(
    composeHostAgentControlHTTPRequest(assertRuntimeConsoleControlRequest({
      kind: "recorder-detail-read",
      resource: "observation-timeline",
      recorderId: "recorder-lab-1",
      limit: 25,
      cursor: "cursor-1",
    })),
    { method: "GET", path: "/v1/runtime/recorders/recorder-lab-1/observability/timeline?limit=25&cursor=cursor-1" },
  );
  assert.deepEqual(
    composeHostAgentControlHTTPRequest(assertRuntimeConsoleControlRequest({
      kind: "recorder-detail-read",
      resource: "incidents",
      recorderId: "recorder-lab-1",
      limit: 25,
    })),
    { method: "GET", path: "/v1/runtime/recorders/recorder-lab-1/observability/incidents?limit=25" },
  );
  assert.deepEqual(
    composeHostAgentControlHTTPRequest(assertRuntimeConsoleControlRequest({
      kind: "recorder-detail-read",
      resource: "artifacts",
      recorderId: "recorder-lab-1",
      limit: 25,
    })),
    { method: "GET", path: "/v1/runtime/recorders/recorder-lab-1/artifacts?limit=25" },
  );
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "recorder-list-read",
      limit: 0,
    }),
    /limit/,
  );
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "recorder-detail-read",
      resource: "raw-postgresql",
      recorderId: "recorder-lab-1",
    }),
    /Recorder detail resource is not published/,
  );
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "recorder-detail-read",
      resource: "artifacts",
      recorderId: "recorder-lab-1",
      limit: 101,
    }),
    /limit/,
  );
});

test("preserves operator lifecycle correlation instead of generating it", () => {
  const request = assertRuntimeConsoleControlRequest({
    kind: "guest-lifecycle",
    action: "start",
    requestId: "operator-start-1",
    guestRuntimeControlEndpointId: "guest-control-1",
    expectedResourceRevision: 7,
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(request), {
    method: "POST",
    path: "/v1/platform/guest:start",
    body: {
      schemaVersion: "v1",
      requestId: "operator-start-1",
      guestRuntimeControlEndpointId: "guest-control-1",
      expectedResourceRevision: 7,
      action: "start",
    },
  });
});

test("maps private archive credential material only through its named local-control command", () => {
  const request = assertRuntimeConsoleControlRequest({
    kind: "archive-credential-material-provision",
    credentialReference: { kind: "vitalserver-library-credential", id: "external-library" },
    userId: "operator",
    password: "not-logged-or-persisted",
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(request), {
    method: "POST",
    path: "/v1/runtime/archive/credential-material",
    body: {
      schemaVersion: "v1",
      credentialReference: { kind: "vitalserver-library-credential", id: "external-library" },
      userId: "operator",
      password: "not-logged-or-persisted",
    },
  });
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "archive-credential-material-provision",
      credentialReference: { kind: "vitalserver-library-credential", id: "external-library", extra: true },
      userId: "operator",
      password: "not-logged-or-persisted",
    }),
    /credentialReference/,
  );
});

test("maps a manual artifact export only from explicit Gateway and Archive owner references", () => {
  const request = assertRuntimeConsoleControlRequest({
    kind: "artifact-export",
    requestId: "operator-archive-export-1",
    virtualRecorderId: "lab-recorder-1",
    expectedResourceRevision: 4,
    coldPathFinalizationReceiptId: "finalization-receipt-1",
    provider: { kind: "archive-export-outcome-profile", id: "bundled-archive", capabilityRevision: 1 },
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(request), {
    method: "POST",
    path: "/v1/runtime/archive/exports",
    body: {
      schemaVersion: "v1",
      requestId: "operator-archive-export-1",
      virtualRecorderId: "lab-recorder-1",
      expectedResourceRevision: 4,
      source: { kind: "recorder-gateway-cold-path", coldPathFinalizationReceiptId: "finalization-receipt-1" },
      provider: { kind: "archive-export-outcome-profile", id: "bundled-archive", capabilityRevision: 1 },
    },
  });
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "artifact-export",
      requestId: "operator-archive-export-1",
      virtualRecorderId: "lab-recorder-1",
      expectedResourceRevision: 4,
      provider: { kind: "archive-export-outcome-profile", id: "bundled-archive", capabilityRevision: 1 },
    }),
    /coldPathFinalizationReceiptId/,
  );
});

test("maps an operator-selected Host bundle directory without allowing the renderer to author C25", () => {
  const imported = assertRuntimeConsoleControlRequest({
    kind: "update-bundle-import",
    requestId: "operator-import-020",
    sourceDirectory: "/Users/operator/Downloads/vitalserver-release-020",
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(imported), {
    method: "POST",
    path: "/v1/platform/update-bundles:import",
    body: {
      schemaVersion: "v1",
      requestId: "operator-import-020",
      sourceDirectory: "/Users/operator/Downloads/vitalserver-release-020",
    },
  });
  const applied = assertRuntimeConsoleControlRequest({
    kind: "update-bundle-apply",
    requestId: "operator-apply-020",
    installationId: "platform-installation-1",
    expectedInstallationRevision: 4,
    bundleReferenceId: "release-bootstrap-020",
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(applied), {
    method: "POST",
    path: "/v1/platform/update-bundles/release-bootstrap-020:apply",
    body: {
      schemaVersion: "v1",
      requestId: "operator-apply-020",
      installationId: "platform-installation-1",
      expectedInstallationRevision: 4,
      bundleReferenceId: "release-bootstrap-020",
    },
  });
  assert.throws(
    () => assertRuntimeConsoleControlRequest({ kind: "update-bundle-apply", requestId: "bad", installationId: "platform-installation-1", expectedInstallationRevision: 0, bundleReferenceId: "release-bootstrap-020" }),
    /expectedInstallationRevision/,
  );
});

test("maps named Lab creation and resource lifecycle commands without a generic Guest command escape", () => {
  const created = assertRuntimeConsoleControlRequest({
    kind: "lab-session-create",
    requestId: "operator-lab-create-1",
    sessionId: "lab-session-operator-1",
    name: "baseline-monitoring",
    scenario: "baseline-monitoring",
    recorderCount: 3,
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(created), {
    method: "POST",
    path: "/v1/runtime/lab/sessions",
    body: {
      schemaVersion: "v1",
      requestId: "operator-lab-create-1",
      sessionId: "lab-session-operator-1",
      expectedSessionRevision: 0,
      name: "baseline-monitoring",
      scenario: "baseline-monitoring",
      recorderCount: 3,
    },
  });
  const stopped = assertRuntimeConsoleControlRequest({
    kind: "lab-resource-command",
    requestId: "operator-lab-stop-1",
    resourceType: "lab-session",
    resourceId: "lab-session-operator-1",
    expectedResourceRevision: 4,
    action: "stop",
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(stopped), {
    method: "POST",
    path: "/v1/runtime/lab/resources:command",
    body: {
      schemaVersion: "v1",
      requestId: "operator-lab-stop-1",
      resourceType: "lab-session",
      resourceId: "lab-session-operator-1",
      expectedResourceRevision: 4,
      action: "stop",
    },
  });
  const deleted = assertRuntimeConsoleControlRequest({
    kind: "lab-resource-command",
    requestId: "operator-lab-delete-1",
    resourceType: "lab-session",
    resourceId: "lab-session-operator-1",
    expectedResourceRevision: 5,
    action: "delete",
    cascade: "owned-resources",
  });
  assert.equal(composeHostAgentControlHTTPRequest(deleted).body.cascade, "owned-resources");
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "lab-resource-command",
      requestId: "operator-lab-invalid-1",
      resourceType: "lab-bed",
      resourceId: "lab-bed-1",
      expectedResourceRevision: 1,
      action: "start",
    }),
    /Lab session or virtual recorder/,
  );
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "lab-resource-command",
      requestId: "operator-lab-invalid-2",
      resourceType: "lab-session",
      resourceId: "lab-session-operator-1",
      expectedResourceRevision: 5,
      action: "delete",
      cascade: "none",
    }),
    /owned-resources/,
  );
});

test("maps named external-upstream and topology configuration without exposing endpoint secrets", () => {
  const external = assertRuntimeConsoleControlRequest({
    kind: "external-upstream-apply",
    requestId: "operator-external-upstream-1",
    integrationId: "external-vitalserver-primary",
    expectedResourceRevision: 0,
    provider: { kind: "external-vitalserver", id: "external-vitalserver-primary", capabilityRevision: 1 },
    endpointReference: { resourceType: "external-vitalserver-delivery-configuration", resourceId: "external-vitalserver-primary-delivery" },
    credentialReference: { kind: "vitalserver-library-credential", id: "external-vitalserver-primary-library" },
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(external), {
    method: "POST",
    path: "/v1/runtime/external-upstreams",
    body: {
      schemaVersion: "v1",
      requestId: "operator-external-upstream-1",
      integrationId: "external-vitalserver-primary",
      expectedResourceRevision: 0,
      spec: {
        provider: { kind: "external-vitalserver", id: "external-vitalserver-primary", capabilityRevision: 1 },
        endpointReference: { resourceType: "external-vitalserver-delivery-configuration", resourceId: "external-vitalserver-primary-delivery" },
        credentialReference: { kind: "vitalserver-library-credential", id: "external-vitalserver-primary-library" },
      },
    },
  });
  const topology = assertRuntimeConsoleControlRequest({
    kind: "runtime-topology-apply",
    requestId: "operator-topology-1",
    topologyId: "primary-topology",
    expectedResourceRevision: 0,
    profileKind: "external-upstream",
    endpointReference: { resourceType: "external-upstream-integration", resourceId: "external-vitalserver-primary" },
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(topology), {
    method: "POST",
    path: "/v1/runtime/topology:apply",
    body: {
      schemaVersion: "v1",
      requestId: "operator-topology-1",
      topologyId: "primary-topology",
      expectedResourceRevision: 0,
      spec: {
        profileKind: "external-upstream",
        providerKind: "vitalserver",
        endpointReference: { resourceType: "external-upstream-integration", resourceId: "external-vitalserver-primary" },
      },
    },
  });
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "runtime-topology-apply",
      requestId: "operator-topology-invalid-1",
      topologyId: "primary-topology",
      expectedResourceRevision: 0,
      profileKind: "external-upstream",
      endpointReference: { resourceType: "bundle", resourceId: "bundled-vitalserver" },
    }),
    /external-upstream-integration/,
  );
});

test("maps explicit Host and Guest NTP authorities without accepting an endpoint address", () => {
  const hostAuthority = assertRuntimeConsoleControlRequest({
    kind: "time-authority-apply",
    scope: "host",
    requestId: "operator-host-time-1",
    authorityId: "host-time-authority",
    expectedResourceRevision: 0,
    node: { kind: "host", id: "vitalserver-host" },
    profile: "enterprise-ntp",
    source: { profile: "enterprise-ntp", sourceId: "hospital-ntp-primary" },
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(hostAuthority), {
    method: "POST",
    path: "/v1/platform/time/authorities",
    body: {
      schemaVersion: "v1",
      requestId: "operator-host-time-1",
      authorityId: "host-time-authority",
      expectedResourceRevision: 0,
      node: { kind: "host", id: "vitalserver-host" },
      spec: { profile: "enterprise-ntp", source: { profile: "enterprise-ntp", sourceId: "hospital-ntp-primary" } },
    },
  });
  const guestAuthority = assertRuntimeConsoleControlRequest({
    kind: "time-authority-apply",
    scope: "guest",
    requestId: "operator-guest-time-1",
    authorityId: "guest-time-authority",
    expectedResourceRevision: 3,
    node: { kind: "guest", id: "vitalserver-guest" },
    profile: "enterprise-ntp",
    source: { profile: "enterprise-ntp", sourceId: "hospital-ntp-primary" },
  });
  assert.equal(composeHostAgentControlHTTPRequest(guestAuthority).path, "/v1/time/authorities");
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "time-authority-apply",
      scope: "host",
      requestId: "operator-host-time-invalid-1",
      authorityId: "host-time-authority",
      expectedResourceRevision: 0,
      node: { kind: "host", id: "vitalserver-host" },
      profile: "enterprise-ntp",
      source: { profile: "enterprise-ntp", sourceId: "hospital-ntp-primary", endpoint: "ntp://should-not-be-here" },
    }),
    /source/,
  );
});

test("maps owner-scoped OTLP logs, metrics, and traces with a bounded redaction policy", () => {
  const request = assertRuntimeConsoleControlRequest({
    kind: "telemetry-pipeline-apply",
    scope: "guest",
    requestId: "operator-guest-telemetry-1",
    pipelineId: "guest-telemetry",
    expectedResourceRevision: 0,
    node: { kind: "guest", id: "vitalserver-guest" },
    collectorReference: { resourceType: "otel-collector", resourceId: "platform-collector" },
    redaction: {
      allowedAttributeKeys: ["operation.kind", "outcome.code"],
      maxAttributes: 8,
      maxValueLength: 128,
      maxDistinctValuesPerKey: 32,
    },
  });
  assert.deepEqual(composeHostAgentControlHTTPRequest(request), {
    method: "POST",
    path: "/v1/runtime/telemetry/pipelines",
    body: {
      schemaVersion: "v1",
      requestId: "operator-guest-telemetry-1",
      pipelineId: "guest-telemetry",
      expectedResourceRevision: 0,
      node: { kind: "guest", id: "vitalserver-guest" },
      spec: {
        protocol: "otlp-http",
        collectorReference: { resourceType: "otel-collector", resourceId: "platform-collector" },
        signalKinds: ["logs", "metrics", "traces"],
        redaction: {
          allowedAttributeKeys: ["operation.kind", "outcome.code"],
          maxAttributes: 8,
          maxValueLength: 128,
          maxDistinctValuesPerKey: 32,
        },
      },
    },
  });
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "telemetry-pipeline-apply",
      scope: "host",
      requestId: "operator-host-telemetry-invalid-1",
      pipelineId: "host-telemetry",
      expectedResourceRevision: 0,
      node: { kind: "host", id: "vitalserver-host" },
      collectorReference: { resourceType: "otel-collector", resourceId: "platform-collector" },
      redaction: { allowedAttributeKeys: ["authorization"], maxAttributes: 1, maxValueLength: 1, maxDistinctValuesPerKey: 1 },
    }),
    /non-sensitive/,
  );
});

test("rejects a lifecycle request without an explicit revision", () => {
  assert.throws(
    () => assertRuntimeConsoleControlRequest({
      kind: "guest-lifecycle",
      action: "stop",
      requestId: "operator-stop-1",
      guestRuntimeControlEndpointId: "guest-control-1",
    }),
    /expectedResourceRevision/,
  );
});
