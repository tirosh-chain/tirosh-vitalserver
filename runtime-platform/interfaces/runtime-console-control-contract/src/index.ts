/**
 * Named public Control API requests shared by the desktop and web renderers.
 * This module contains transport vocabulary and input-shape validation only;
 * it owns no Host, Guest, Recorder, or operation state.
 */

export const runtimeConsoleReadNames = [
  "installation",
  "guest-runtime-control-endpoint",
  "runtime-readiness",
  "runtime-topology",
  "runtime-capabilities",
  "host-clock-quality",
  "guest-clock-quality",
  "lab-sessions",
  "lab-beds",
  "lab-recorders",
  "archive-export-provider",
  "archive-credential-material",
  "external-upstreams",
  "outbound-relays",
] as const;

export type RuntimeConsoleReadName = (typeof runtimeConsoleReadNames)[number];

export type RuntimeConsoleGuestLifecycleAction = "start" | "stop" | "reboot";
export type RuntimeConsoleLabResourceType = "lab-session" | "lab-bed" | "virtual-recorder";
export type RuntimeConsoleLabResourceAction = "start" | "stop" | "hide" | "unhide" | "detach" | "delete";
export type RuntimeConsoleTopologyProfileKind = "bundled-upstream" | "external-upstream";
export type RuntimeConsoleOperationalScope = "host" | "guest";

export interface RuntimeConsoleResourceReference {
  readonly resourceType: string;
  readonly resourceId: string;
}

export interface RuntimeConsoleSecretReference {
  readonly kind: string;
  readonly id: string;
}

export interface RuntimeConsoleIntegrationProviderReference {
  readonly kind: string;
  readonly id: string;
  readonly capabilityRevision: number;
}

export interface RuntimeConsoleNodeReference {
  readonly kind: string;
  readonly id: string;
}

export interface RuntimeConsoleTelemetryRedactionPolicy {
  readonly allowedAttributeKeys: readonly string[];
  readonly maxAttributes: number;
  readonly maxValueLength: number;
  readonly maxDistinctValuesPerKey: number;
}

export interface RuntimeConsoleGuestLifecycleRequest {
  readonly kind: "guest-lifecycle";
  readonly action: RuntimeConsoleGuestLifecycleAction;
  readonly requestId: string;
  readonly guestRuntimeControlEndpointId: string;
  readonly expectedResourceRevision: number;
}

export interface RuntimeConsoleReadRequest {
  readonly kind: "read";
  readonly resource: RuntimeConsoleReadName;
}

export interface RuntimeConsoleArchiveCredentialMaterialProvisionRequest {
  readonly kind: "archive-credential-material-provision";
  readonly credentialReference: {
    readonly kind: string;
    readonly id: string;
  };
  readonly userId: string;
  readonly password: string;
}

/**
 * Requests one explicit Archive Export operation.  The Guest-owned Lab read
 * supplies the stopped recorder's finalized cold-path receipt, and the
 * Archive Export read supplies the provider reference.  The Console never
 * turns a recorder name, stopped state, or topology configuration into either
 * of those inputs.
 */
export interface RuntimeConsoleArtifactExportRequest {
  readonly kind: "artifact-export";
  readonly requestId: string;
  readonly virtualRecorderId: string;
  readonly expectedResourceRevision: number;
  readonly coldPathFinalizationReceiptId: string;
  readonly provider: RuntimeConsoleIntegrationProviderReference;
}

export interface RuntimeConsoleUpdateBundleImportRequest {
  readonly kind: "update-bundle-import";
  readonly requestId: string;
  readonly sourceDirectory: string;
}

export interface RuntimeConsoleUpdateBundleApplyRequest {
  readonly kind: "update-bundle-apply";
  readonly requestId: string;
  readonly installationId: string;
  readonly expectedInstallationRevision: number;
  readonly bundleReferenceId: string;
}

export interface RuntimeConsoleLabSessionCreateRequest {
  readonly kind: "lab-session-create";
  readonly requestId: string;
  readonly sessionId: string;
  readonly name: string;
  readonly scenario: string;
  readonly recorderCount: number;
}

export interface RuntimeConsoleLabReplayReadRequest {
  readonly kind: "lab-replay-read";
  readonly replayId: string;
}

export interface RuntimeConsoleLabReplayCreateRequest {
  readonly kind: "lab-replay-create";
  readonly requestId: string;
  readonly replayId: string;
  readonly sourceReference: {
    readonly resourceType: "lab-replay-source";
    readonly resourceId: string;
  };
  readonly sourceSha256: string;
  readonly recorderGatewayRecorderCode: string;
  readonly requestedAt: string;
}

export interface RuntimeConsoleRecorderListReadRequest {
  readonly kind: "recorder-list-read";
  readonly limit: number;
  readonly cursor?: string;
}

export type RuntimeConsoleRecorderDetailResource =
  | "observability-summary"
  | "observation-timeline"
  | "incidents"
  | "artifacts";

export interface RuntimeConsoleRecorderDetailReadRequest {
  readonly kind: "recorder-detail-read";
  readonly resource: RuntimeConsoleRecorderDetailResource;
  readonly recorderId: string;
  readonly limit?: number;
  readonly cursor?: string;
}

