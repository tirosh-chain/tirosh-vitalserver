import { useCallback, useEffect, useMemo, useState, type ReactElement } from "react";
import { createRoot } from "react-dom/client";

import type {
  RuntimeConsoleControlResponse,
  RuntimeConsoleControlTransport,
  RuntimeConsoleGuestLifecycleAction,
  RuntimeConsoleGuestLifecycleRequest,
  RuntimeConsoleArchiveCredentialMaterialProvisionRequest,
  RuntimeConsoleArtifactExportRequest,
  RuntimeConsoleExternalUpstreamApplyRequest,
  RuntimeConsoleLabResourceAction,
  RuntimeConsoleLabResourceCommandRequest,
  RuntimeConsoleLabSessionCreateRequest,
  RuntimeConsoleUpdateBundleApplyRequest,
  RuntimeConsoleUpdateBundleImportRequest,
  RuntimeConsoleReadName,
  RuntimeConsoleTopologyApplyRequest,
  RuntimeConsoleTopologyProfileKind,
  RuntimeConsoleOperationalScope,
  RuntimeConsoleTelemetryPipelineApplyRequest,
  RuntimeConsoleTimeAuthorityApplyRequest,
} from "@tirosh-chain/runtime-console-control-contract";

import "./runtime_console_styles.css";

declare global {
  interface Window {
    vitalServerRuntimeConsole?: RuntimeConsoleControlTransport;
    vitalServerRuntimeConsoleDirectorySelector?: {
      selectUpdateBundleDirectory(): Promise<string | undefined>;
    };
  }
}

type ReadView = {
  readonly response?: RuntimeConsoleControlResponse;
  readonly interfaceError?: string;
  readonly pending: boolean;
};

type LabResourceOption = {
  readonly selectionKey: string;
  readonly resourceType: "lab-session" | "lab-bed" | "virtual-recorder";
  readonly id: string;
  readonly revision: number;
  readonly name: string;
  readonly state: string;
};

const readLabels: Readonly<Record<RuntimeConsoleReadName, string>> = {
  "installation": "Host installation",
  "guest-runtime-control-endpoint": "Guest control endpoint",
  "runtime-readiness": "Guest readiness",
  "runtime-topology": "Runtime topology",
  "runtime-capabilities": "Runtime capabilities",
  "host-clock-quality": "Host clock quality",
  "guest-clock-quality": "Guest clock quality",
  "lab-sessions": "Lab sessions",
  "lab-beds": "Lab beds",
  "lab-recorders": "Lab virtual recorders",
  "archive-export-provider": "Archive Export provider",
  "archive-credential-material": "Archive credential material",
  "external-upstreams": "External upstreams",
  "outbound-relays": "Outbound relays",
  "recorder-observations": "Vital Recorder observations",
};

const runtimeConsoleReadEntries = Object.entries(readLabels) as ReadonlyArray<readonly [RuntimeConsoleReadName, string]>;

const initialReadViews: Readonly<Record<RuntimeConsoleReadName, ReadView>> = {
  "installation": { pending: false },
  "guest-runtime-control-endpoint": { pending: false },
  "runtime-readiness": { pending: false },
  "runtime-topology": { pending: false },
  "runtime-capabilities": { pending: false },
  "host-clock-quality": { pending: false },
  "guest-clock-quality": { pending: false },
  "lab-sessions": { pending: false },
  "lab-beds": { pending: false },
  "lab-recorders": { pending: false },
  "archive-export-provider": { pending: false },
  "archive-credential-material": { pending: false },
  "external-upstreams": { pending: false },
  "outbound-relays": { pending: false },
  "recorder-observations": { pending: false },
};

