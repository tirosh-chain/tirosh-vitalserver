import type {
  RuntimeControlGateway,
  RuntimeEventQuery
} from "@/console/runtimeControlGateway";
import {
  runtimeEventTypeValues,
  type RuntimeEventTypeValue
} from "@/domain/runtime-control/contracts/runtimeEventTypes";
import {
  RuntimeControlAPIError,
  RuntimeControlContractError,
  RuntimeControlNetworkError,
  RuntimeControlValidationError
} from "@/domain/runtime-control/errors/runtimeControlError";
import type {
  ControlCapabilities,
  PlatformCapabilities,
  RuntimeCapabilities,
  RuntimeApplyProductSettingsRequest,
  RuntimeApplyPlatformSettingsRequest,
  RuntimeAdminPasswordRequest,
  RuntimeBackup,
  RuntimeBackupRequest,
  RuntimeCommandResponse,
  RuntimeExportLogsRequest,
  RuntimeEventHistory,
  RuntimeGuestControlServiceOperation,
  RuntimeGuestControlStackStatus,
  RuntimeGuestServiceResource,
  RuntimeGuestServiceControlRequest,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabBedList,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabRecorderList,
  RuntimeLabRecorderResponse,
  RuntimeLabScenarioList,
  RuntimeLabSessionCreateRequest,
  RuntimeLabSessionResponse,
  RuntimeLabSessionList,
  RuntimeLabVitalFileList,
  RuntimeLabVitalFileUploadRequest,
  RuntimeLabVitalFileUploadResponse,
  RuntimeLabVitalFileReplayRequest,
  RuntimeLogExportResult,
  RuntimeLogTextRequest,
  RuntimeLogTextResponse,
  PlatformOperationState,
  PlatformWorkflowOperation,
  PlatformWorkflowResource,
  RuntimeRedisRelayStatusReadResult,
  RuntimeRedisRelaySettingsRead,
  RuntimeRedisRelaySettingsApplyRequest,
  RuntimeVitalDBObservationSnapshot,
  RuntimeVitalRecorderActivityWindow,
  RuntimeVitalRecorderActivityWindowQuery,
  RuntimeReleaseInfo,
  RuntimeInstallInfo,
  RuntimeProductSettingsRead,
  RuntimePlatformSettingsRead,
  RuntimeProviderCommandResponse,
  PlatformState,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest,
  RuntimeUpdateBundleSummaryResponse,
  VitalDBBedVisibilityRequest,
  VitalDBBeds,
  VitalDBRecorderVisibilityRequest,
  VitalDBRecorders,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeBackupSchema,
  platformCapabilitiesSchema,
  runtimeCapabilitiesSchema,
  runtimeCommandResponseSchema,
  runtimeEventHistorySchema,
  runtimeGuestControlStackStatusSchema,
  runtimeGuestControlServiceOperationSchema,
  runtimeGuestServiceResourceSchema,
  runtimeLabBedListSchema,
  runtimeLabRecorderListSchema,
  runtimeLabRecorderResponseSchema,
  runtimeLabScenarioListSchema,
  runtimeLabSessionResponseSchema,
  runtimeLabSessionListSchema,
  runtimeLabVitalFileListSchema,
  runtimeLabVitalFileUploadResponseSchema,
  runtimeLogExportResultSchema,
  runtimeLogTextResponseSchema,
  platformOperationStateSchema,
  platformWorkflowOperationSchema,
  platformWorkflowResourceSchema,
  runtimeRedisRelayStatusReadResultSchema,
  runtimeRedisRelaySettingsReadSchema,
  runtimeVitalDBObservationSnapshotSchema,
  recorderActivityWindowSchema,
  runtimeReleaseInfoSchema,
  runtimeInstallInfoSchema,
  runtimeProductSettingsReadSchema,
  runtimePlatformSettingsReadSchema,
  runtimeProviderCommandResponseSchema,
  platformStateSchema,
  runtimeUpdateBundleSummaryResponseSchema,
  vitalDBBedsSchema,
  vitalDBRecordersSchema,
  vitalDBRelationshipsSchema
} from "@/domain/runtime-control/contracts/schemas/runtimeControlSchemas";
import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";
import type { ZodType } from "zod";

type RuntimeControlRequestQuery = Record<string, string | number>;

export type RuntimeControlApiClientOptions = {
  baseURL?: string;
  token?: string;
  useBrowserSession?: boolean;
  fetchImpl?: typeof fetch;
};