export interface RuntimeConsoleLabResourceCommandRequest {
  readonly kind: "lab-resource-command";
  readonly requestId: string;
  readonly resourceType: RuntimeConsoleLabResourceType;
  readonly resourceId: string;
  readonly expectedResourceRevision: number;
  readonly action: RuntimeConsoleLabResourceAction;
  readonly cascade?: "none" | "owned-resources";
}

export interface RuntimeConsoleExternalUpstreamApplyRequest {
  readonly kind: "external-upstream-apply";
  readonly requestId: string;
  readonly integrationId: string;
  readonly expectedResourceRevision: number;
  readonly provider: RuntimeConsoleIntegrationProviderReference;
  readonly endpointReference: RuntimeConsoleResourceReference;
  readonly credentialReference?: RuntimeConsoleSecretReference;
}

export interface RuntimeConsoleTopologyApplyRequest {
  readonly kind: "runtime-topology-apply";
  readonly requestId: string;
  readonly topologyId: string;
  readonly expectedResourceRevision: number;
  readonly profileKind: RuntimeConsoleTopologyProfileKind;
  readonly endpointReference: RuntimeConsoleResourceReference;
  readonly credentialReference?: RuntimeConsoleSecretReference;
}

/**
 * Applies one owner-scoped NTP authority. The deployment/secret owner, not
 * this operator surface, owns a concrete NTP endpoint and its credentials.
 */
export interface RuntimeConsoleTimeAuthorityApplyRequest {
  readonly kind: "time-authority-apply";
  readonly scope: RuntimeConsoleOperationalScope;
  readonly requestId: string;
  readonly authorityId: string;
  readonly expectedResourceRevision: number;
  readonly node: RuntimeConsoleNodeReference;
  readonly profile: string;
  readonly source: {
    readonly profile: string;
    readonly sourceId: string;
  };
}

/**
 * Applies one owner-scoped OpenTelemetry pipeline. The signal set is fixed to
 * logs, metrics, and traces; the caller supplies only a collector reference
 * and a bounded redaction policy.
 */
export interface RuntimeConsoleTelemetryPipelineApplyRequest {
  readonly kind: "telemetry-pipeline-apply";
  readonly scope: RuntimeConsoleOperationalScope;
  readonly requestId: string;
  readonly pipelineId: string;
  readonly expectedResourceRevision: number;
  readonly node: RuntimeConsoleNodeReference;
  readonly collectorReference: RuntimeConsoleResourceReference;
  readonly redaction: RuntimeConsoleTelemetryRedactionPolicy;
}

export type RuntimeConsoleControlRequest = RuntimeConsoleReadRequest | RuntimeConsoleGuestLifecycleRequest | RuntimeConsoleArchiveCredentialMaterialProvisionRequest | RuntimeConsoleArtifactExportRequest | RuntimeConsoleUpdateBundleImportRequest | RuntimeConsoleUpdateBundleApplyRequest | RuntimeConsoleLabSessionCreateRequest | RuntimeConsoleLabReplayReadRequest | RuntimeConsoleLabReplayCreateRequest | RuntimeConsoleRecorderListReadRequest | RuntimeConsoleRecorderDetailReadRequest | RuntimeConsoleLabResourceCommandRequest | RuntimeConsoleExternalUpstreamApplyRequest | RuntimeConsoleTopologyApplyRequest | RuntimeConsoleTimeAuthorityApplyRequest | RuntimeConsoleTelemetryPipelineApplyRequest;

export interface RuntimeConsoleControlResponse {
  readonly httpStatus: number;
  readonly document: unknown;
}

export interface RuntimeConsoleControlRequestOptions {
  readonly signal?: AbortSignal;
}

export interface RuntimeConsoleControlTransport {
  request(
    request: RuntimeConsoleControlRequest,
    options?: RuntimeConsoleControlRequestOptions,
  ): Promise<RuntimeConsoleControlResponse>;
}

export interface HostAgentControlHTTPRequest {
  readonly method: "GET" | "POST";
  readonly path: string;
  readonly body?: Readonly<Record<string, unknown>>;
}

const publicReadPaths: Readonly<Record<RuntimeConsoleReadName, string>> = {
  "installation": "/v1/platform/installation",
  "guest-runtime-control-endpoint": "/v1/platform/guest-runtime-control-endpoint",
  "runtime-readiness": "/v1/runtime/readiness",
  "runtime-topology": "/v1/runtime/topology",
  "runtime-capabilities": "/v1/runtime/capabilities",
  "host-clock-quality": "/v1/platform/time/clock-quality",
  "guest-clock-quality": "/v1/time/clock-quality",
  "lab-sessions": "/v1/runtime/lab/sessions",
  "lab-beds": "/v1/runtime/lab/beds",
  "lab-recorders": "/v1/runtime/lab/recorders",
  "archive-export-provider": "/v1/runtime/archive/export-provider",
  "archive-credential-material": "/v1/runtime/archive/credential-material",
  "external-upstreams": "/v1/runtime/external-upstreams",
  "outbound-relays": "/v1/runtime/relay-targets",
};