function RuntimeConsoleApplication({ transport }: { readonly transport?: RuntimeConsoleControlTransport }): ReactElement {
  const [reads, setReads] = useState<Readonly<Record<RuntimeConsoleReadName, ReadView>>>(initialReadViews);
  const [requestId, setRequestId] = useState("");
  const [commandResponse, setCommandResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [commandInterfaceError, setCommandInterfaceError] = useState<string | undefined>();
  const [commandPending, setCommandPending] = useState(false);
	const [credentialUserId, setCredentialUserId] = useState("");
	const [credentialPassword, setCredentialPassword] = useState("");
	const [credentialProvisionPending, setCredentialProvisionPending] = useState(false);
	const [credentialProvisionResponse, setCredentialProvisionResponse] = useState<RuntimeConsoleControlResponse | undefined>();
	const [credentialProvisionInterfaceError, setCredentialProvisionInterfaceError] = useState<string | undefined>();
  const [updateBundleSourceDirectory, setUpdateBundleSourceDirectory] = useState("");
  const [updateBundleID, setUpdateBundleID] = useState("");
  const [updateImportRequestID, setUpdateImportRequestID] = useState("");
  const [updateApplyRequestID, setUpdateApplyRequestID] = useState("");
  const [updateImportPending, setUpdateImportPending] = useState(false);
  const [updateApplyPending, setUpdateApplyPending] = useState(false);
  const [updateImportResponse, setUpdateImportResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [updateApplyResponse, setUpdateApplyResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [updateInterfaceError, setUpdateInterfaceError] = useState<string | undefined>();
  const [labCreateRequestID, setLabCreateRequestID] = useState("");
  const [labSessionID, setLabSessionID] = useState("");
  const [labName, setLabName] = useState("");
  const [labScenario, setLabScenario] = useState("");
  const [labRecorderCount, setLabRecorderCount] = useState("1");
  const [labCreatePending, setLabCreatePending] = useState(false);
  const [labCreateResponse, setLabCreateResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [labResourceRequestID, setLabResourceRequestID] = useState("");
  const [selectedLabResourceKey, setSelectedLabResourceKey] = useState("");
  const [labResourceAction, setLabResourceAction] = useState<RuntimeConsoleLabResourceAction>("start");
  const [labResourcePending, setLabResourcePending] = useState(false);
  const [labResourceResponse, setLabResourceResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [archiveExportRequestID, setArchiveExportRequestID] = useState("");
  const [archiveExportPending, setArchiveExportPending] = useState(false);
  const [archiveExportResponse, setArchiveExportResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [archiveExportInterfaceError, setArchiveExportInterfaceError] = useState<string | undefined>();
  const [labInterfaceError, setLabInterfaceError] = useState<string | undefined>();
  const [externalRequestID, setExternalRequestID] = useState("");
  const [externalIntegrationID, setExternalIntegrationID] = useState("");
  const [externalExpectedRevision, setExternalExpectedRevision] = useState("0");
  const [externalProviderKind, setExternalProviderKind] = useState("");
  const [externalProviderID, setExternalProviderID] = useState("");
  const [externalProviderCapabilityRevision, setExternalProviderCapabilityRevision] = useState("1");
  const [externalEndpointResourceType, setExternalEndpointResourceType] = useState("");
  const [externalEndpointResourceID, setExternalEndpointResourceID] = useState("");
  const [externalCredentialKind, setExternalCredentialKind] = useState("");
  const [externalCredentialID, setExternalCredentialID] = useState("");
  const [externalPending, setExternalPending] = useState(false);
  const [externalResponse, setExternalResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [externalInterfaceError, setExternalInterfaceError] = useState<string | undefined>();
  const [topologyRequestID, setTopologyRequestID] = useState("");
  const [topologyID, setTopologyID] = useState("");
  const [topologyExpectedRevision, setTopologyExpectedRevision] = useState("0");
  const [topologyProfileKind, setTopologyProfileKind] = useState<RuntimeConsoleTopologyProfileKind>("external-upstream");
  const [topologyEndpointResourceType, setTopologyEndpointResourceType] = useState("external-upstream-integration");
  const [topologyEndpointResourceID, setTopologyEndpointResourceID] = useState("");
  const [topologyCredentialKind, setTopologyCredentialKind] = useState("");
  const [topologyCredentialID, setTopologyCredentialID] = useState("");
  const [topologyPending, setTopologyPending] = useState(false);
  const [topologyResponse, setTopologyResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [topologyInterfaceError, setTopologyInterfaceError] = useState<string | undefined>();
  const [timeScope, setTimeScope] = useState<RuntimeConsoleOperationalScope>("host");
  const [timeRequestID, setTimeRequestID] = useState("");
  const [timeAuthorityID, setTimeAuthorityID] = useState("");
  const [timeExpectedRevision, setTimeExpectedRevision] = useState("0");
  const [timeNodeKind, setTimeNodeKind] = useState("");
  const [timeNodeID, setTimeNodeID] = useState("");
  const [timeProfile, setTimeProfile] = useState("enterprise-ntp");
  const [timeSourceProfile, setTimeSourceProfile] = useState("enterprise-ntp");
  const [timeSourceID, setTimeSourceID] = useState("");
  const [timePending, setTimePending] = useState(false);
  const [timeResponse, setTimeResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [timeInterfaceError, setTimeInterfaceError] = useState<string | undefined>();
  const [telemetryScope, setTelemetryScope] = useState<RuntimeConsoleOperationalScope>("guest");
  const [telemetryRequestID, setTelemetryRequestID] = useState("");
  const [telemetryPipelineID, setTelemetryPipelineID] = useState("");
  const [telemetryExpectedRevision, setTelemetryExpectedRevision] = useState("0");
  const [telemetryNodeKind, setTelemetryNodeKind] = useState("");
  const [telemetryNodeID, setTelemetryNodeID] = useState("");
  const [telemetryCollectorResourceType, setTelemetryCollectorResourceType] = useState("otel-collector");
  const [telemetryCollectorResourceID, setTelemetryCollectorResourceID] = useState("");
  const [telemetryAllowedAttributeKeys, setTelemetryAllowedAttributeKeys] = useState("operation.kind,outcome.code");
  const [telemetryMaxAttributes, setTelemetryMaxAttributes] = useState("8");
  const [telemetryMaxValueLength, setTelemetryMaxValueLength] = useState("128");
  const [telemetryMaxDistinctValuesPerKey, setTelemetryMaxDistinctValuesPerKey] = useState("32");
  const [telemetryPending, setTelemetryPending] = useState(false);
  const [telemetryResponse, setTelemetryResponse] = useState<RuntimeConsoleControlResponse | undefined>();
  const [telemetryInterfaceError, setTelemetryInterfaceError] = useState<string | undefined>();

  const readOwnerResource = useCallback(async (resource: RuntimeConsoleReadName): Promise<void> => {
    if (transport === undefined) {
      setReads((current) => ({
        ...current,
        [resource]: { pending: false, interfaceError: "The desktop control transport was not provided." },
      }));
      return;
    }
    setReads((current) => ({ ...current, [resource]: { pending: true } }));
    try {
      const response = await transport.request({ kind: "read", resource });
      setReads((current) => ({ ...current, [resource]: { pending: false, response } }));
    } catch (error: unknown) {
      setReads((current) => ({
        ...current,
        [resource]: { pending: false, interfaceError: interfaceErrorMessage(error) },
      }));
    }
  }, [transport]);

  useEffect(() => {
    void Promise.all(runtimeConsoleReadEntries.map(([resource]) => readOwnerResource(resource)));
  }, [readOwnerResource]);

  const guestLifecycleInput = useMemo(
    () => ownerSuppliedGuestLifecycleInput((reads["guest-runtime-control-endpoint"] ?? initialReadViews["guest-runtime-control-endpoint"]).response),
    [reads],
  );
	const archiveCredentialReference = useMemo(
		() => ownerSuppliedArchiveCredentialReference((reads["archive-credential-material"] ?? initialReadViews["archive-credential-material"]).response),
		[reads],
	);
  const archiveExportProvider = useMemo(
    () => ownerSuppliedArchiveExportProvider((reads["archive-export-provider"] ?? initialReadViews["archive-export-provider"]).response),
    [reads],
  );
  const installationInput = useMemo(
    () => ownerSuppliedInstallationInput((reads["installation"] ?? initialReadViews["installation"]).response),
    [reads],
  );
  const labResourceOptions = useMemo(
    () => ownerSuppliedLabResourceOptions(
      (reads["lab-sessions"] ?? initialReadViews["lab-sessions"]).response,
      (reads["lab-beds"] ?? initialReadViews["lab-beds"]).response,
      (reads["lab-recorders"] ?? initialReadViews["lab-recorders"]).response,
    ),
    [reads],
  );
  const selectedLabResource = useMemo(
    () => labResourceOptions.find((option) => option.selectionKey === selectedLabResourceKey),
    [labResourceOptions, selectedLabResourceKey],
  );
  const selectedLabResourceActions = useMemo(
    () => selectedLabResource === undefined ? [] : supportedLabActions(selectedLabResource.resourceType),
    [selectedLabResource],
  );
  const selectedLabRecorderArchiveCandidate = useMemo(
    () => ownerSuppliedManualArchiveExportCandidate(
      selectedLabResourceKey,
      (reads["lab-recorders"] ?? initialReadViews["lab-recorders"]).response,
    ),
    [reads, selectedLabResourceKey],
  );
  const topologyOwnerInput = useMemo(
    () => ownerSuppliedTopologyInput((reads["runtime-topology"] ?? initialReadViews["runtime-topology"]).response),
    [reads],
  );

  useEffect(() => {
    if (selectedLabResource === undefined) {
      return;
    }
    if (!selectedLabResourceActions.includes(labResourceAction)) {
      setLabResourceAction(selectedLabResourceActions[0] ?? "start");
    }
  }, [labResourceAction, selectedLabResource, selectedLabResourceActions]);

  const submitGuestLifecycle = useCallback(async (action: RuntimeConsoleGuestLifecycleAction): Promise<void> => {
    if (transport === undefined) {
      setCommandInterfaceError("The desktop control transport was not provided.");
      return;
    }
    if (guestLifecycleInput === undefined) {
      setCommandInterfaceError("Read an available Guest control endpoint before requesting Guest start.");
      return;
    }
    if (requestId === "") {
      setCommandInterfaceError("Request ID is required and must be supplied by the operator.");
      return;
    }
    const request: RuntimeConsoleGuestLifecycleRequest = {
      kind: "guest-lifecycle",
      action,
      requestId,
      guestRuntimeControlEndpointId: guestLifecycleInput.id,
      expectedResourceRevision: guestLifecycleInput.revision,
    };
    setCommandPending(true);
    setCommandInterfaceError(undefined);
    setCommandResponse(undefined);
    try {
      setCommandResponse(await transport.request(request));
    } catch (error: unknown) {
      setCommandInterfaceError(interfaceErrorMessage(error));
    } finally {
      setCommandPending(false);
    }
  }, [guestLifecycleInput, requestId, transport]);

	const provisionArchiveCredentialMaterial = useCallback(async (): Promise<void> => {
		if (transport === undefined) {
			setCredentialProvisionInterfaceError("The desktop control transport was not provided.");
			return;
		}
		if (archiveCredentialReference === undefined) {
			setCredentialProvisionInterfaceError("Read the configured archive credential-material status before provisioning credentials.");
			return;
		}
		if (credentialUserId === "" || credentialPassword === "") {
			setCredentialProvisionInterfaceError("User ID and password are required. They are sent only to the local Host Agent facade and are not displayed again.");
			return;
		}
		const request: RuntimeConsoleArchiveCredentialMaterialProvisionRequest = {
			kind: "archive-credential-material-provision",
			credentialReference: archiveCredentialReference,
			userId: credentialUserId,
			password: credentialPassword,
		};
		setCredentialProvisionPending(true);
		setCredentialProvisionInterfaceError(undefined);
		setCredentialProvisionResponse(undefined);
		try {
			setCredentialProvisionResponse(await transport.request(request));
			await readOwnerResource("archive-credential-material");
		} catch (error: unknown) {
			setCredentialProvisionInterfaceError(interfaceErrorMessage(error));
		} finally {
			setCredentialUserId("");
			setCredentialPassword("");
			setCredentialProvisionPending(false);
		}
	}, [archiveCredentialReference, credentialPassword, credentialUserId, readOwnerResource, transport]);

  const selectUpdateBundleDirectory = useCallback(async (): Promise<void> => {
    const selector = window.vitalServerRuntimeConsoleDirectorySelector;
    if (selector === undefined) {
      setUpdateInterfaceError("This interface does not provide an OS-authorized update-bundle directory selector. Enter an explicit Host-local directory path only when your operator environment permits it.");
      return;
    }
    try {
      const selected = await selector.selectUpdateBundleDirectory();
      if (selected !== undefined) {
        setUpdateBundleSourceDirectory(selected);
      }
    } catch (error: unknown) {
      setUpdateInterfaceError(interfaceErrorMessage(error));
    }
  }, []);

  const importUpdateBundle = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setUpdateInterfaceError("The desktop control transport was not provided.");
      return;
    }
    if (updateImportRequestID === "" || updateBundleSourceDirectory === "") {
      setUpdateInterfaceError("Import request ID and an explicit Host-local bundle directory are required.");
      return;
    }
    const request: RuntimeConsoleUpdateBundleImportRequest = {
      kind: "update-bundle-import",
      requestId: updateImportRequestID,
      sourceDirectory: updateBundleSourceDirectory,
    };
    setUpdateImportPending(true);
    setUpdateInterfaceError(undefined);
    setUpdateImportResponse(undefined);
    try {
      const response = await transport.request(request);
      setUpdateImportResponse(response);
      const importedID = ownerSuppliedImportedUpdateBundleID(response);
      if (importedID !== undefined) {
        setUpdateBundleID(importedID);
      }
    } catch (error: unknown) {
      setUpdateInterfaceError(interfaceErrorMessage(error));
    } finally {
      setUpdateImportPending(false);
    }
  }, [transport, updateBundleSourceDirectory, updateImportRequestID]);

  const applyUpdateBundle = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setUpdateInterfaceError("The desktop control transport was not provided.");
      return;
    }
    if (installationInput === undefined) {
      setUpdateInterfaceError("Read the Host-owned installation before requesting an update.");
      return;
    }
    if (updateApplyRequestID === "" || updateBundleID === "") {
      setUpdateInterfaceError("Update request ID and imported bundle ID are required.");
      return;
    }
    const request: RuntimeConsoleUpdateBundleApplyRequest = {
      kind: "update-bundle-apply",
      requestId: updateApplyRequestID,
      installationId: installationInput.id,
      expectedInstallationRevision: installationInput.revision,
      bundleReferenceId: updateBundleID,
    };
    setUpdateApplyPending(true);
    setUpdateInterfaceError(undefined);
    setUpdateApplyResponse(undefined);
    try {
      setUpdateApplyResponse(await transport.request(request));
    } catch (error: unknown) {
      setUpdateInterfaceError(interfaceErrorMessage(error));
    } finally {
      setUpdateApplyPending(false);
    }
  }, [installationInput, transport, updateApplyRequestID, updateBundleID]);

  const createLabSession = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setLabInterfaceError("The desktop control transport was not provided.");
      return;
    }
    const recorderCount = Number(labRecorderCount);
    if (!Number.isInteger(recorderCount)) {
      setLabInterfaceError("Recorder count must be an integer from 1 through 64.");
      return;
    }
    const request: RuntimeConsoleLabSessionCreateRequest = {
      kind: "lab-session-create",
      requestId: labCreateRequestID,
      sessionId: labSessionID,
      name: labName,
      scenario: labScenario,
      recorderCount,
    };
    setLabCreatePending(true);
    setLabInterfaceError(undefined);
    setLabCreateResponse(undefined);
    try {
      setLabCreateResponse(await transport.request(request));
      await Promise.all([readOwnerResource("lab-sessions"), readOwnerResource("lab-beds"), readOwnerResource("lab-recorders")]);
    } catch (error: unknown) {
      setLabInterfaceError(interfaceErrorMessage(error));
    } finally {
      setLabCreatePending(false);
    }
  }, [labCreateRequestID, labName, labRecorderCount, labScenario, labSessionID, readOwnerResource, transport]);

  const executeLabResourceCommand = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setLabInterfaceError("The desktop control transport was not provided.");
      return;
    }
    if (selectedLabResource === undefined) {
      setLabInterfaceError("Refresh and select one Lab-owned resource before requesting a lifecycle action.");
      return;
    }
    const request: RuntimeConsoleLabResourceCommandRequest = {
      kind: "lab-resource-command",
      requestId: labResourceRequestID,
      resourceType: selectedLabResource.resourceType,
      resourceId: selectedLabResource.id,
      expectedResourceRevision: selectedLabResource.revision,
      action: labResourceAction,
      ...(labResourceAction === "delete" ? { cascade: selectedLabResource.resourceType === "lab-session" ? "owned-resources" : "none" } : {}),
    };
    setLabResourcePending(true);
    setLabInterfaceError(undefined);
    setLabResourceResponse(undefined);
    try {
      setLabResourceResponse(await transport.request(request));
      await Promise.all([readOwnerResource("lab-sessions"), readOwnerResource("lab-beds"), readOwnerResource("lab-recorders")]);
    } catch (error: unknown) {
      setLabInterfaceError(interfaceErrorMessage(error));
    } finally {
      setLabResourcePending(false);
    }
  }, [labResourceAction, labResourceRequestID, readOwnerResource, selectedLabResource, transport]);

  const executeManualArtifactExport = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setArchiveExportInterfaceError("The desktop control transport was not provided.");
      return;
    }
    if (selectedLabRecorderArchiveCandidate === undefined) {
      setArchiveExportInterfaceError("Refresh and select one stopped virtual recorder with an explicit manual-export policy and finalized Recorder Gateway receipt.");
      return;
    }
    if (archiveExportProvider === undefined) {
      setArchiveExportInterfaceError("Read an available Archive Export provider configuration before requesting manual export.");
      return;
    }
    if (archiveExportRequestID === "") {
      setArchiveExportInterfaceError("Archive export request ID is required and must be supplied by the operator.");
      return;
    }
    const request: RuntimeConsoleArtifactExportRequest = {
      kind: "artifact-export",
      requestId: archiveExportRequestID,
      virtualRecorderId: selectedLabRecorderArchiveCandidate.id,
      expectedResourceRevision: selectedLabRecorderArchiveCandidate.revision,
      coldPathFinalizationReceiptId: selectedLabRecorderArchiveCandidate.finalizationReceiptId,
      provider: archiveExportProvider,
    };
    setArchiveExportPending(true);
    setArchiveExportInterfaceError(undefined);
    setArchiveExportResponse(undefined);
    try {
      setArchiveExportResponse(await transport.request(request));
      await readOwnerResource("lab-recorders");
    } catch (error: unknown) {
      setArchiveExportInterfaceError(interfaceErrorMessage(error));
    } finally {
      setArchiveExportPending(false);
    }
  }, [archiveExportProvider, archiveExportRequestID, readOwnerResource, selectedLabRecorderArchiveCandidate, transport]);

  const applyExternalUpstream = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setExternalInterfaceError("The desktop control transport was not provided.");
      return;
    }
    const expectedResourceRevision = Number(externalExpectedRevision);
    const capabilityRevision = Number(externalProviderCapabilityRevision);
    if (!Number.isInteger(expectedResourceRevision) || !Number.isInteger(capabilityRevision)) {
      setExternalInterfaceError("External integration and provider revisions must be explicit integers.");
      return;
    }
    const credentialReference = optionalReference(externalCredentialKind, externalCredentialID, "External credential kind and ID must be supplied together.");
    if (credentialReference instanceof Error) {
      setExternalInterfaceError(credentialReference.message);
      return;
    }
    const request: RuntimeConsoleExternalUpstreamApplyRequest = {
      kind: "external-upstream-apply",
      requestId: externalRequestID,
      integrationId: externalIntegrationID,
      expectedResourceRevision,
      provider: { kind: externalProviderKind, id: externalProviderID, capabilityRevision },
      endpointReference: { resourceType: externalEndpointResourceType, resourceId: externalEndpointResourceID },
      ...(credentialReference === undefined ? {} : { credentialReference }),
    };
    setExternalPending(true);
    setExternalInterfaceError(undefined);
    setExternalResponse(undefined);
    try {
      setExternalResponse(await transport.request(request));
      await Promise.all([readOwnerResource("external-upstreams"), readOwnerResource("runtime-topology"), readOwnerResource("runtime-capabilities")]);
    } catch (error: unknown) {
      setExternalInterfaceError(interfaceErrorMessage(error));
    } finally {
      setExternalPending(false);
    }
  }, [externalCredentialID, externalCredentialKind, externalEndpointResourceID, externalEndpointResourceType, externalExpectedRevision, externalIntegrationID, externalProviderCapabilityRevision, externalProviderID, externalProviderKind, externalRequestID, readOwnerResource, transport]);

  const applyRuntimeTopology = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setTopologyInterfaceError("The desktop control transport was not provided.");
      return;
    }
    const expectedResourceRevision = Number(topologyExpectedRevision);
    if (!Number.isInteger(expectedResourceRevision)) {
      setTopologyInterfaceError("Topology expected revision must be an explicit integer.");
      return;
    }
    const credentialReference = optionalReference(topologyCredentialKind, topologyCredentialID, "Topology credential kind and ID must be supplied together.");
    if (credentialReference instanceof Error) {
      setTopologyInterfaceError(credentialReference.message);
      return;
    }
    const request: RuntimeConsoleTopologyApplyRequest = {
      kind: "runtime-topology-apply",
      requestId: topologyRequestID,
      topologyId: topologyID,
      expectedResourceRevision,
      profileKind: topologyProfileKind,
      endpointReference: { resourceType: topologyEndpointResourceType, resourceId: topologyEndpointResourceID },
      ...(credentialReference === undefined ? {} : { credentialReference }),
    };
    setTopologyPending(true);
    setTopologyInterfaceError(undefined);
    setTopologyResponse(undefined);
    try {
      setTopologyResponse(await transport.request(request));
      await Promise.all([readOwnerResource("runtime-topology"), readOwnerResource("runtime-capabilities"), readOwnerResource("runtime-readiness")]);
    } catch (error: unknown) {
      setTopologyInterfaceError(interfaceErrorMessage(error));
    } finally {
      setTopologyPending(false);
    }
  }, [readOwnerResource, topologyCredentialID, topologyCredentialKind, topologyEndpointResourceID, topologyEndpointResourceType, topologyExpectedRevision, topologyID, topologyProfileKind, topologyRequestID, transport]);

  const applyTimeAuthority = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setTimeInterfaceError("The desktop control transport was not provided.");
      return;
    }
    const expectedResourceRevision = Number(timeExpectedRevision);
    if (!Number.isInteger(expectedResourceRevision) || expectedResourceRevision < 0) {
      setTimeInterfaceError("Time authority expected revision must be a non-negative integer.");
      return;
    }
    const request: RuntimeConsoleTimeAuthorityApplyRequest = {
      kind: "time-authority-apply",
      scope: timeScope,
      requestId: timeRequestID,
      authorityId: timeAuthorityID,
      expectedResourceRevision,
      node: { kind: timeNodeKind, id: timeNodeID },
      profile: timeProfile,
      source: { profile: timeSourceProfile, sourceId: timeSourceID },
    };
    setTimePending(true);
    setTimeInterfaceError(undefined);
    setTimeResponse(undefined);
    try {
      setTimeResponse(await transport.request(request));
      await readOwnerResource(timeScope === "host" ? "host-clock-quality" : "guest-clock-quality");
    } catch (error: unknown) {
      setTimeInterfaceError(interfaceErrorMessage(error));
    } finally {
      setTimePending(false);
    }
  }, [readOwnerResource, timeAuthorityID, timeExpectedRevision, timeNodeID, timeNodeKind, timeProfile, timeRequestID, timeScope, timeSourceID, timeSourceProfile, transport]);

  const applyTelemetryPipeline = useCallback(async (): Promise<void> => {
    if (transport === undefined) {
      setTelemetryInterfaceError("The desktop control transport was not provided.");
      return;
    }
    const expectedResourceRevision = Number(telemetryExpectedRevision);
    const maxAttributes = Number(telemetryMaxAttributes);
    const maxValueLength = Number(telemetryMaxValueLength);
    const maxDistinctValuesPerKey = Number(telemetryMaxDistinctValuesPerKey);
    if (![expectedResourceRevision, maxAttributes, maxValueLength, maxDistinctValuesPerKey].every(Number.isInteger) || expectedResourceRevision < 0) {
      setTelemetryInterfaceError("Telemetry revision and redaction limits must be explicit integers.");
      return;
    }
    const allowedAttributeKeys = telemetryAllowedAttributeKeys.split(",").map((value) => value.trim()).filter((value) => value !== "");
    const request: RuntimeConsoleTelemetryPipelineApplyRequest = {
      kind: "telemetry-pipeline-apply",
      scope: telemetryScope,
      requestId: telemetryRequestID,
      pipelineId: telemetryPipelineID,
      expectedResourceRevision,
      node: { kind: telemetryNodeKind, id: telemetryNodeID },
      collectorReference: { resourceType: telemetryCollectorResourceType, resourceId: telemetryCollectorResourceID },
      redaction: { allowedAttributeKeys, maxAttributes, maxValueLength, maxDistinctValuesPerKey },
    };
    setTelemetryPending(true);
    setTelemetryInterfaceError(undefined);
    setTelemetryResponse(undefined);
    try {
      setTelemetryResponse(await transport.request(request));
    } catch (error: unknown) {
      setTelemetryInterfaceError(interfaceErrorMessage(error));
    } finally {
      setTelemetryPending(false);
    }
  }, [telemetryAllowedAttributeKeys, telemetryCollectorResourceID, telemetryCollectorResourceType, telemetryExpectedRevision, telemetryMaxAttributes, telemetryMaxDistinctValuesPerKey, telemetryMaxValueLength, telemetryNodeID, telemetryNodeKind, telemetryPipelineID, telemetryRequestID, telemetryScope, transport]);

  return (
    <main>
      <header>
        <p className="eyebrow">VitalServer Runtime Platform</p>
        <h1>Runtime Console</h1>
        <p>Owner-supplied control state only. An accepted Host operation is not inferred to be Guest readiness.</p>
      </header>

      <section aria-labelledby="reads-heading">
        <div className="section-heading">
          <h2 id="reads-heading">Owner resources</h2>
          <button type="button" onClick={() => void Promise.all(runtimeConsoleReadEntries.map(([resource]) => readOwnerResource(resource)))}>Refresh all</button>
        </div>
        <div className="resource-grid">
          {runtimeConsoleReadEntries.map(([resource, label]) => (
            <OwnerReadCard key={resource} label={label} view={reads[resource] ?? initialReadViews[resource]} refresh={() => void readOwnerResource(resource)} />
          ))}
        </div>
      </section>

      <section aria-labelledby="guest-start-heading">
        <h2 id="guest-start-heading">Request Guest lifecycle action</h2>
        <p>The endpoint identity and revision below are read from the Host-owned resource. The operator supplies a new request ID for each distinct action; only a retry of the exact same action may reuse it.</p>
        <dl className="command-inputs">
          <div><dt>Guest control endpoint ID</dt><dd>{guestLifecycleInput?.id ?? "Not available"}</dd></div>
          <div><dt>Expected resource revision</dt><dd>{guestLifecycleInput?.revision ?? "Not available"}</dd></div>
        </dl>
        <label htmlFor="request-id">Request ID</label>
        <input id="request-id" value={requestId} onChange={(event) => setRequestId(event.target.value)} placeholder="operator-start-20260719-001" />
        <div className="command-buttons">
          <button type="button" disabled={commandPending} onClick={() => void submitGuestLifecycle("start")}>{commandPending ? "Requesting…" : "Request Guest start"}</button>
          <button type="button" disabled={commandPending} onClick={() => void submitGuestLifecycle("stop")}>{commandPending ? "Requesting…" : "Request Guest stop"}</button>
          <button type="button" disabled={commandPending} onClick={() => void submitGuestLifecycle("reboot")}>{commandPending ? "Requesting…" : "Request Guest reboot"}</button>
        </div>
        <InterfaceError message={commandInterfaceError} />
        {commandResponse !== undefined ? <ControlResponseCard label="Guest lifecycle response" response={commandResponse} /> : null}
      </section>

      <section aria-labelledby="observability-heading">
        <h2 id="observability-heading">Configure time and observability contracts</h2>
        <p>Host and Guest own separate NTP and OpenTelemetry resources. This Console sends explicit owner identity, node identity, revision, and references. The selected deployment owns concrete NTP/collector endpoints and credentials, so this screen never accepts a server address, URL, header, password, or raw configuration document.</p>
        <h3>Apply NTP time authority</h3>
        <label htmlFor="time-scope">Owner scope</label>
        <select id="time-scope" value={timeScope} onChange={(event) => setTimeScope(event.target.value as RuntimeConsoleOperationalScope)}>
          <option value="host">host</option>
          <option value="guest">guest</option>
        </select>
        <label htmlFor="time-request-id">Time authority request ID</label>
        <input id="time-request-id" value={timeRequestID} onChange={(event) => setTimeRequestID(event.target.value)} placeholder="operator-host-time-001" />
        <label htmlFor="time-authority-id">Time authority ID</label>
        <input id="time-authority-id" value={timeAuthorityID} onChange={(event) => setTimeAuthorityID(event.target.value)} placeholder="host-time-authority" />
        <label htmlFor="time-expected-revision">Expected resource revision</label>
        <input id="time-expected-revision" type="number" min="0" value={timeExpectedRevision} onChange={(event) => setTimeExpectedRevision(event.target.value)} />
        <label htmlFor="time-node-kind">Node kind</label>
        <input id="time-node-kind" value={timeNodeKind} onChange={(event) => setTimeNodeKind(event.target.value)} placeholder="host or guest" />
        <label htmlFor="time-node-id">Node ID</label>
        <input id="time-node-id" value={timeNodeID} onChange={(event) => setTimeNodeID(event.target.value)} placeholder="vitalserver-host" />
        <label htmlFor="time-profile">Authority profile</label>
        <input id="time-profile" value={timeProfile} onChange={(event) => setTimeProfile(event.target.value)} placeholder="enterprise-ntp" />
        <label htmlFor="time-source-profile">Source profile</label>
        <input id="time-source-profile" value={timeSourceProfile} onChange={(event) => setTimeSourceProfile(event.target.value)} placeholder="enterprise-ntp" />
        <label htmlFor="time-source-id">Source ID</label>
        <input id="time-source-id" value={timeSourceID} onChange={(event) => setTimeSourceID(event.target.value)} placeholder="hospital-ntp-primary" />
        <button type="button" disabled={timePending} onClick={() => void applyTimeAuthority()}>{timePending ? "Applying…" : "Apply time authority"}</button>
        <InterfaceError message={timeInterfaceError} />
        {timeResponse !== undefined ? <ControlResponseCard label="Time authority operation response" response={timeResponse} /> : null}

        <h3>Apply OpenTelemetry pipeline</h3>
        <p>The signal set is fixed: <code>logs</code>, <code>metrics</code>, and <code>traces</code>. The allowlist protects export from arbitrary or sensitive attributes.</p>
        <label htmlFor="telemetry-scope">Owner scope</label>
        <select id="telemetry-scope" value={telemetryScope} onChange={(event) => setTelemetryScope(event.target.value as RuntimeConsoleOperationalScope)}>
          <option value="host">host</option>
          <option value="guest">guest</option>
        </select>
        <label htmlFor="telemetry-request-id">Telemetry request ID</label>
        <input id="telemetry-request-id" value={telemetryRequestID} onChange={(event) => setTelemetryRequestID(event.target.value)} placeholder="operator-guest-telemetry-001" />
        <label htmlFor="telemetry-pipeline-id">Pipeline ID</label>
        <input id="telemetry-pipeline-id" value={telemetryPipelineID} onChange={(event) => setTelemetryPipelineID(event.target.value)} placeholder="guest-telemetry" />
        <label htmlFor="telemetry-expected-revision">Expected resource revision</label>
        <input id="telemetry-expected-revision" type="number" min="0" value={telemetryExpectedRevision} onChange={(event) => setTelemetryExpectedRevision(event.target.value)} />
        <label htmlFor="telemetry-node-kind">Node kind</label>
        <input id="telemetry-node-kind" value={telemetryNodeKind} onChange={(event) => setTelemetryNodeKind(event.target.value)} placeholder="guest" />
        <label htmlFor="telemetry-node-id">Node ID</label>
        <input id="telemetry-node-id" value={telemetryNodeID} onChange={(event) => setTelemetryNodeID(event.target.value)} placeholder="vitalserver-guest" />
        <label htmlFor="telemetry-collector-resource-type">Collector reference type</label>
        <input id="telemetry-collector-resource-type" value={telemetryCollectorResourceType} onChange={(event) => setTelemetryCollectorResourceType(event.target.value)} />
        <label htmlFor="telemetry-collector-resource-id">Collector reference ID</label>
        <input id="telemetry-collector-resource-id" value={telemetryCollectorResourceID} onChange={(event) => setTelemetryCollectorResourceID(event.target.value)} placeholder="platform-collector" />
        <label htmlFor="telemetry-allowed-attribute-keys">Allowed attribute keys (comma-separated)</label>
        <input id="telemetry-allowed-attribute-keys" value={telemetryAllowedAttributeKeys} onChange={(event) => setTelemetryAllowedAttributeKeys(event.target.value)} />
        <label htmlFor="telemetry-max-attributes">Maximum attributes</label>
        <input id="telemetry-max-attributes" type="number" min="1" max="32" value={telemetryMaxAttributes} onChange={(event) => setTelemetryMaxAttributes(event.target.value)} />
        <label htmlFor="telemetry-max-value-length">Maximum value length</label>
        <input id="telemetry-max-value-length" type="number" min="1" max="256" value={telemetryMaxValueLength} onChange={(event) => setTelemetryMaxValueLength(event.target.value)} />
        <label htmlFor="telemetry-max-distinct-values">Maximum distinct values per key</label>
        <input id="telemetry-max-distinct-values" type="number" min="1" max="100" value={telemetryMaxDistinctValuesPerKey} onChange={(event) => setTelemetryMaxDistinctValuesPerKey(event.target.value)} />
        <button type="button" disabled={telemetryPending} onClick={() => void applyTelemetryPipeline()}>{telemetryPending ? "Applying…" : "Apply telemetry pipeline"}</button>
        <InterfaceError message={telemetryInterfaceError} />
        {telemetryResponse !== undefined ? <ControlResponseCard label="Telemetry pipeline operation response" response={telemetryResponse} /> : null}
      </section>

		<section aria-labelledby="archive-credentials-heading">
			<h2 id="archive-credentials-heading">Provision external archive credentials</h2>
			<p>The expected credential reference is supplied by the Guest secret-material owner. The values are sent through the OS-authorized local control transport, written only to the private Guest C51 file, then cleared from this console. They are never read back.</p>
			<dl className="command-inputs">
				<div><dt>Credential kind</dt><dd>{archiveCredentialReference?.kind ?? "Not available"}</dd></div>
				<div><dt>Credential ID</dt><dd>{archiveCredentialReference?.id ?? "Not available"}</dd></div>
			</dl>
			<label htmlFor="archive-credential-user-id">User ID</label>
			<input id="archive-credential-user-id" value={credentialUserId} onChange={(event) => setCredentialUserId(event.target.value)} autoComplete="username" />
			<label htmlFor="archive-credential-password">Password</label>
			<input id="archive-credential-password" type="password" value={credentialPassword} onChange={(event) => setCredentialPassword(event.target.value)} autoComplete="current-password" />
			<button type="button" disabled={credentialProvisionPending || archiveCredentialReference === undefined} onClick={() => void provisionArchiveCredentialMaterial()}>{credentialProvisionPending ? "Provisioning…" : "Provision credentials"}</button>
			<InterfaceError message={credentialProvisionInterfaceError} />
			{credentialProvisionResponse !== undefined ? <ControlResponseCard label="Credential provisioning response" response={credentialProvisionResponse} /> : null}
		</section>

      <section aria-labelledby="upstream-heading">
        <h2 id="upstream-heading">Configure upstream topology by explicit references</h2>
        <p>External VitalServer and Redis-adjacent provider details belong to the reviewed Guest deployment configuration, not to this UI. This interface submits only provider, endpoint, and optional credential references. It has no field for remote URLs, headers, passwords, or a raw Guest JSON body.</p>
        <h3>Apply external VitalServer integration</h3>
        <label htmlFor="external-request-id">External integration request ID</label>
        <input id="external-request-id" value={externalRequestID} onChange={(event) => setExternalRequestID(event.target.value)} placeholder="operator-external-upstream-001" />
        <label htmlFor="external-integration-id">Integration ID</label>
        <input id="external-integration-id" value={externalIntegrationID} onChange={(event) => setExternalIntegrationID(event.target.value)} placeholder="external-vitalserver-primary" />
        <label htmlFor="external-expected-revision">Expected integration revision</label>
        <input id="external-expected-revision" type="number" min="0" value={externalExpectedRevision} onChange={(event) => setExternalExpectedRevision(event.target.value)} />
        <label htmlFor="external-provider-kind">Provider kind</label>
        <input id="external-provider-kind" value={externalProviderKind} onChange={(event) => setExternalProviderKind(event.target.value)} placeholder="external-vitalserver" />
        <label htmlFor="external-provider-id">Provider ID</label>
        <input id="external-provider-id" value={externalProviderID} onChange={(event) => setExternalProviderID(event.target.value)} placeholder="external-vitalserver-primary" />
        <label htmlFor="external-provider-capability-revision">Provider capability revision</label>
        <input id="external-provider-capability-revision" type="number" min="1" value={externalProviderCapabilityRevision} onChange={(event) => setExternalProviderCapabilityRevision(event.target.value)} />
        <label htmlFor="external-endpoint-resource-type">Endpoint reference type</label>
        <input id="external-endpoint-resource-type" value={externalEndpointResourceType} onChange={(event) => setExternalEndpointResourceType(event.target.value)} placeholder="external-vitalserver-delivery-configuration" />
        <label htmlFor="external-endpoint-resource-id">Endpoint reference ID</label>
        <input id="external-endpoint-resource-id" value={externalEndpointResourceID} onChange={(event) => setExternalEndpointResourceID(event.target.value)} placeholder="external-vitalserver-primary-delivery" />
        <label htmlFor="external-credential-kind">Optional credential reference kind</label>
        <input id="external-credential-kind" value={externalCredentialKind} onChange={(event) => setExternalCredentialKind(event.target.value)} placeholder="vitalserver-library-credential" />
        <label htmlFor="external-credential-id">Optional credential reference ID</label>
        <input id="external-credential-id" value={externalCredentialID} onChange={(event) => setExternalCredentialID(event.target.value)} placeholder="external-vitalserver-primary-library" />
        <button type="button" disabled={externalPending} onClick={() => void applyExternalUpstream()}>{externalPending ? "Applying…" : "Apply external upstream integration"}</button>
        <InterfaceError message={externalInterfaceError} />
        {externalResponse !== undefined ? <ControlResponseCard label="External upstream operation response" response={externalResponse} /> : null}
        <h3>Apply Runtime topology</h3>
        <p>Current owner-published topology: {topologyOwnerInput === undefined ? "not available" : `${topologyOwnerInput.id} revision ${topologyOwnerInput.revision}`}. Copy its ID and revision only after a fresh read when changing it; use a new ID with revision zero when no topology exists.</p>
        <label htmlFor="topology-request-id">Topology request ID</label>
        <input id="topology-request-id" value={topologyRequestID} onChange={(event) => setTopologyRequestID(event.target.value)} placeholder="operator-topology-001" />
        <label htmlFor="topology-id">Topology ID</label>
        <input id="topology-id" value={topologyID} onChange={(event) => setTopologyID(event.target.value)} placeholder={topologyOwnerInput?.id ?? "primary-topology"} />
        <label htmlFor="topology-expected-revision">Expected topology revision</label>
        <input id="topology-expected-revision" type="number" min="0" value={topologyExpectedRevision} onChange={(event) => setTopologyExpectedRevision(event.target.value)} placeholder={topologyOwnerInput?.revision.toString() ?? "0"} />
        <label htmlFor="topology-profile-kind">Profile kind</label>
        <select id="topology-profile-kind" value={topologyProfileKind} onChange={(event) => setTopologyProfileKind(event.target.value as RuntimeConsoleTopologyProfileKind)}>
          <option value="external-upstream">external-upstream</option>
          <option value="bundled-upstream">bundled-upstream</option>
        </select>
        <label htmlFor="topology-endpoint-resource-type">Endpoint reference type</label>
        <input id="topology-endpoint-resource-type" value={topologyEndpointResourceType} onChange={(event) => setTopologyEndpointResourceType(event.target.value)} />
        <label htmlFor="topology-endpoint-resource-id">Endpoint reference ID</label>
        <input id="topology-endpoint-resource-id" value={topologyEndpointResourceID} onChange={(event) => setTopologyEndpointResourceID(event.target.value)} placeholder="external-vitalserver-primary" />
        <label htmlFor="topology-credential-kind">Optional credential reference kind</label>
        <input id="topology-credential-kind" value={topologyCredentialKind} onChange={(event) => setTopologyCredentialKind(event.target.value)} />
        <label htmlFor="topology-credential-id">Optional credential reference ID</label>
        <input id="topology-credential-id" value={topologyCredentialID} onChange={(event) => setTopologyCredentialID(event.target.value)} />
        <button type="button" disabled={topologyPending} onClick={() => void applyRuntimeTopology()}>{topologyPending ? "Applying…" : "Apply Runtime topology"}</button>
        <InterfaceError message={topologyInterfaceError} />
        {topologyResponse !== undefined ? <ControlResponseCard label="Runtime topology operation response" response={topologyResponse} /> : null}
      </section>

      <section aria-labelledby="lab-heading">
        <h2 id="lab-heading">Operate a Lab-owned virtual recorder session</h2>
        <p>Lab is a Guest-owned aggregate. Create uses an explicit new session ID and revision zero. The Guest applies the visible <code>LAB-</code> name prefix to its own session, bed, and virtual-recorder names; the operator supplies only the base name. Start, stop, visibility, detach, and delete always use the resource ID and revision returned by the latest owner read.</p>
        <h3>Create prepared session</h3>
        <label htmlFor="lab-create-request-id">Create request ID</label>
        <input id="lab-create-request-id" value={labCreateRequestID} onChange={(event) => setLabCreateRequestID(event.target.value)} placeholder="operator-lab-create-001" />
        <label htmlFor="lab-session-id">New session ID</label>
        <input id="lab-session-id" value={labSessionID} onChange={(event) => setLabSessionID(event.target.value)} placeholder="lab-session-baseline-001" />
        <label htmlFor="lab-name">Base name</label>
        <input id="lab-name" value={labName} onChange={(event) => setLabName(event.target.value)} placeholder="baseline-monitoring" />
        <label htmlFor="lab-scenario">Scenario ID</label>
        <input id="lab-scenario" value={labScenario} onChange={(event) => setLabScenario(event.target.value)} placeholder="baseline-monitoring" />
        <label htmlFor="lab-recorder-count">Virtual recorder count</label>
        <input id="lab-recorder-count" type="number" min="1" max="64" value={labRecorderCount} onChange={(event) => setLabRecorderCount(event.target.value)} />
        <button type="button" disabled={labCreatePending} onClick={() => void createLabSession()}>{labCreatePending ? "Creating…" : "Create prepared Lab session"}</button>
        {labCreateResponse !== undefined ? <ControlResponseCard label="Lab create response" response={labCreateResponse} /> : null}
        <h3>Request selected resource action</h3>
        <p>Refresh before every action. A response from this request is a durable Guest operation result, not an inferred VitalServer, packet-delivery, archive-export, or browser-monitoring success.</p>
        <label htmlFor="lab-resource">Lab-owned resource</label>
        <select id="lab-resource" value={selectedLabResourceKey} onChange={(event) => setSelectedLabResourceKey(event.target.value)}>
          <option value="">Select an owner-published Lab resource</option>
          {labResourceOptions.map((resource) => <option key={resource.selectionKey} value={resource.selectionKey}>{resource.resourceType} · {resource.name} · {resource.id} · revision {resource.revision} · {resource.state}</option>)}
        </select>
        <label htmlFor="lab-resource-action">Action</label>
        <select id="lab-resource-action" value={labResourceAction} disabled={selectedLabResource === undefined} onChange={(event) => setLabResourceAction(event.target.value as RuntimeConsoleLabResourceAction)}>
          {selectedLabResourceActions.map((action) => <option key={action} value={action}>{action}</option>)}
        </select>
        {labResourceAction === "delete" && selectedLabResource !== undefined ? <p>Delete cascade: <code>{selectedLabResource.resourceType === "lab-session" ? "owned-resources" : "none"}</code>. This is the only cascade allowed by the Guest Lab contract.</p> : null}
        <label htmlFor="lab-resource-request-id">Action request ID</label>
        <input id="lab-resource-request-id" value={labResourceRequestID} onChange={(event) => setLabResourceRequestID(event.target.value)} placeholder="operator-lab-start-001" />
        <button type="button" disabled={labResourcePending || selectedLabResource === undefined} onClick={() => void executeLabResourceCommand()}>{labResourcePending ? "Requesting…" : "Request Lab resource action"}</button>
        <InterfaceError message={labInterfaceError} />
        {labResourceResponse !== undefined ? <ControlResponseCard label="Lab resource action response" response={labResourceResponse} /> : null}
        <h3>Export one stopped virtual recorder artifact</h3>
        <p>Stopping a recorder does not itself create, upload, or index a <code>.vital</code> artifact. For a recorder whose Guest-owned terminal policy is <code>no-export</code>, this command carries the exact stopped recorder revision and finalized Recorder Gateway receipt from the latest Lab read together with the Archive-owned provider reference. A recorder with <code>export-on-stop</code> already has a separate Archive intent and is not manually exported here.</p>
        <dl className="command-inputs">
          <div><dt>Selected manual-export recorder</dt><dd>{selectedLabRecorderArchiveCandidate?.id ?? "Not available"}</dd></div>
          <div><dt>Expected recorder revision</dt><dd>{selectedLabRecorderArchiveCandidate?.revision ?? "Not available"}</dd></div>
          <div><dt>Cold-path finalization receipt</dt><dd>{selectedLabRecorderArchiveCandidate?.finalizationReceiptId ?? "Not available"}</dd></div>
          <div><dt>Archive provider</dt><dd>{archiveExportProvider === undefined ? "Not available" : `${archiveExportProvider.kind} · ${archiveExportProvider.id} · capability ${archiveExportProvider.capabilityRevision}`}</dd></div>
        </dl>
        {selectedLabResource?.resourceType === "virtual-recorder" && selectedLabRecorderArchiveCandidate === undefined ? <p>Select a stopped virtual recorder with the Guest-owned <code>no-export</code> policy. If it has <code>export-on-stop</code>, inspect its terminal Archive intent instead of issuing a second export.</p> : null}
        <label htmlFor="archive-export-request-id">Archive export request ID</label>
        <input id="archive-export-request-id" value={archiveExportRequestID} onChange={(event) => setArchiveExportRequestID(event.target.value)} placeholder="operator-archive-export-001" />
        <button type="button" disabled={archiveExportPending || selectedLabRecorderArchiveCandidate === undefined || archiveExportProvider === undefined} onClick={() => void executeManualArtifactExport()}>{archiveExportPending ? "Requesting export…" : "Export selected stopped recorder"}</button>
        <InterfaceError message={archiveExportInterfaceError} />
        {archiveExportResponse !== undefined ? <ControlResponseCard label="Artifact export operation response" response={archiveExportResponse} /> : null}
      </section>

      <section aria-labelledby="updates-heading">
        <h2 id="updates-heading">Import and apply a signed product update</h2>
        <p>Host imports a selected offline release-bundle directory atomically. Import only records immutable bytes and the declared C25 envelope; it does not verify the release trust signature or claim update success. Applying the imported ID enters the existing Host-owned C27/C29 update workflow, which performs trust verification and emits explicit operation state.</p>
        <label htmlFor="update-import-request-id">Import request ID</label>
        <input id="update-import-request-id" value={updateImportRequestID} onChange={(event) => setUpdateImportRequestID(event.target.value)} placeholder="operator-import-20260720-001" />
        <label htmlFor="update-bundle-source-directory">Host-local release bundle directory</label>
        <div className="command-buttons">
          <input id="update-bundle-source-directory" value={updateBundleSourceDirectory} onChange={(event) => setUpdateBundleSourceDirectory(event.target.value)} placeholder="/absolute/path/to/release-bundle" />
          <button type="button" onClick={() => void selectUpdateBundleDirectory()}>Choose directory</button>
        </div>
        <button type="button" disabled={updateImportPending} onClick={() => void importUpdateBundle()}>{updateImportPending ? "Importing…" : "Import update bundle"}</button>
        {updateImportResponse !== undefined ? <ControlResponseCard label="Update bundle import response" response={updateImportResponse} /> : null}
        <label htmlFor="update-bundle-id">Imported bundle ID</label>
        <input id="update-bundle-id" value={updateBundleID} onChange={(event) => setUpdateBundleID(event.target.value)} placeholder="release-bootstrap-020" />
        <dl className="command-inputs">
          <div><dt>Installation ID</dt><dd>{installationInput?.id ?? "Not available"}</dd></div>
          <div><dt>Expected installation revision</dt><dd>{installationInput?.revision ?? "Not available"}</dd></div>
        </dl>
        <label htmlFor="update-apply-request-id">Update request ID</label>
        <input id="update-apply-request-id" value={updateApplyRequestID} onChange={(event) => setUpdateApplyRequestID(event.target.value)} placeholder="operator-update-20260720-001" />
        <button type="button" disabled={updateApplyPending || installationInput === undefined} onClick={() => void applyUpdateBundle()}>{updateApplyPending ? "Requesting update…" : "Apply imported update bundle"}</button>
        <InterfaceError message={updateInterfaceError} />
        {updateApplyResponse !== undefined ? <ControlResponseCard label="Update workflow response" response={updateApplyResponse} /> : null}
      </section>
    </main>
  );
}