export class RuntimeControlApiClient implements RuntimeControlGateway {
  private readonly baseURL: string;
  private readonly token: string;
  private readonly useBrowserSession: boolean;
  private readonly fetchImpl: typeof fetch;
  private browserSessionBootstrap: Promise<void> | undefined;

  constructor(options: RuntimeControlApiClientOptions = {}) {
    this.baseURL = trimTrailingSlash(
      options.baseURL ?? DEFAULT_APP_SETTINGS.runtimeControl.apiBaseURL
    );
    this.token =
      options.token ?? DEFAULT_APP_SETTINGS.runtimeControl.token;
    this.useBrowserSession =
      options.useBrowserSession ?? (this.token === "" && this.baseURL === "");
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  getPlatformCapabilities(): Promise<PlatformCapabilities> {
    return this.get("/platform/capabilities", platformCapabilitiesSchema);
  }

  getRuntimeCapabilities(): Promise<RuntimeCapabilities> {
    return this.get("/runtime/capabilities", runtimeCapabilitiesSchema);
  }

  async getCapabilities(): Promise<ControlCapabilities> {
    const [platform, runtime] = await Promise.all([
      this.getPlatformCapabilities(),
      this.getRuntimeCapabilities()
    ]);
    const available = new Set(runtime.capabilities);
    return {
      ...platform,
      canControlGuestServices:
        available.has("services:start") &&
        available.has("services:stop") &&
        available.has("services:restart"),
      canUseLab: available.has("lab:scenarios"),
      canListLabSessions: available.has("lab:sessions:list"),
      canControlLabRecorders:
        available.has("lab:recorders:start") &&
        available.has("lab:recorders:stop"),
      canApplyRuntimeProductSettings: available.has("settings:apply"),
      canApplyRuntimeAdminPassword: available.has("admin-password:apply"),
      canApplyRuntimeRedisRelaySettings:
        available.has("redis-relay:settings:apply"),
      canRepairRuntimeDatastore:
        available.has("maintenance:datastore-repair:create")
    };
  }

  getPlatformState(): Promise<PlatformState> {
    return this.get("/platform", platformStateSchema);
  }

  getReleaseInfo(): Promise<RuntimeReleaseInfo> {
    return this.get("/platform/release", runtimeReleaseInfoSchema);
  }

  getInstallInfo(): Promise<RuntimeInstallInfo> {
    return this.get("/platform/installation", runtimeInstallInfoSchema);
  }

  getRedisRelayStatus(): Promise<RuntimeRedisRelayStatusReadResult> {
    return this.get(
      "/runtime/redis-relay/status",
      runtimeRedisRelayStatusReadResultSchema
    );
  }

  getRuntimeRedisRelaySettings(): Promise<RuntimeRedisRelaySettingsRead> {
    return this.get(
      "/runtime/redis-relay/settings",
      runtimeRedisRelaySettingsReadSchema
    );
  }

  applyRuntimeRedisRelaySettings(
    request: RuntimeRedisRelaySettingsApplyRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.put(
      "/runtime/redis-relay/settings",
      request,
      runtimeGuestControlServiceOperationSchema
    );
  }

  getLatestVitalDBObservation(): Promise<RuntimeVitalDBObservationSnapshot> {
    return this.get(
      "/runtime/vitaldb/observations/latest",
      runtimeVitalDBObservationSnapshotSchema
    );
  }

  getOperationState(): Promise<PlatformOperationState> {
    return this.get("/platform/operations", platformOperationStateSchema);
  }

  getPlatformWorkflow(): Promise<PlatformWorkflowResource> {
    return this.get("/platform/workflows/current", platformWorkflowResourceSchema);
  }

  getRuntimeProductSettings(): Promise<RuntimeProductSettingsRead> {
    return this.get("/runtime/settings", runtimeProductSettingsReadSchema);
  }

  getRuntimePlatformSettings(): Promise<RuntimePlatformSettingsRead> {
    return this.get("/platform/settings", runtimePlatformSettingsReadSchema);
  }

  getLabScenarios(): Promise<RuntimeLabScenarioList> {
    return this.get("/runtime/lab/scenarios", runtimeLabScenarioListSchema);
  }

  getLabBeds(): Promise<RuntimeLabBedList> {
    return this.get("/runtime/lab/beds", runtimeLabBedListSchema);
  }

  getLabRecorders(): Promise<RuntimeLabRecorderList> {
    return this.get("/runtime/lab/recorders", runtimeLabRecorderListSchema);
  }

  createLabBeds(request: RuntimeLabBedCreateRequest): Promise<RuntimeLabBedList> {
    return this.post("/runtime/lab/beds/create", request, runtimeLabBedListSchema);
  }

  deleteLabBeds(request: RuntimeLabBedDeleteRequest): Promise<RuntimeLabBedList> {
    return this.post("/runtime/lab/beds/delete", request, runtimeLabBedListSchema);
  }

  resetLabBeds(): Promise<RuntimeLabBedList> {
    return this.post("/runtime/lab/beds/reset", undefined, runtimeLabBedListSchema);
  }

  createLabRecorders(
    request: RuntimeLabRecorderCreateRequest
  ): Promise<RuntimeLabRecorderList> {
    return this.post("/runtime/lab/recorders/create", request, runtimeLabRecorderListSchema);
  }

  deleteLabRecorders(
    request: RuntimeLabRecorderDeleteRequest
  ): Promise<RuntimeLabRecorderList> {
    return this.post("/runtime/lab/recorders/delete", request, runtimeLabRecorderListSchema);
  }

  resetLabRecorders(): Promise<RuntimeLabRecorderList> {
    return this.post("/runtime/lab/recorders/reset", undefined, runtimeLabRecorderListSchema);
  }

  getLabSessions(): Promise<RuntimeLabSessionList> {
    return this.get("/runtime/lab/sessions", runtimeLabSessionListSchema);
  }

  createLabSession(
    request: RuntimeLabSessionCreateRequest
  ): Promise<RuntimeLabSessionResponse> {
    return this.post("/runtime/lab/sessions", request, runtimeLabSessionResponseSchema);
  }

  getLabSession(sessionId: string): Promise<RuntimeLabSessionResponse> {
    return this.get(
      labSessionPath(sessionId),
      runtimeLabSessionResponseSchema
    );
  }

  startLabSession(sessionId: string): Promise<RuntimeLabSessionResponse> {
    return this.post(
      `${labSessionPath(sessionId)}/start`,
      undefined,
      runtimeLabSessionResponseSchema
    );
  }

  stopLabSession(sessionId: string): Promise<RuntimeLabSessionResponse> {
    return this.post(
      `${labSessionPath(sessionId)}/stop`,
      undefined,
      runtimeLabSessionResponseSchema
    );
  }

  finishLabSession(sessionId: string): Promise<RuntimeLabSessionResponse> {
    return this.post(
      `${labSessionPath(sessionId)}/finish`,
      undefined,
      runtimeLabSessionResponseSchema
    );
  }

  startLabRecorder(
    sessionId: string,
    recorderId: string
  ): Promise<RuntimeLabRecorderResponse> {
    return this.post(
      `${labSessionPath(sessionId)}/recorders/${encodeURIComponent(recorderId)}/start`,
      undefined,
      runtimeLabRecorderResponseSchema
    );
  }

  stopLabRecorder(
    sessionId: string,
    recorderId: string
  ): Promise<RuntimeLabRecorderResponse> {
    return this.post(
      `${labSessionPath(sessionId)}/recorders/${encodeURIComponent(recorderId)}/stop`,
      undefined,
      runtimeLabRecorderResponseSchema
    );
  }

  getLabVitalFiles(): Promise<RuntimeLabVitalFileList> {
    return this.get("/runtime/lab/vital-files", runtimeLabVitalFileListSchema);
  }

  async uploadLabVitalFiles(
    request: RuntimeLabVitalFileUploadRequest
  ): Promise<RuntimeLabVitalFileUploadResponse> {
    const form = new FormData();
    request.files.forEach((file) => form.append("files", file, file.name));
    const response = await this.request("/runtime/lab/vital-files/upload", {
      method: "POST",
      headers: this.headers(),
      body: form
    });
    if (!response.ok) {
      const responseBody = await response.text();
      throw new RuntimeControlAPIError(
        `Runtime Control API request failed: ${response.status}`,
        response.status,
        responseBody
      );
    }
    return this.parse(
      "/runtime/lab/vital-files/upload",
      runtimeLabVitalFileUploadResponseSchema,
      await response.json()
    );
  }

  replayLabVitalFile(
    request: RuntimeLabVitalFileReplayRequest
  ): Promise<RuntimeLabSessionResponse> {
    return this.post(
      "/runtime/lab/vital-files/replay",
      request,
      runtimeLabSessionResponseSchema
    );
  }

  getRuntimeStack(): Promise<RuntimeGuestControlStackStatus> {
    return this.get(
      "/runtime/stack",
      runtimeGuestControlStackStatusSchema
    );
  }

  getGuestServiceResource(service: string): Promise<RuntimeGuestServiceResource> {
    return this.get(
      `/runtime/services/${encodeURIComponent(service)}/resource`,
      runtimeGuestServiceResourceSchema
    );
  }

  startGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      `/runtime/services/${encodeURIComponent(request.service)}/start`,
      undefined,
      runtimeGuestControlServiceOperationSchema
    );
  }

  stopGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      `/runtime/services/${encodeURIComponent(request.service)}/stop`,
      undefined,
      runtimeGuestControlServiceOperationSchema
    );
  }

  restartGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      `/runtime/services/${encodeURIComponent(request.service)}/restart`,
      undefined,
      runtimeGuestControlServiceOperationSchema
    );
  }

  applyRuntimeProductSettings(
    request: RuntimeApplyProductSettingsRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.put(
      "/runtime/settings",
      request,
      runtimeGuestControlServiceOperationSchema
    );
  }

  applyRuntimePlatformSettings(
    request: RuntimeApplyPlatformSettingsRequest
  ): Promise<RuntimeCommandResponse> {
    return this.put("/platform/settings", request, runtimeCommandResponseSchema);
  }

  applyRuntimeAdminPassword(
    request: RuntimeAdminPasswordRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      "/runtime/admin-password",
      request,
      runtimeGuestControlServiceOperationSchema
    );
  }

  uninstallRuntime(
    request: RuntimeUninstallRequest
  ): Promise<PlatformWorkflowOperation> {
    return this.post(
      "/platform/uninstall",
      request,
      platformWorkflowOperationSchema
    );
  }

  async getRuntimeEvents(
    query: RuntimeEventQuery = {}
  ): Promise<RuntimeEventHistory> {
    return await this.get(
      "/runtime/events",
      runtimeEventHistorySchema,
      runtimeEventQueryParameters(query)
    );
  }

  getRecorders(): Promise<VitalDBRecorders> {
    return this.get("/runtime/vitaldb/recorders", vitalDBRecordersSchema);
  }

  getRecorderActivity(
    query: RuntimeVitalRecorderActivityWindowQuery
  ): Promise<RuntimeVitalRecorderActivityWindow> {
    const pageIndex = query.pageIndex;
    return this.get(
      `/runtime/vitaldb/recorders/${encodeURIComponent(query.vrcode)}/activity`,
      recorderActivityWindowSchema,
      {
        bucketSeconds: query.bucketSeconds,
        period: query.period,
        ...(pageIndex === undefined ? {} : { pageIndex })
      }
    );
  }

  hideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/runtime/vitaldb/recorders/hide", request, vitalDBRecordersSchema);
  }

  unhideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/runtime/vitaldb/recorders/unhide", request, vitalDBRecordersSchema);
  }

  deleteRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/runtime/vitaldb/recorders/delete", request, vitalDBRecordersSchema);
  }

  getBeds(): Promise<VitalDBBeds> {
    return this.get("/runtime/vitaldb/beds", vitalDBBedsSchema);
  }

  hideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBBeds> {
    return this.post("/runtime/vitaldb/beds/hide", request, vitalDBBedsSchema);
  }

  unhideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBBeds> {
    return this.post("/runtime/vitaldb/beds/unhide", request, vitalDBBedsSchema);
  }

  deleteBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBBeds> {
    return this.post("/runtime/vitaldb/beds/delete", request, vitalDBBedsSchema);
  }

  getRelationships(): Promise<VitalDBRelationships> {
    return this.get("/runtime/vitaldb/relationships", vitalDBRelationshipsSchema);
  }

  readLogs(request: RuntimeLogTextRequest): Promise<RuntimeLogTextResponse> {
    return this.post("/platform/logs/read", request, runtimeLogTextResponseSchema);
  }

  exportLogs(
    request: RuntimeExportLogsRequest
  ): Promise<RuntimeLogExportResult> {
    return this.post(
      "/platform/logs/export",
      request,
      runtimeLogExportResultSchema
    );
  }

  summarizeUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeUpdateBundleSummaryResponse> {
    return this.post(
      "/platform/update-bundles/summary",
      request,
      runtimeUpdateBundleSummaryResponseSchema
    );
  }

  verifyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<PlatformWorkflowOperation> {
    return this.post(
      "/platform/update-bundles/verify",
      request,
      platformWorkflowOperationSchema
    );
  }

  applyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<PlatformWorkflowOperation> {
    return this.post(
      "/platform/update-bundles/apply",
      request,
      platformWorkflowOperationSchema
    );
  }

  rollbackRelease(): Promise<PlatformWorkflowOperation> {
    return this.post(
      "/platform/releases/rollback",
      undefined,
      platformWorkflowOperationSchema
    );
  }

  createPlatformSupportExport(): Promise<PlatformWorkflowOperation> {
    return this.post(
      "/platform/support-exports",
      undefined,
      platformWorkflowOperationSchema
    );
  }

  listHostBackups(): Promise<RuntimeBackup[]> {
    return this.get("/platform/backups", runtimeBackupSchema.array());
  }

  listRedisBackups(): Promise<RuntimeBackup[]> {
    return this.get("/platform/backups/redis", runtimeBackupSchema.array());
  }

  listRuntimeDataBackups(): Promise<RuntimeBackup[]> {
    return this.get("/platform/backups/runtime-data", runtimeBackupSchema.array());
  }

  rollbackBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse> {
    return this.post(
      "/platform/backups/rollback",
      request,
      runtimeCommandResponseSchema
    );
  }

  deleteHostBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete("/platform/backups", request, runtimeCommandResponseSchema);
  }

  deleteUpdateBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete(
      "/platform/backups/update",
      request,
      runtimeCommandResponseSchema
    );
  }

  deleteRuntimeDataBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete(
      "/platform/backups/runtime-data",
      request,
      runtimeCommandResponseSchema
    );
  }

  restoreRedisBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/platform/backups/redis/restore",
      request,
      runtimeCommandResponseSchema
    );
  }

  restoreRuntimeDataBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/platform/backups/runtime-data/restore",
      request,
      runtimeCommandResponseSchema
    );
  }

  createRedisBackup(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/platform/backups/redis",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  createRuntimeDataBackup(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/platform/backups/runtime-data",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  restartRuntimeProvider(): Promise<RuntimeProviderCommandResponse> {
    return this.postRuntimeProviderCommand("/platform/runtime-provider/restart");
  }

  repairDatastore(): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      "/runtime/maintenance/datastore/repair",
      undefined,
      runtimeGuestControlServiceOperationSchema
    );
  }

  private async get<T>(
    path: string,
    schema: ZodType<T>,
    query: RuntimeControlRequestQuery = {}
  ): Promise<T> {
    const response = await this.request(
      path,
      {
        method: "GET",
        headers: this.headers()
      },
      query
    );

    if (!response.ok) {
      const body = await response.text();
      throw new RuntimeControlAPIError(
        `Runtime Control API request failed: ${response.status}`,
        response.status,
        body
      );
    }

    return this.parse(path, schema, await response.json());
  }

  private async put<T>(
    path: string,
    body: unknown,
    schema: ZodType<T>
  ): Promise<T> {
    const response = await this.request(path, this.jsonRequest("PUT", body));

    if (!response.ok) {
      const responseBody = await response.text();
      throw new RuntimeControlAPIError(
        `Runtime Control API request failed: ${response.status}`,
        response.status,
        responseBody
      );
    }

    return this.parse(path, schema, await response.json());
  }

  private async post<T>(
    path: string,
    body: unknown | undefined,
    schema: ZodType<T>
  ): Promise<T> {
    const response = await this.request(path, this.jsonRequest("POST", body));

    if (!response.ok) {
      const responseBody = await response.text();
      throw new RuntimeControlAPIError(
        `Runtime Control API request failed: ${response.status}`,
        response.status,
        responseBody
      );
    }

    return this.parse(path, schema, await response.json());
  }

  private async postRuntimeProviderCommand(
    path: "/platform/runtime-provider/restart"
  ): Promise<RuntimeProviderCommandResponse> {
    const response = await this.request(path, this.jsonRequest("POST", undefined));
    if (response.status !== 200 && response.status !== 503) {
      const responseBody = await response.text();
      throw new RuntimeControlAPIError(
        `Runtime Control API request failed: ${response.status}`,
        response.status,
        responseBody
      );
    }
    return this.parse(path, runtimeProviderCommandResponseSchema, await response.json());
  }

  private async delete<T>(
    path: string,
    body: unknown | undefined,
    schema: ZodType<T>
  ): Promise<T> {
    const response = await this.request(path, this.jsonRequest("DELETE", body));

    if (!response.ok) {
      const responseBody = await response.text();
      throw new RuntimeControlAPIError(
        `Runtime Control API request failed: ${response.status}`,
        response.status,
        responseBody
      );
    }

    return this.parse(path, schema, await response.json());
  }

  private parse<T>(path: string, schema: ZodType<T>, data: unknown): T {
    const result = schema.safeParse(data);
    if (!result.success) {
      throw new RuntimeControlContractError(path, result.error);
    }
    return result.data;
  }

  private headers(): HeadersInit {
    const headers: Record<string, string> = {
      Accept: "application/json"
    };
    if (this.token) {
      headers["X-Runtime-Control-Token"] = this.token;
    }
    return headers;
  }

  private jsonRequest(method: string, body: unknown | undefined): RequestInit {
    if (body === undefined) {
      return {
        method,
        headers: this.headers()
      };
    }

    return {
      method,
      headers: {
        ...this.headers(),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    };
  }

  private async request(
    path: string,
    init: RequestInit,
    query: RuntimeControlRequestQuery = {}
  ): Promise<Response> {
    await this.ensureBrowserSession();
    const url = this.url(path, query);
    const response = await this.fetch(url, {
      ...init,
      credentials: "same-origin"
    });
    if (!this.useBrowserSession || response.status !== 401) {
      return response;
    }

    this.browserSessionBootstrap = undefined;
    await this.ensureBrowserSession();
    return this.fetch(url, {
      ...init,
      credentials: "same-origin"
    });
  }

  private async ensureBrowserSession(): Promise<void> {
    if (!this.useBrowserSession) {
      return;
    }
    if (!this.browserSessionBootstrap) {
      const bootstrap = this.bootstrapBrowserSession();
      this.browserSessionBootstrap = bootstrap;
      try {
        await bootstrap;
      } catch (error) {
        this.browserSessionBootstrap = undefined;
        throw error;
      }
      return;
    }
    await this.browserSessionBootstrap;
  }

  private async bootstrapBrowserSession(): Promise<void> {
    const path = "/platform/browser-session";
    const url = this.url(path, {});
    const response = await this.fetch(url, {
      method: "POST",
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    });
    if (!response.ok) {
      throw new RuntimeControlAPIError(
        `Runtime Control browser session bootstrap failed: ${response.status}`,
        response.status,
        await response.text()
      );
    }
  }

  private async fetch(url: string, init: RequestInit): Promise<Response> {
    try {
      return await this.fetchImpl(url, init);
    } catch (cause) {
      throw new RuntimeControlNetworkError(url, cause);
    }
  }

  private url(
    path: string,
    query: RuntimeControlRequestQuery
  ): string {
    const url = new URL(`${this.baseURL}${path}`, window.location.origin);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, String(value));
    }
    return url.toString();
  }
}

function trimTrailingSlash(value: string): string {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}

function labSessionPath(sessionId: string): string {
  return `/runtime/lab/sessions/${encodeURIComponent(sessionId)}`;
}

function runtimeEventQueryParameters(
  query: RuntimeEventQuery
): RuntimeControlRequestQuery {
  const params: RuntimeControlRequestQuery = {};
  const fields: Array<keyof RuntimeEventQuery> = [
    "limit",
    "type",
    "since",
    "cursor"
  ];

  for (const field of fields) {
    if (!Object.prototype.hasOwnProperty.call(query, field)) {
      continue;
    }

    const value = query[field];
    if (value === undefined) {
      throw new RuntimeControlValidationError(
        "Runtime event query contains an undefined value.",
        [`${field} must be omitted or set to a value.`]
      );
    }
    if (
      field === "type" &&
      (typeof value !== "string" ||
        !runtimeEventTypeValues.includes(value as RuntimeEventTypeValue))
    ) {
      throw new RuntimeControlValidationError(
        "Runtime event query type is not a Guest operation event type.",
        ["type must be one of the documented operation-* values."]
      );
    }
    params[field] = value;
  }

  return params;
}