/**
 * composeHostAgentControlHTTPRequest maps only an intentional set of public
 * control resources. It does not offer a generic path or body escape hatch.
 */
export function composeHostAgentControlHTTPRequest(request: RuntimeConsoleControlRequest): HostAgentControlHTTPRequest {
  if (request.kind === "read") {
    if (!isRuntimeConsoleReadName(request.resource)) {
      throw new Error("runtime console read resource is not published");
    }
    return { method: "GET", path: publicReadPaths[request.resource] };
  }

  if (request.kind === "lab-replay-read") {
    return {
      method: "GET",
      path: `/v1/runtime/lab/replays/${identifier(request.replayId, "replayId")}`,
    };
  }

  if (request.kind === "lab-replay-create") {
    assertLabReplayCreateRequestShape(request);
    return {
      method: "POST",
      path: "/v1/runtime/lab/replays",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        replayId: request.replayId,
        sourceReference: request.sourceReference,
        sourceSha256: request.sourceSha256,
        recorderGatewayRecorderCode: request.recorderGatewayRecorderCode,
        requestedAt: request.requestedAt,
      },
    };
  }

  if (request.kind === "recorder-list-read") {
    const normalized = recorderListReadRequest(request);
    return {
      method: "GET",
      path: `/v1/runtime/recorders?limit=${normalized.limit}${normalized.cursor === undefined ? "" : `&cursor=${encodeURIComponent(normalized.cursor)}`}`,
    };
  }

  if (request.kind === "recorder-detail-read") {
    const normalized = recorderDetailReadRequest(request);
    const suffix: Readonly<Record<RuntimeConsoleRecorderDetailResource, string>> = {
      "observability-summary": "/observability",
      "observation-timeline": "/observability/timeline",
      "incidents": "/observability/incidents",
      "artifacts": "/artifacts",
    };
    const query = normalized.limit === undefined
      ? ""
      : `?limit=${normalized.limit}${normalized.cursor === undefined ? "" : `&cursor=${encodeURIComponent(normalized.cursor)}`}`;
    return {
      method: "GET",
      path: `/v1/runtime/recorders/${normalized.recorderId}${suffix[normalized.resource]}${query}`,
    };
  }

	if (request.kind === "archive-credential-material-provision") {
		assertArchiveCredentialMaterialProvisionRequestShape(request);
		return {
			method: "POST",
			path: "/v1/runtime/archive/credential-material",
			body: {
				schemaVersion: "v1",
				credentialReference: request.credentialReference,
				userId: request.userId,
				password: request.password,
			},
		};
	}

  if (request.kind === "artifact-export") {
    assertArtifactExportRequestShape(request);
    return {
      method: "POST",
      path: "/v1/runtime/archive/exports",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        virtualRecorderId: request.virtualRecorderId,
        expectedResourceRevision: request.expectedResourceRevision,
        source: {
          kind: "recorder-gateway-cold-path",
          coldPathFinalizationReceiptId: request.coldPathFinalizationReceiptId,
        },
        provider: request.provider,
      },
    };
  }

  if (request.kind === "update-bundle-import") {
    assertUpdateBundleImportRequestShape(request);
    return {
      method: "POST",
      path: "/v1/platform/update-bundles:import",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        sourceDirectory: request.sourceDirectory,
      },
    };
  }

  if (request.kind === "update-bundle-apply") {
    assertUpdateBundleApplyRequestShape(request);
    return {
      method: "POST",
      path: `/v1/platform/update-bundles/${request.bundleReferenceId}:apply`,
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        installationId: request.installationId,
        expectedInstallationRevision: request.expectedInstallationRevision,
        bundleReferenceId: request.bundleReferenceId,
      },
    };
  }

  if (request.kind === "lab-session-create") {
    assertLabSessionCreateRequestShape(request);
    return {
      method: "POST",
      path: "/v1/runtime/lab/sessions",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        sessionId: request.sessionId,
        expectedSessionRevision: 0,
        name: request.name,
        scenario: request.scenario,
        recorderCount: request.recorderCount,
      },
    };
  }

  if (request.kind === "lab-resource-command") {
    assertLabResourceCommandRequestShape(request);
    return {
      method: "POST",
      path: "/v1/runtime/lab/resources:command",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        resourceType: request.resourceType,
        resourceId: request.resourceId,
        expectedResourceRevision: request.expectedResourceRevision,
        action: request.action,
        ...(request.cascade === undefined ? {} : { cascade: request.cascade }),
      },
    };
  }

  if (request.kind === "external-upstream-apply") {
    assertExternalUpstreamApplyRequestShape(request);
    return {
      method: "POST",
      path: "/v1/runtime/external-upstreams",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        integrationId: request.integrationId,
        expectedResourceRevision: request.expectedResourceRevision,
        spec: {
          provider: request.provider,
          endpointReference: request.endpointReference,
          ...(request.credentialReference === undefined ? {} : { credentialReference: request.credentialReference }),
        },
      },
    };
  }

  if (request.kind === "runtime-topology-apply") {
    assertTopologyApplyRequestShape(request);
    return {
      method: "POST",
      path: "/v1/runtime/topology:apply",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        topologyId: request.topologyId,
        expectedResourceRevision: request.expectedResourceRevision,
        spec: {
          profileKind: request.profileKind,
          providerKind: "vitalserver",
          endpointReference: request.endpointReference,
          ...(request.credentialReference === undefined ? {} : { credentialReference: request.credentialReference }),
        },
      },
    };
  }

  if (request.kind === "time-authority-apply") {
    assertTimeAuthorityApplyRequestShape(request);
    return {
      method: "POST",
      path: request.scope === "host" ? "/v1/platform/time/authorities" : "/v1/time/authorities",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        authorityId: request.authorityId,
        expectedResourceRevision: request.expectedResourceRevision,
        node: request.node,
        spec: { profile: request.profile, source: request.source },
      },
    };
  }

  if (request.kind === "telemetry-pipeline-apply") {
    assertTelemetryPipelineApplyRequestShape(request);
    return {
      method: "POST",
      path: request.scope === "host" ? "/v1/platform/telemetry/pipelines" : "/v1/runtime/telemetry/pipelines",
      body: {
        schemaVersion: "v1",
        requestId: request.requestId,
        pipelineId: request.pipelineId,
        expectedResourceRevision: request.expectedResourceRevision,
        node: request.node,
        spec: {
          protocol: "otlp-http",
          collectorReference: request.collectorReference,
          signalKinds: ["logs", "metrics", "traces"],
          redaction: request.redaction,
        },
      },
    };
  }

  assertGuestLifecycleRequestShape(request);
  return {
    method: "POST",
    path: `/v1/platform/guest:${request.action}`,
    body: {
      schemaVersion: "v1",
      requestId: request.requestId,
      guestRuntimeControlEndpointId: request.guestRuntimeControlEndpointId,
      expectedResourceRevision: request.expectedResourceRevision,
      action: request.action,
    },
  };
}

