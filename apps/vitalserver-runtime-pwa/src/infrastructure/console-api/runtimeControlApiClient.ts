import type {
  RuntimeControlGateway,
  RuntimeEventQuery
} from "@/console/runtimeControlGateway";
import {
  RuntimeControlAPIError,
  RuntimeControlContractError,
  RuntimeControlNetworkError,
  RuntimeControlValidationError
} from "@/domain/runtime-control/errors/runtimeControlError";
import type {
  RuntimeControlCapabilities,
  RuntimeControlOverview,
  RuntimeApplySettingsRequest,
  RuntimeBackup,
  RuntimeBackupRequest,
  RuntimeCommandResponse,
  RuntimeExportLogsRequest,
  RuntimeEventHistory,
  RuntimeGuestControlServiceOperation,
  RuntimeGuestControlStackStatus,
  RuntimeGuestServiceControlRequest,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabBedList,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabRecorderList,
  RuntimeLabScenarioList,
  RuntimeLabSessionCreateRequest,
  RuntimeLabSessionResponse,
  RuntimeLabVitalFileReplayRequest,
  RuntimeLogExportResult,
  RuntimeLogTextRequest,
  RuntimeLogTextResponse,
  RuntimeOperationState,
  RuntimeSettings,
  RuntimeStatus,
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
  runtimeCapabilitiesSchema,
  runtimeCommandResponseSchema,
  runtimeEventHistorySchema,
  runtimeGuestControlStackStatusSchema,
  runtimeGuestControlServiceOperationSchema,
  runtimeLabBedListSchema,
  runtimeLabRecorderListSchema,
  runtimeLabScenarioListSchema,
  runtimeLabSessionResponseSchema,
  runtimeLogExportResultSchema,
  runtimeLogTextResponseSchema,
  runtimeOperationStateSchema,
  runtimeOverviewSchema,
  runtimeSettingsSchema,
  runtimeStatusSchema,
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
  fetchImpl?: typeof fetch;
};