function OwnerReadCard({ label, view, refresh }: { readonly label: string; readonly view: ReadView; readonly refresh: () => void }): ReactElement {
  return (
    <article className="resource-card">
      <div className="card-heading"><h3>{label}</h3><button type="button" disabled={view.pending} onClick={refresh}>{view.pending ? "Reading…" : "Refresh"}</button></div>
      <InterfaceError message={view.interfaceError} />
      {view.response !== undefined ? <ControlResponseCard label={label} response={view.response} /> : null}
    </article>
  );
}

function ControlResponseCard({ label, response }: { readonly label: string; readonly response: RuntimeConsoleControlResponse }): ReactElement {
  return (
    <div className="response-card">
      <p><strong>{label}</strong> · HTTP {response.httpStatus}</p>
      <pre>{JSON.stringify(response.document, null, 2)}</pre>
    </div>
  );
}

function InterfaceError({ message }: { readonly message?: string }): ReactElement | null {
  return message === undefined ? null : <p className="interface-error">Interface transport error: {message}</p>;
}

function ownerSuppliedGuestLifecycleInput(response: RuntimeConsoleControlResponse | undefined): { readonly id: string; readonly revision: number } | undefined {
  if (response === undefined || !isRecord(response.document) || response.document.state !== "available" || !isRecord(response.document.value)) {
    return undefined;
  }
  const id = response.document.value.id;
  const revision = response.document.value.resourceRevision;
  if (typeof id !== "string" || id === "" || typeof revision !== "number" || !Number.isInteger(revision) || revision < 0) {
    return undefined;
  }
  return { id, revision };
}

