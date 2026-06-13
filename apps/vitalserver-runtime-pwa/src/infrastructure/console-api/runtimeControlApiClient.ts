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
  RuntimeLogExportResult,
  RuntimeLogTextRequest,
  RuntimeLogTextResponse,
  RuntimeSettings,
  RuntimeStatus,
  RuntimeTestKitCreateBedsRequest,
  RuntimeTestKitDeleteBedsRequest,
  RuntimeTestKitRecorderDeletionRequest,
  RuntimeTestKitRestartRequest,
  RuntimeTestKitSession,
  RuntimeTestKitSessionSelectionRequest,
  RuntimeTestKitStatus,
  RuntimeTestKitVirtualRecorderStartRequest,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest,
  RuntimeUpdateBundleSummaryResponse,
  VitalDBBeds,
  VitalDBRecorders,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeBackupSchema,
  runtimeCapabilitiesSchema,
  runtimeCommandResponseSchema,
  runtimeEventHistorySchema,
  runtimeLogExportResultSchema,
  runtimeLogTextResponseSchema,
  runtimeOverviewSchema,
  runtimeSettingsSchema,
  runtimeStatusSchema,
  runtimeTestKitBedListSchema,
  runtimeTestKitRecorderDeletionSchema,
  runtimeTestKitSessionOrNullSchema,
  runtimeTestKitSessionSchema,
  runtimeTestKitStatusSchema,
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

  getSettings(): Promise<RuntimeSettings> {
    return this.get("/runtime/settings", runtimeSettingsSchema);
  }

  applySettings(
    request: RuntimeApplySettingsRequest
  ): Promise<RuntimeCommandResponse> {
    return this.put("/runtime/settings", request, runtimeCommandResponseSchema);
  }

  startRuntimeServices(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/start",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  stopRuntimeServices(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/stop",
      undefined,
      runtimeCommandResponseSchema
    );
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

  getBeds(): Promise<VitalDBBeds> {
    return this.get("/vitaldb/beds", vitalDBBedsSchema);
  }

  getRelationships(): Promise<VitalDBRelationships> {
    return this.get("/vitaldb/relationships", vitalDBRelationshipsSchema);
  }

  getTestKitStatus(): Promise<RuntimeTestKitStatus> {
    return this.get("/dev/testkit/status", runtimeTestKitStatusSchema);
  }

  createTestKitBeds(request: RuntimeTestKitCreateBedsRequest) {
    return this.post(
      "/dev/testkit/beds/create",
      request,
      runtimeTestKitBedListSchema
    );
  }

  deleteTestKitBeds(request: RuntimeTestKitDeleteBedsRequest) {
    return this.post(
      "/dev/testkit/beds/delete",
      request,
      runtimeTestKitBedListSchema
    );
  }

  resetTestKitBeds() {
    return this.post(
      "/dev/testkit/beds/reset",
      undefined,
      runtimeTestKitBedListSchema
    );
  }

  startTestKitVirtualRecorders(
    request: RuntimeTestKitVirtualRecorderStartRequest
  ): Promise<RuntimeTestKitSession> {
    return this.post(
      "/dev/testkit/virtual-recorders/start",
      request,
      runtimeTestKitSessionSchema
    );
  }

  stopTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post(
      "/dev/testkit/virtual-recorders/stop",
      request,
      runtimeTestKitSessionOrNullSchema
    );
  }

  pauseTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post(
      "/dev/testkit/virtual-recorders/pause",
      request,
      runtimeTestKitSessionOrNullSchema
    );
  }

  resumeTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post(
      "/dev/testkit/virtual-recorders/resume",
      request,
      runtimeTestKitSessionOrNullSchema
    );
  }

  restartTestKitVirtualRecorders(
    request: RuntimeTestKitRestartRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post(
      "/dev/testkit/virtual-recorders/restart",
      request,
      runtimeTestKitSessionOrNullSchema
    );
  }

  deleteTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post(
      "/dev/testkit/virtual-recorders/delete",
      request,
      runtimeTestKitSessionOrNullSchema
    );
  }

  resetTestKitVirtualRecorders(): Promise<RuntimeTestKitStatus> {
    return this.post(
      "/dev/testkit/virtual-recorders/reset",
      undefined,
      runtimeTestKitStatusSchema
    );
  }

  deleteTestKitOrphanVRecorder(
    request: RuntimeTestKitRecorderDeletionRequest
  ) {
    return this.post(
      "/dev/testkit/virtual-recorders/delete-orphan",
      request,
      runtimeTestKitRecorderDeletionSchema
    );
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
    return this.get("/host/backups/runtime-data", runtimeBackupSchema.array());
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
      "/host/backups/runtime-data",
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
      "/host/backups/runtime-data/restore",
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