/**
 * assertRuntimeConsoleControlRequest protects the shell IPC boundary from an
 * arbitrary renderer message. It validates only transport shape; Host Agent
 * remains the authoritative lifecycle-command admission owner.
 */
export function assertRuntimeConsoleControlRequest(value: unknown): RuntimeConsoleControlRequest {
  if (!isRecord(value) || typeof value.kind !== "string") {
    throw new Error("runtime console control request must contain a kind");
  }
  if (value.kind === "read") {
    if (!isRuntimeConsoleReadName(value.resource)) {
      throw new Error("runtime console read resource is not published");
    }
    return { kind: "read", resource: value.resource };
  }
  if (value.kind === "guest-lifecycle") {
    const request: RuntimeConsoleGuestLifecycleRequest = {
      kind: "guest-lifecycle",
      action: lifecycleAction(value.action),
      requestId: nonEmptyString(value.requestId, "requestId"),
      guestRuntimeControlEndpointId: nonEmptyString(value.guestRuntimeControlEndpointId, "guestRuntimeControlEndpointId"),
      expectedResourceRevision: nonNegativeInteger(value.expectedResourceRevision, "expectedResourceRevision"),
    };
    return request;
  }
	if (value.kind === "archive-credential-material-provision") {
		if (!isRecord(value.credentialReference) || !hasOnlyKeys(value.credentialReference, ["kind", "id"])) {
			throw new Error("credentialReference must be an exact object");
		}
		return {
			kind: "archive-credential-material-provision",
			credentialReference: {
				kind: nonEmptyString(value.credentialReference.kind, "credentialReference.kind"),
				id: nonEmptyString(value.credentialReference.id, "credentialReference.id"),
			},
			userId: boundedSecretInput(value.userId, "userId", 1024),
			password: boundedSecretInput(value.password, "password", 4096),
		};
	}
  if (value.kind === "artifact-export") {
    const request: RuntimeConsoleArtifactExportRequest = {
      kind: "artifact-export",
      requestId: identifier(value.requestId, "requestId"),
      virtualRecorderId: identifier(value.virtualRecorderId, "virtualRecorderId"),
      expectedResourceRevision: positiveInteger(value.expectedResourceRevision, "expectedResourceRevision"),
      coldPathFinalizationReceiptId: identifier(value.coldPathFinalizationReceiptId, "coldPathFinalizationReceiptId"),
      provider: integrationProviderReference(value.provider),
    };
    assertArtifactExportRequestShape(request);
    return request;
  }
  if (value.kind === "update-bundle-import") {
    return {
      kind: "update-bundle-import",
      requestId: nonEmptyString(value.requestId, "requestId"),
      sourceDirectory: boundedHostPath(value.sourceDirectory, "sourceDirectory"),
    };
  }
  if (value.kind === "update-bundle-apply") {
    return {
      kind: "update-bundle-apply",
      requestId: nonEmptyString(value.requestId, "requestId"),
      installationId: nonEmptyString(value.installationId, "installationId"),
      expectedInstallationRevision: positiveInteger(value.expectedInstallationRevision, "expectedInstallationRevision"),
      bundleReferenceId: nonEmptyString(value.bundleReferenceId, "bundleReferenceId"),
    };
  }
  if (value.kind === "lab-session-create") {
    return {
      kind: "lab-session-create",
      requestId: identifier(value.requestId, "requestId"),
      sessionId: identifier(value.sessionId, "sessionId"),
      name: boundedLabText(value.name, "name"),
      scenario: boundedLabText(value.scenario, "scenario"),
      recorderCount: boundedPositiveInteger(value.recorderCount, "recorderCount", 64),
    };
  }
  if (value.kind === "lab-replay-read") {
    return {
      kind: "lab-replay-read",
      replayId: identifier(value.replayId, "replayId"),
    };
  }
  if (value.kind === "lab-replay-create") {
    if (!isRecord(value.sourceReference) ||
        !hasOnlyKeys(value.sourceReference, ["resourceType", "resourceId"]) ||
        value.sourceReference.resourceType !== "lab-replay-source") {
      throw new Error("sourceReference must be an exact lab-replay-source reference");
    }
    const request: RuntimeConsoleLabReplayCreateRequest = {
      kind: "lab-replay-create",
      requestId: identifier(value.requestId, "requestId"),
      replayId: identifier(value.replayId, "replayId"),
      sourceReference: {
        resourceType: "lab-replay-source",
        resourceId: identifier(value.sourceReference.resourceId, "sourceReference.resourceId"),
      },
      sourceSha256: sha256(value.sourceSha256, "sourceSha256"),
      recorderGatewayRecorderCode: identifier(value.recorderGatewayRecorderCode, "recorderGatewayRecorderCode"),
      requestedAt: timestamp(value.requestedAt, "requestedAt"),
    };
    assertLabReplayCreateRequestShape(request);
    return request;
  }
  if (value.kind === "recorder-detail-read") {
    return recorderDetailReadRequest(value);
  }
  if (value.kind === "recorder-list-read") {
    return recorderListReadRequest(value);
  }
  if (value.kind === "lab-resource-command") {
    const action = labResourceAction(value.action);
    const resourceType = labResourceType(value.resourceType);
    const cascade = value.cascade === undefined ? undefined : labResourceCascade(value.cascade);
    const request: RuntimeConsoleLabResourceCommandRequest = {
      kind: "lab-resource-command",
      requestId: identifier(value.requestId, "requestId"),
      resourceType,
      resourceId: identifier(value.resourceId, "resourceId"),
      expectedResourceRevision: positiveInteger(value.expectedResourceRevision, "expectedResourceRevision"),
      action,
      ...(cascade === undefined ? {} : { cascade }),
    };
    assertLabResourceCommandRequestShape(request);
    return request;
  }
  if (value.kind === "external-upstream-apply") {
    const request: RuntimeConsoleExternalUpstreamApplyRequest = {
      kind: "external-upstream-apply",
      requestId: identifier(value.requestId, "requestId"),
      integrationId: identifier(value.integrationId, "integrationId"),
      expectedResourceRevision: nonNegativeInteger(value.expectedResourceRevision, "expectedResourceRevision"),
      provider: integrationProviderReference(value.provider),
      endpointReference: resourceReference(value.endpointReference, "endpointReference"),
      ...(value.credentialReference === undefined ? {} : { credentialReference: secretReference(value.credentialReference, "credentialReference") }),
    };
    assertExternalUpstreamApplyRequestShape(request);
    return request;
  }
  if (value.kind === "runtime-topology-apply") {
    const request: RuntimeConsoleTopologyApplyRequest = {
      kind: "runtime-topology-apply",
      requestId: identifier(value.requestId, "requestId"),
      topologyId: identifier(value.topologyId, "topologyId"),
      expectedResourceRevision: nonNegativeInteger(value.expectedResourceRevision, "expectedResourceRevision"),
      profileKind: topologyProfileKind(value.profileKind),
      endpointReference: resourceReference(value.endpointReference, "endpointReference"),
      ...(value.credentialReference === undefined ? {} : { credentialReference: secretReference(value.credentialReference, "credentialReference") }),
    };
    assertTopologyApplyRequestShape(request);
    return request;
  }
  if (value.kind === "time-authority-apply") {
    const request: RuntimeConsoleTimeAuthorityApplyRequest = {
      kind: "time-authority-apply",
      scope: operationalScope(value.scope),
      requestId: identifier(value.requestId, "requestId"),
      authorityId: identifier(value.authorityId, "authorityId"),
      expectedResourceRevision: nonNegativeInteger(value.expectedResourceRevision, "expectedResourceRevision"),
      node: nodeReference(value.node, "node"),
      profile: identifier(value.profile, "profile"),
      source: timeSource(value.source),
    };
    assertTimeAuthorityApplyRequestShape(request);
    return request;
  }
  if (value.kind === "telemetry-pipeline-apply") {
    const request: RuntimeConsoleTelemetryPipelineApplyRequest = {
      kind: "telemetry-pipeline-apply",
      scope: operationalScope(value.scope),
      requestId: identifier(value.requestId, "requestId"),
      pipelineId: identifier(value.pipelineId, "pipelineId"),
      expectedResourceRevision: nonNegativeInteger(value.expectedResourceRevision, "expectedResourceRevision"),
      node: nodeReference(value.node, "node"),
      collectorReference: resourceReference(value.collectorReference, "collectorReference"),
      redaction: telemetryRedactionPolicy(value.redaction),
    };
    assertTelemetryPipelineApplyRequestShape(request);
    return request;
  }
  throw new Error("runtime console control request kind is not published");
}