function ownerSuppliedArchiveCredentialReference(response: RuntimeConsoleControlResponse | undefined): { readonly kind: string; readonly id: string } | undefined {
	if (response === undefined || !isRecord(response.document) || !isRecord(response.document.credentialReference)) {
		return undefined;
	}
	const kind = response.document.credentialReference.kind;
	const id = response.document.credentialReference.id;
	if (typeof kind !== "string" || kind === "" || typeof id !== "string" || id === "") {
		return undefined;
	}
	return { kind, id };
}

function ownerSuppliedArchiveExportProvider(response: RuntimeConsoleControlResponse | undefined): { readonly kind: string; readonly id: string; readonly capabilityRevision: number } | undefined {
  if (response === undefined || !isRecord(response.document) || response.document.state !== "available" || !isRecord(response.document.value) || !isRecord(response.document.value.provider)) {
    return undefined;
  }
  const kind = response.document.value.provider.kind;
  const id = response.document.value.provider.id;
  const capabilityRevision = response.document.value.provider.capabilityRevision;
  if (typeof kind !== "string" || kind === "" || typeof id !== "string" || id === "" || typeof capabilityRevision !== "number" || !Number.isInteger(capabilityRevision) || capabilityRevision < 1) {
    return undefined;
  }
  return { kind, id, capabilityRevision };
}

