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
  VitalDBRecorders
} from "../../domain/runtime-control/contracts/runtimeControlTypes";
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
  vitalDBRecordersSchema
} from "../../domain/runtime-control/contracts/schemas/runtimeControlSchemas";
import type { ZodType } from "zod";

export type RuntimeControlClientOptions = {
  baseURL?: string;
  token?: string;
  fetchImpl?: typeof fetch;
};

export type RuntimeEventQuery = {
  limit?: number;
  type?: string;
  since?: string;
  cursor?: string;
};

export class RuntimeControlAPIError extends Error {
  readonly status: number;
  readonly body: string;

  constructor(message: string, status: number, body: string) {
    super(message);
    this.name = "RuntimeControlAPIError";
    this.status = status;
    this.body = body;
  }
}

export class RuntimeControlContractError extends Error {
  readonly path: string;
  readonly cause: unknown;

  constructor(path: string, cause: unknown) {
    super(`Runtime Control API contract validation failed: ${path}`);
    this.name = "RuntimeControlContractError";
    this.path = path;
    this.cause = cause;
  }
}

export class RuntimeControlClient {
  private readonly baseURL: string;
  private readonly token: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: RuntimeControlClientOptions = {}) {
    this.baseURL = trimTrailingSlash(
      options.baseURL ??
        import.meta.env.VITE_RUNTIME_CONTROL_API_BASE_URL ??
        ""
    );
    this.token =
      options.token ??
      import.meta.env.VITE_RUNTIME_CONTROL_TOKEN ??
      "vitalserver-helper-dev";
    this.fetchImpl = options.fetchImpl ?? fetch;
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

  getRuntimeEvents(query: RuntimeEventQuery = {}): Promise<RuntimeEventHistory> {
    return this.get("/runtime/events", runtimeEventHistorySchema, query);
  }

  getRecorders(): Promise<VitalDBRecorders> {
    return this.get("/vitaldb/recorders", vitalDBRecordersSchema);
  }

  getBeds(): Promise<VitalDBBeds> {
    return this.get("/vitaldb/beds", vitalDBBedsSchema);
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

  restoreRedisBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post(
      "/host/backups/redis/restore",
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

  repairRuntime(): Promise<RuntimeCommandResponse> {
    return this.post(
      "/runtime/services/repair-runtime",
      undefined,
      runtimeCommandResponseSchema
    );
  }

  repairProxy(proxyPort?: number): Promise<RuntimeCommandResponse> {
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

  private async get<T>(
    path: string,
    schema: ZodType<T>,
    query: Record<string, string | number | undefined> = {}
  ): Promise<T> {
    const response = await this.fetchImpl(this.url(path, query), {
      method: "GET",
      headers: this.headers()
    });

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
    const response = await this.fetchImpl(this.url(path, {}), {
      method: "PUT",
      headers: {
        ...this.headers(),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

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
    body: unknown,
    schema: ZodType<T>
  ): Promise<T> {
    const response = await this.fetchImpl(this.url(path, {}), {
      method: "POST",
      headers: {
        ...this.headers(),
        "Content-Type": "application/json"
      },
      body: body === undefined ? undefined : JSON.stringify(body)
    });

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
    body: unknown,
    schema: ZodType<T>
  ): Promise<T> {
    const response = await this.fetchImpl(this.url(path, {}), {
      method: "DELETE",
      headers: {
        ...this.headers(),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

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

  private url(
    path: string,
    query: Record<string, string | number | undefined>
  ): string {
    const url = new URL(`${this.baseURL}${path}`, window.location.origin);
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined) {
        url.searchParams.set(key, String(value));
      }
    }
    return url.toString();
  }
}

export const runtimeControlClient = new RuntimeControlClient();

function trimTrailingSlash(value: string): string {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}