function assertGuestLifecycleRequestShape(request: RuntimeConsoleGuestLifecycleRequest): void {
  lifecycleAction(request.action);
  nonEmptyString(request.requestId, "requestId");
  nonEmptyString(request.guestRuntimeControlEndpointId, "guestRuntimeControlEndpointId");
  nonNegativeInteger(request.expectedResourceRevision, "expectedResourceRevision");
}

function assertArchiveCredentialMaterialProvisionRequestShape(request: RuntimeConsoleArchiveCredentialMaterialProvisionRequest): void {
	nonEmptyString(request.credentialReference.kind, "credentialReference.kind");
	nonEmptyString(request.credentialReference.id, "credentialReference.id");
	boundedSecretInput(request.userId, "userId", 1024);
	boundedSecretInput(request.password, "password", 4096);
}

function assertArtifactExportRequestShape(request: RuntimeConsoleArtifactExportRequest): void {
  identifier(request.requestId, "requestId");
  identifier(request.virtualRecorderId, "virtualRecorderId");
  positiveInteger(request.expectedResourceRevision, "expectedResourceRevision");
  identifier(request.coldPathFinalizationReceiptId, "coldPathFinalizationReceiptId");
  integrationProviderReference(request.provider);
}

function assertUpdateBundleImportRequestShape(request: RuntimeConsoleUpdateBundleImportRequest): void {
  nonEmptyString(request.requestId, "requestId");
  boundedHostPath(request.sourceDirectory, "sourceDirectory");
}