function ownerSuppliedInstallationInput(response: RuntimeConsoleControlResponse | undefined): { readonly id: string; readonly revision: number } | undefined {
  if (response === undefined || !isRecord(response.document) || response.document.state !== "available" || !isRecord(response.document.value)) {
    return undefined;
  }
  const id = response.document.value.id;
  const revision = response.document.value.resourceRevision;
  if (typeof id !== "string" || id === "" || typeof revision !== "number" || !Number.isInteger(revision) || revision < 1) {
    return undefined;
  }
  return { id, revision };
}

function ownerSuppliedImportedUpdateBundleID(response: RuntimeConsoleControlResponse): string | undefined {
  if (!isRecord(response.document) || !isRecord(response.document.bundle)) {
    return undefined;
  }
  const id = response.document.bundle.id;
  const state = response.document.bundle.state;
  return typeof id === "string" && id !== "" && state === "declared" ? id : undefined;
}

function ownerSuppliedLabResourceOptions(
  sessions: RuntimeConsoleControlResponse | undefined,
  beds: RuntimeConsoleControlResponse | undefined,
  recorders: RuntimeConsoleControlResponse | undefined,
): readonly LabResourceOption[] {
  return [
    ...ownerSuppliedLabResourceOptionsFor("lab-session", "state", sessions),
    ...ownerSuppliedLabResourceOptionsFor("lab-bed", "assignmentState", beds),
    ...ownerSuppliedLabResourceOptionsFor("virtual-recorder", "executionState", recorders),
  ];
}