export class RuntimeControlApiClient implements RuntimeControlGateway {
  private readonly baseURL: string;
  private readonly token: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: RuntimeControlApiClientOptions = {}) {
    this.baseURL = trimTrailingSlash(
      options.baseURL ?? DEFAULT_APP_SETTINGS.runtimeControl.apiBaseURL
    );
    this.token =
      options.token ?? DEFAULT_APP_SETTINGS.runtimeControl.token;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  getCapabilities(): Promise<RuntimeControlCapabilities> {
    return this.get("/runtime/capabilities", runtimeCapabilitiesSchema);
  }

  getOverview(): Promise<RuntimeControlOverview> {
    return this.get("/runtime/overview", runtimeOverviewSchema);
  }

  getStatus(): Promise<RuntimeStatus> {
    return this.get("/runtime/status", runtimeStatusSchema);
  }

  getOperationState(): Promise<RuntimeOperationState> {
    return this.get("/runtime/operation-state", runtimeOperationStateSchema);
  }

  getSettings(): Promise<RuntimeSettings> {
    return this.get("/runtime/settings", runtimeSettingsSchema);
  }

  getLabScenarios(): Promise<RuntimeLabScenarioList> {
    return this.get("/lab/scenarios", runtimeLabScenarioListSchema);
  }

  getLabBeds(): Promise<RuntimeLabBedList> {
    return this.get("/lab/beds", runtimeLabBedListSchema);
  }

  getLabRecorders(): Promise<RuntimeLabRecorderList> {
    return this.get("/lab/recorders", runtimeLabRecorderListSchema);
  }

  createLabBeds(request: RuntimeLabBedCreateRequest): Promise<RuntimeLabBedList> {
    return this.post("/lab/beds/create", request, runtimeLabBedListSchema);
  }

  deleteLabBeds(request: RuntimeLabBedDeleteRequest): Promise<RuntimeLabBedList> {
    return this.post("/lab/beds/delete", request, runtimeLabBedListSchema);
  }

  resetLabBeds(): Promise<RuntimeLabBedList> {
    return this.post("/lab/beds/reset", undefined, runtimeLabBedListSchema);
  }

  createLabRecorders(
    request: RuntimeLabRecorderCreateRequest
  ): Promise<RuntimeLabRecorderList> {
    return this.post("/lab/recorders/create", request, runtimeLabRecorderListSchema);
  }

  deleteLabRecorders(
    request: RuntimeLabRecorderDeleteRequest
  ): Promise<RuntimeLabRecorderList> {
    return this.post("/lab/recorders/delete", request, runtimeLabRecorderListSchema);
  }

  resetLabRecorders(): Promise<RuntimeLabRecorderList> {
    return this.post("/lab/recorders/reset", undefined, runtimeLabRecorderListSchema);
  }

  createLabSession(
    request: RuntimeLabSessionCreateRequest
  ): Promise<RuntimeLabSessionResponse> {
    return this.post("/lab/sessions", request, runtimeLabSessionResponseSchema);
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

  replayLabVitalFile(
    request: RuntimeLabVitalFileReplayRequest
  ): Promise<RuntimeLabSessionResponse> {
    return this.post(
      "/lab/vital-files/replay",
      request,
      runtimeLabSessionResponseSchema
    );
  }

  getGuestStackStatus(): Promise<RuntimeGuestControlStackStatus> {
    return this.get(
      "/runtime/guest/stack/status",
      runtimeGuestControlStackStatusSchema
    );
  }

  startGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      "/runtime/guest/services/start",
      request,
      runtimeGuestControlServiceOperationSchema
    );
  }

  stopGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      "/runtime/guest/services/stop",
      request,
      runtimeGuestControlServiceOperationSchema
    );
  }

  restartGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation> {
    return this.post(
      "/runtime/guest/services/restart",
      request,
      runtimeGuestControlServiceOperationSchema
    );
  }

  applySettings(
    request: RuntimeApplySettingsRequest
  ): Promise<RuntimeCommandResponse> {
    return this.put("/runtime/settings", request, runtimeCommandResponseSchema);
  }

  uninstallRuntime(
    request: RuntimeUninstallRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/uninstall",
      request,
      runtimeCommandResponseSchema
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
    return this.get("/vitaldb/recorders", vitalDBRecordersSchema);
  }

  hideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/vitaldb/recorders/hide", request, vitalDBRecordersSchema);
  }

  unhideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/vitaldb/recorders/unhide", request, vitalDBRecordersSchema);
  }

  deleteRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/vitaldb/recorders/delete", request, vitalDBRecordersSchema);
  }

  getBeds(): Promise<VitalDBBeds> {
    return this.get("/vitaldb/beds", vitalDBBedsSchema);
  }

  hideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/vitaldb/beds/hide", request, vitalDBRecordersSchema);
  }

  unhideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/vitaldb/beds/unhide", request, vitalDBRecordersSchema);
  }

  deleteBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBRecorders> {
    return this.post("/vitaldb/beds/delete", request, vitalDBRecordersSchema);
  }

  getRelationships(): Promise<VitalDBRelationships> {
    return this.get("/vitaldb/relationships", vitalDBRelationshipsSchema);
  }

  readLogs(request: RuntimeLogTextRequest): Promise<RuntimeLogTextResponse> {
    return this.post("/host/logs/read", request, runtimeLogTextResponseSchema);
  }

  exportLogs(
    request: RuntimeExportLogsRequest
  ): Promise<RuntimeLogExportResult> {
    return this.post(
      "/host/logs/export",
      request,
      runtimeLogExportResultSchema
    );
  }

  summarizeUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeUpdateBundleSummaryResponse> {
    return this.post(
      "/host/update-bundles/summary",
      request,
      runtimeUpdateBundleSummaryResponseSchema
    );
  }

  verifyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/host/update-bundles/verify",
      request,
      runtimeCommandResponseSchema
    );
  }

  applyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/host/update-bundles/apply",
      request,
      runtimeCommandResponseSchema
    );
  }

  listHostBackups(): Promise<RuntimeBackup[]> {
    return this.get("/host/backups", runtimeBackupSchema.array());
  }

  listRedisBackups(): Promise<RuntimeBackup[]> {
    return this.get("/host/backups/redis", runtimeBackupSchema.array());
  }

  listRuntimeDataBackups(): Promise<RuntimeBackup[]> {
    return this.get("/host/backups/vitalserver-helper", runtimeBackupSchema.array());
  }

  rollbackBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse> {
    return this.post(
      "/host/backups/rollback",
      request,
      runtimeCommandResponseSchema
    );
  }

  deleteHostBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete("/host/backups", request, runtimeCommandResponseSchema);
  }

  deleteUpdateBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete(
      "/host/backups/update",
      request,
      runtimeCommandResponseSchema
    );
  }

  deleteRuntimeDataBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete(
      "/host/backups/vitalserver-helper",
      request,
      runtimeCommandResponseSchema
    );
  }

  restoreRedisBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/host/backups/redis/restore",
      request,
      runtimeCommandResponseSchema
    );
  }

  restoreRuntimeDataBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/host/backups/vitalserver-helper/restore",
      request,
      runtimeCommandResponseSchema
    );
  }

  createRedisBackup(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/redis/backups",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  createRuntimeDataBackup(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/data/backups",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  repairRuntime(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/repair-runtime",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  repairProxy(proxyPort: number): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/repair-proxy",
      { proxyPort },
      runtimeCommandResponseSchema
    );
  }

  repairDatastore(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/repair-datastore",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  repairVMDisk(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/repair-vm-disk",
      undefined,
      runtimeCommandResponseSchema
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
    return {
      Accept: "application/json",
      "X-Runtime-Control-Token": this.token
    };
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
    const url = this.url(path, query);
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
  return `/lab/sessions/${encodeURIComponent(sessionId)}`;
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
    params[field] = value;
  }

  return params;
}