function assertUpdateBundleApplyRequestShape(request: RuntimeConsoleUpdateBundleApplyRequest): void {
  nonEmptyString(request.requestId, "requestId");
  nonEmptyString(request.installationId, "installationId");
  positiveInteger(request.expectedInstallationRevision, "expectedInstallationRevision");
  nonEmptyString(request.bundleReferenceId, "bundleReferenceId");
}

function assertLabSessionCreateRequestShape(request: RuntimeConsoleLabSessionCreateRequest): void {
  identifier(request.requestId, "requestId");
  identifier(request.sessionId, "sessionId");
  boundedLabText(request.name, "name");
  boundedLabText(request.scenario, "scenario");
  boundedPositiveInteger(request.recorderCount, "recorderCount", 64);
}

function assertLabReplayCreateRequestShape(request: RuntimeConsoleLabReplayCreateRequest): void {
  identifier(request.requestId, "requestId");
  identifier(request.replayId, "replayId");
  if (request.sourceReference.resourceType !== "lab-replay-source") {
    throw new Error("sourceReference.resourceType must be lab-replay-source");
  }
  identifier(request.sourceReference.resourceId, "sourceReference.resourceId");
  sha256(request.sourceSha256, "sourceSha256");
  identifier(request.recorderGatewayRecorderCode, "recorderGatewayRecorderCode");
  timestamp(request.requestedAt, "requestedAt");
}

function recorderListReadRequest(value: unknown): RuntimeConsoleRecorderListReadRequest {
  if (!isRecord(value) || value.kind !== "recorder-list-read") {
    throw new Error("Recorder list read must be an object");
  }
  const limit = boundedPositiveInteger(value.limit, "limit", 100);
  const cursor = value.cursor === undefined ? undefined : boundedCursor(value.cursor);
  return {
    kind: "recorder-list-read",
    limit,
    ...(cursor === undefined ? {} : { cursor }),
  };
}

function recorderDetailReadRequest(value: unknown): RuntimeConsoleRecorderDetailReadRequest {
  if (!isRecord(value) || value.kind !== "recorder-detail-read") {
    throw new Error("Recorder detail read must be an object");
  }
  const resource = recorderDetailResource(value.resource);
  const recorderId = identifier(value.recorderId, "recorderId");
  if (resource === "observability-summary") {
    if (value.limit !== undefined || value.cursor !== undefined) {
      throw new Error("observability-summary does not accept pagination");
    }
    return { kind: "recorder-detail-read", resource, recorderId };
  }
  const limit = boundedPositiveInteger(value.limit, "limit", 100);
  const cursor = value.cursor === undefined ? undefined : boundedCursor(value.cursor);
  return {
    kind: "recorder-detail-read",
    resource,
    recorderId,
    limit,
    ...(cursor === undefined ? {} : { cursor }),
  };
}

function recorderDetailResource(value: unknown): RuntimeConsoleRecorderDetailResource {
  if (value === "observability-summary" || value === "observation-timeline" || value === "incidents" || value === "artifacts") {
    return value;
  }
  throw new Error("Recorder detail resource is not published");
}

function boundedCursor(value: unknown): string {
  const cursor = nonEmptyString(value, "cursor");
  if (cursor.length > 2048) {
    throw new Error("cursor must contain at most 2048 characters");
  }
  return cursor;
}