function ownerSuppliedManualArchiveExportCandidate(
  selectedResourceKey: string,
  response: RuntimeConsoleControlResponse | undefined,
): { readonly id: string; readonly revision: number; readonly finalizationReceiptId: string } | undefined {
  if (!selectedResourceKey.startsWith("virtual-recorder|") || response === undefined || !isRecord(response.document) || response.document.state !== "available" || !Array.isArray(response.document.value)) {
    return undefined;
  }
  const selectedID = selectedResourceKey.slice("virtual-recorder|".length);
  for (const value of response.document.value) {
    if (!isRecord(value) || value.id !== selectedID || value.executionState !== "stopped" || value.terminalArchivePolicy !== "no-export") {
      continue;
    }
    const revision = value.resourceRevision;
    const finalizationReceiptId = value.recorderGatewayFinalizationReceiptId;
    if (typeof revision !== "number" || !Number.isInteger(revision) || revision < 1 || typeof finalizationReceiptId !== "string" || finalizationReceiptId === "") {
      return undefined;
    }
    return { id: selectedID, revision, finalizationReceiptId };
  }
  return undefined;
}

function ownerSuppliedTopologyInput(response: RuntimeConsoleControlResponse | undefined): { readonly id: string; readonly revision: number } | undefined {
  if (response === undefined || !isRecord(response.document) || response.document.state !== "available" || !isRecord(response.document.value)) {
    return undefined;
  }
  const id = response.document.value.id;
  const revision = response.document.value.resourceRevision;
  if (typeof id !== "string" || id === "" || typeof revision !== "number" || !Number.isInteger(revision) || revision < 1) {
    return undefined;
  }
  return { id, revision };
}

