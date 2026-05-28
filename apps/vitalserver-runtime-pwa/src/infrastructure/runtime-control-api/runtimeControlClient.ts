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
    return this.get("/runtime/capabilities");
  }

  getOverview(): Promise<RuntimeControlOverview> {
    return this.get("/runtime/overview");
  }

  getStatus(): Promise<RuntimeStatus> {
    return this.get("/runtime/status");
  }

  getSettings(): Promise<RuntimeSettings> {
    return this.get("/runtime/settings");
  }

  applySettings(
    request: RuntimeApplySettingsRequest
  ): Promise<RuntimeCommandResponse> {
    return this.put("/runtime/settings", request);
  }

  startRuntimeServices(): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/services/start", undefined);
  }

  stopRuntimeServices(): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/services/stop", undefined);
  }

  uninstallRuntime(
    request: RuntimeUninstallRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/uninstall", request);
  }

  getRuntimeEvents(query: RuntimeEventQuery = {}): Promise<RuntimeEventHistory> {
    return this.get("/runtime/events", query);
  }

  getRecorders(): Promise<VitalDBRecorders> {
    return this.get("/vitaldb/recorders");
  }

  getBeds(): Promise<VitalDBBeds> {
    return this.get("/vitaldb/beds");
  }

  getTestKitStatus(): Promise<RuntimeTestKitStatus> {
    return this.get("/dev/testkit/status");
  }

  createTestKitBeds(request: RuntimeTestKitCreateBedsRequest) {
    return this.post("/dev/testkit/beds/create", request);
  }

  deleteTestKitBeds(request: RuntimeTestKitDeleteBedsRequest) {
    return this.post("/dev/testkit/beds/delete", request);
  }

  resetTestKitBeds() {
    return this.post("/dev/testkit/beds/reset", undefined);
  }

  startTestKitVirtualRecorders(
    request: RuntimeTestKitVirtualRecorderStartRequest
  ): Promise<RuntimeTestKitSession> {
    return this.post("/dev/testkit/virtual-recorders/start", request);
  }

  stopTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post("/dev/testkit/virtual-recorders/stop", request);
  }

  pauseTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post("/dev/testkit/virtual-recorders/pause", request);
  }

  resumeTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post("/dev/testkit/virtual-recorders/resume", request);
  }

  restartTestKitVirtualRecorders(
    request: RuntimeTestKitRestartRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post("/dev/testkit/virtual-recorders/restart", request);
  }

  deleteTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null> {
    return this.post("/dev/testkit/virtual-recorders/delete", request);
  }

  resetTestKitVirtualRecorders(): Promise<RuntimeTestKitStatus> {
    return this.post("/dev/testkit/virtual-recorders/reset", undefined);
  }

  deleteTestKitOrphanVRecorder(
    request: RuntimeTestKitRecorderDeletionRequest
  ) {
    return this.post("/dev/testkit/virtual-recorders/delete-orphan", request);
  }

  readLogs(request: RuntimeLogTextRequest): Promise<RuntimeLogTextResponse> {
    return this.post("/host/logs/read", request);
  }

  exportLogs(
    request: RuntimeExportLogsRequest
  ): Promise<RuntimeLogExportResult> {
    return this.post("/host/logs/export", request);
  }

  summarizeUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeUpdateBundleSummaryResponse> {
    return this.post("/host/update-bundles/summary", request);
  }

  verifyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post("/host/update-bundles/verify", request);
  }

  applyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post("/host/update-bundles/apply", request);
  }

  listHostBackups(): Promise<RuntimeBackup[]> {
    return this.get("/host/backups");
  }

  listRedisBackups(): Promise<RuntimeBackup[]> {
    return this.get("/host/backups/redis");
  }

  rollbackBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse> {
    return this.post("/host/backups/rollback", request);
  }

  deleteHostBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.delete("/host/backups", request);
  }

  restoreRedisBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse> {
    return this.post("/host/backups/redis/restore", request);
  }

  createRedisBackup(): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/redis/backups", undefined);
  }

  repairRuntime(): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/services/repair-runtime", undefined);
  }

  repairProxy(proxyPort?: number): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/services/repair-proxy", { proxyPort });
  }

  repairDatastore(): Promise<RuntimeCommandResponse> {
    return this.post("/runtime/services/repair-datastore", undefined);
  }

  private async get<T>(
    path: string,
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

    return (await response.json()) as T;
  }

  private async put<T>(path: string, body: unknown): Promise<T> {
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

    return (await response.json()) as T;
  }

  private async post<T>(path: string, body: unknown): Promise<T> {
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

    return (await response.json()) as T;
  }

  private async delete<T>(path: string, body: unknown): Promise<T> {
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

    return (await response.json()) as T;
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