function assertLabResourceCommandRequestShape(request: RuntimeConsoleLabResourceCommandRequest): void {
  identifier(request.requestId, "requestId");
  labResourceType(request.resourceType);
  identifier(request.resourceId, "resourceId");
  positiveInteger(request.expectedResourceRevision, "expectedResourceRevision");
  const action = labResourceAction(request.action);
  if ((action === "start" || action === "stop") && request.resourceType === "lab-bed") {
    throw new Error("start and stop require a Lab session or virtual recorder");
  }
  if ((action === "hide" || action === "unhide") && request.resourceType === "lab-session") {
    throw new Error("hide and unhide require a Lab bed or virtual recorder");
  }
  if (action === "detach" && request.resourceType !== "virtual-recorder") {
    throw new Error("detach requires a virtual recorder");
  }
  if (action === "delete") {
    const expectedCascade = request.resourceType === "lab-session" ? "owned-resources" : "none";
    if (request.cascade !== expectedCascade) {
      throw new Error(`delete requires cascade=${expectedCascade}`);
    }
    return;
  }
  if (request.cascade !== undefined) {
    throw new Error("cascade is only valid for delete");
  }
}

function assertExternalUpstreamApplyRequestShape(request: RuntimeConsoleExternalUpstreamApplyRequest): void {
  identifier(request.requestId, "requestId");
  identifier(request.integrationId, "integrationId");
  nonNegativeInteger(request.expectedResourceRevision, "expectedResourceRevision");
  integrationProviderReference(request.provider);
  resourceReference(request.endpointReference, "endpointReference");
  if (request.credentialReference !== undefined) {
    secretReference(request.credentialReference, "credentialReference");
  }
}

function assertTopologyApplyRequestShape(request: RuntimeConsoleTopologyApplyRequest): void {
  identifier(request.requestId, "requestId");
  identifier(request.topologyId, "topologyId");
  nonNegativeInteger(request.expectedResourceRevision, "expectedResourceRevision");
  const profileKind = topologyProfileKind(request.profileKind);
  const endpoint = resourceReference(request.endpointReference, "endpointReference");
  if (profileKind === "external-upstream" && endpoint.resourceType !== "external-upstream-integration") {
    throw new Error("external-upstream topology requires endpointReference.resourceType external-upstream-integration");
  }
  if (request.credentialReference !== undefined) {
    secretReference(request.credentialReference, "credentialReference");
  }
}

function assertTimeAuthorityApplyRequestShape(request: RuntimeConsoleTimeAuthorityApplyRequest): void {
  operationalScope(request.scope);
  identifier(request.requestId, "requestId");
  identifier(request.authorityId, "authorityId");
  nonNegativeInteger(request.expectedResourceRevision, "expectedResourceRevision");
  nodeReference(request.node, "node");
  identifier(request.profile, "profile");
  timeSource(request.source);
}

function assertTelemetryPipelineApplyRequestShape(request: RuntimeConsoleTelemetryPipelineApplyRequest): void {
  operationalScope(request.scope);
  identifier(request.requestId, "requestId");
  identifier(request.pipelineId, "pipelineId");
  nonNegativeInteger(request.expectedResourceRevision, "expectedResourceRevision");
  nodeReference(request.node, "node");
  resourceReference(request.collectorReference, "collectorReference");
  telemetryRedactionPolicy(request.redaction);
}

function isRuntimeConsoleReadName(value: unknown): value is RuntimeConsoleReadName {
  return typeof value === "string" && (runtimeConsoleReadNames as readonly string[]).includes(value);
}

function lifecycleAction(value: unknown): RuntimeConsoleGuestLifecycleAction {
  if (value === "start" || value === "stop" || value === "reboot") {
    return value;
  }
  throw new Error("guest lifecycle action must be start, stop, or reboot");
}

function labResourceType(value: unknown): RuntimeConsoleLabResourceType {
  if (value === "lab-session" || value === "lab-bed" || value === "virtual-recorder") {
    return value;
  }
  throw new Error("resourceType must be lab-session, lab-bed, or virtual-recorder");
}

function labResourceAction(value: unknown): RuntimeConsoleLabResourceAction {
  if (value === "start" || value === "stop" || value === "hide" || value === "unhide" || value === "detach" || value === "delete") {
    return value;
  }
  throw new Error("action must be one published Lab resource action");
}

function labResourceCascade(value: unknown): "none" | "owned-resources" {
  if (value === "none" || value === "owned-resources") {
    return value;
  }
  throw new Error("cascade must be none or owned-resources");
}

function topologyProfileKind(value: unknown): RuntimeConsoleTopologyProfileKind {
  if (value === "bundled-upstream" || value === "external-upstream") {
    return value;
  }
  throw new Error("profileKind must be bundled-upstream or external-upstream");
}

function operationalScope(value: unknown): RuntimeConsoleOperationalScope {
  if (value === "host" || value === "guest") {
    return value;
  }
  throw new Error("scope must be host or guest");
}

function nodeReference(value: unknown, field: string): RuntimeConsoleNodeReference {
  if (!isRecord(value) || !hasOnlyKeys(value, ["kind", "id"])) {
    throw new Error(`${field} must be an exact node reference`);
  }
  return { kind: identifier(value.kind, `${field}.kind`), id: identifier(value.id, `${field}.id`) };
}