function optionalReference(kind: string, id: string, missingPairMessage: string): { readonly kind: string; readonly id: string } | undefined | Error {
  if (kind === "" && id === "") {
    return undefined;
  }
  if (kind === "" || id === "") {
    return new Error(missingPairMessage);
  }
  return { kind, id };
}

function ownerSuppliedLabResourceOptionsFor(
  resourceType: LabResourceOption["resourceType"],
  stateKey: string,
  response: RuntimeConsoleControlResponse | undefined,
): readonly LabResourceOption[] {
  if (response === undefined || !isRecord(response.document) || response.document.state !== "available" || !Array.isArray(response.document.value)) {
    return [];
  }
  const resources: LabResourceOption[] = [];
  for (const value of response.document.value) {
    if (!isRecord(value)) {
      continue;
    }
    const id = value.id;
    const name = value.name;
    const revision = value.resourceRevision;
    const state = value[stateKey];
    if (typeof id !== "string" || id === "" || typeof name !== "string" || name === "" || typeof revision !== "number" || !Number.isInteger(revision) || revision < 1 || typeof state !== "string" || state === "") {
      continue;
    }
    resources.push({ selectionKey: `${resourceType}|${id}`, resourceType, id, revision, name, state });
  }
  return resources;
}

function supportedLabActions(resourceType: LabResourceOption["resourceType"]): readonly RuntimeConsoleLabResourceAction[] {
  switch (resourceType) {
    case "lab-session":
      return ["start", "stop", "delete"];
    case "lab-bed":
      return ["hide", "unhide", "delete"];
    case "virtual-recorder":
      return ["start", "stop", "hide", "unhide", "detach", "delete"];
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function interfaceErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "unknown interface transport failure";
}

const rootElement = document.getElementById("runtime-console-root");
if (rootElement === null) {
  throw new Error("runtime console root element is missing");
}

createRoot(rootElement).render(<RuntimeConsoleApplication transport={window.vitalServerRuntimeConsole} />);