function timeSource(value: unknown): RuntimeConsoleTimeAuthorityApplyRequest["source"] {
  if (!isRecord(value) || !hasOnlyKeys(value, ["profile", "sourceId"])) {
    throw new Error("source must be an exact NTP source reference");
  }
  return { profile: identifier(value.profile, "source.profile"), sourceId: identifier(value.sourceId, "source.sourceId") };
}

function telemetryRedactionPolicy(value: unknown): RuntimeConsoleTelemetryRedactionPolicy {
  if (!isRecord(value) || !hasOnlyKeys(value, ["allowedAttributeKeys", "maxAttributes", "maxValueLength", "maxDistinctValuesPerKey"])) {
    throw new Error("redaction must be an exact telemetry redaction policy");
  }
  if (!Array.isArray(value.allowedAttributeKeys) || value.allowedAttributeKeys.length < 1 || value.allowedAttributeKeys.length > 32) {
    throw new Error("redaction.allowedAttributeKeys must contain 1 through 32 keys");
  }
  const keys = value.allowedAttributeKeys.map((key, index) => telemetryAttributeKey(key, `redaction.allowedAttributeKeys[${index}]`));
  if (new Set(keys).size !== keys.length) {
    throw new Error("redaction.allowedAttributeKeys must not repeat a key");
  }
  return {
    allowedAttributeKeys: keys,
    maxAttributes: boundedPositiveInteger(value.maxAttributes, "redaction.maxAttributes", 32),
    maxValueLength: boundedPositiveInteger(value.maxValueLength, "redaction.maxValueLength", 256),
    maxDistinctValuesPerKey: boundedPositiveInteger(value.maxDistinctValuesPerKey, "redaction.maxDistinctValuesPerKey", 100),
  };
}

function telemetryAttributeKey(value: unknown, field: string): string {
  const key = nonEmptyString(value, field);
  if (!/^[a-z][a-z0-9_.-]*$/.test(key) || /(password|secret|token|credential|authorization)/.test(key)) {
    throw new Error(`${field} must be a non-sensitive telemetry attribute key`);
  }
  return key;
}

function nonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value === "") {
    throw new Error(`${field} must be a non-empty string`);
  }
  return value;
}

function identifier(value: unknown, field: string): string {
  const text = nonEmptyString(value, field);
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(text)) {
    throw new Error(`${field} must be a v1 identifier`);
  }
  return text;
}

function sha256(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/.test(value)) {
    throw new Error(`${field} must be a lowercase SHA-256 digest`);
  }
  return value;
}

function timestamp(value: unknown, field: string): string {
  if (typeof value !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) ||
      Number.isNaN(Date.parse(value))) {
    throw new Error(`${field} must be an RFC 3339 timestamp`);
  }
  return value;
}

function nonNegativeInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative integer`);
  }
  return value;
}

function positiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`${field} must be a positive integer`);
  }
  return value;
}

function boundedHostPath(value: unknown, field: string): string {
  if (typeof value !== "string" || value === "" || value.length > 4096 || value.includes("\u0000")) {
    throw new Error(`${field} must be a bounded non-empty Host path`);
  }
  return value;
}

function boundedSecretInput(value: unknown, field: string, maximumLength: number): string {
	if (typeof value !== "string" || value === "" || value.length > maximumLength) {
		throw new Error(`${field} must be a bounded non-empty string`);
	}
	return value;
}

function boundedLabText(value: unknown, field: string): string {
  const text = nonEmptyString(value, field);
  if (text.length > 128) {
    throw new Error(`${field} must be a non-empty string of at most 128 characters`);
  }
  return text;
}

function boundedPositiveInteger(value: unknown, field: string, maximum: number): number {
  const integer = positiveInteger(value, field);
  if (integer > maximum) {
    throw new Error(`${field} must be at most ${maximum}`);
  }
  return integer;
}

function resourceReference(value: unknown, field: string): RuntimeConsoleResourceReference {
  if (!isRecord(value) || !hasOnlyKeys(value, ["resourceType", "resourceId"])) {
    throw new Error(`${field} must be an exact resource reference`);
  }
  return {
    resourceType: identifier(value.resourceType, `${field}.resourceType`),
    resourceId: identifier(value.resourceId, `${field}.resourceId`),
  };
}

function secretReference(value: unknown, field: string): RuntimeConsoleSecretReference {
  if (!isRecord(value) || !hasOnlyKeys(value, ["kind", "id"])) {
    throw new Error(`${field} must be an exact secret reference`);
  }
  return {
    kind: identifier(value.kind, `${field}.kind`),
    id: identifier(value.id, `${field}.id`),
  };
}

function integrationProviderReference(value: unknown): RuntimeConsoleIntegrationProviderReference {
  if (!isRecord(value) || !hasOnlyKeys(value, ["kind", "id", "capabilityRevision"])) {
    throw new Error("provider must be an exact provider reference");
  }
  return {
    kind: identifier(value.kind, "provider.kind"),
    id: identifier(value.id, "provider.id"),
    capabilityRevision: positiveInteger(value.capabilityRevision, "provider.capabilityRevision"),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
	const actual = Object.keys(value);
	return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}
