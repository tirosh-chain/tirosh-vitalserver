import { describe, expect, it, vi } from "vitest";

import {
  RuntimeControlAPIError,
  RuntimeControlContractError,
  RuntimeControlNetworkError,
  RuntimeControlValidationError,
  summarizeRuntimeControlError
} from "@/domain/runtime-control/errors/runtimeControlError";
import { RuntimeControlApiClient } from "./runtimeControlApiClient";

type RecordedRequest = {
  url: string;
  init: RequestInit;
};

describe("RuntimeControlApiClient", () => {
  it("schedules a managed Platform support export without a caller path", async () => {
    const operation = {
      ...platformWorkflowOperation("update-verify"),
      operationId: "support-export-1",
      kind: "support-export" as const,
      state: "accepted" as const
    };
    const { client, requests } = clientWithResponses({
      "/platform/support-exports": operation
    });

    await expect(client.createPlatformSupportExport()).resolves.toEqual(operation);
    expect(requests[0]?.init.method).toBe("POST");
    expect(requests[0]?.init.body).toBeUndefined();
  });

  it("sends authenticated GET requests with query parameters", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/events": { events: [], nextCursor: null, matchingCount: 0 }
    });

    await expect(
      client.getRuntimeEvents({ limit: 5, type: "operation-completed" })
    ).resolves.toEqual({
      events: [],
      nextCursor: null,
      matchingCount: 0
    });

    expect(requests[0]?.url).toBe(
      "http://helper.local/runtime/events?limit=5&type=operation-completed"
    );
    expect(requests[0]?.init.method).toBe("GET");
    expect(requests[0]?.init.headers).toMatchObject({
      Accept: "application/json",
      "X-Runtime-Control-Token": "token-a"
    });
  });

  it("preserves a Guest operation-ledger 503 response", async () => {
    const { client } = clientWithResponses(
      {
        "/runtime/events": {
          code: "guestControlUnavailable",
          message: "Guest operation event ledger is unavailable"
        }
      },
      503
    );

    await expect(client.getRuntimeEvents()).rejects.toMatchObject({
      kind: "api",
      status: 503,
      body: JSON.stringify({
        code: "guestControlUnavailable",
        message: "Guest operation event ledger is unavailable"
      })
    });
  });

  it("uses an opaque same-origin browser session instead of a shipped API token", async () => {
    const requests: RecordedRequest[] = [];
    const fetchImpl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      requests.push({ url, init: init ?? {} });
      if (new URL(url).pathname === "/platform/browser-session") {
        return new Response(null, { status: 204 });
      }
      return new Response(JSON.stringify(platformCapabilities()), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }) as typeof fetch;
    const client = new RuntimeControlApiClient({
      token: "",
      useBrowserSession: true,
      fetchImpl
    });

    await expect(client.getPlatformCapabilities()).resolves.toEqual(platformCapabilities());

    expect(requests.map((request) => new URL(request.url).pathname)).toEqual([
      "/platform/browser-session",
      "/platform/capabilities"
    ]);
    for (const request of requests) {
      expect(request.init.credentials).toBe("same-origin");
      expect(request.init.headers).toEqual({ Accept: "application/json" });
    }
  });

  it("reads and applies Runtime-owned Redis Relay settings", async () => {
    const read = {
      state: "loaded",
      settings: {
        enabled: false,
        target: {
          url: "redis://redis.example:6379/0",
          username: "",
          passwordConfigured: false,
          tls: false
        },
        scope: "vital_reconstruction",
        includeRecorderNetworkContext: false,
        intervalSeconds: 1,
        scanCount: 1000
      },
      readError: null
    };
    const apply = {
      enabled: true,
      target: {
        url: "redis://relay.example:6379/1",
        username: "relay",
        password: "secret",
        clearPassword: false,
        tls: true
      },
      scope: "waveform_trend_only" as const,
      includeRecorderNetworkContext: true,
      intervalSeconds: 0.5,
      scanCount: 250
    };
    const { client, requests } = clientWithResponses({
      "/runtime/redis-relay/settings": read,
      "PUT /runtime/redis-relay/settings": runtimeSettingsOperation()
    });

    await expect(client.getRuntimeRedisRelaySettings()).resolves.toEqual(read);
    await client.applyRuntimeRedisRelaySettings(apply);

    expect(requests.map((request) => request.init.method)).toEqual(["GET", "PUT"]);
    expect(JSON.parse(String(requests[1]?.init.body))).toEqual(apply);
  });

  it("parses all Runtime settings apply operation responses at the HTTP boundary", async () => {
    const adminOperation = runtimeSettingsOperation(
      "apply-admin-password",
      "runtime-admin"
    );
    const relayOperation = runtimeSettingsOperation(
      "apply-redis-relay-settings",
      "redis-relay-settings"
    );
    const { client } = clientWithResponses({
      "POST /runtime/admin-password": adminOperation,
      "PUT /runtime/redis-relay/settings": relayOperation
    });

    await expect(
      client.applyRuntimeAdminPassword({ password: "new-admin-secret" })
    ).resolves.toEqual(adminOperation);
    await expect(
      client.applyRuntimeRedisRelaySettings({
        enabled: false,
        target: {
          url: "redis://relay.example:6379/0",
          username: "",
          password: "",
          clearPassword: false,
          tls: false
        },
        scope: "vital_reconstruction",
        includeRecorderNetworkContext: false,
        intervalSeconds: 1,
        scanCount: 1000
      })
    ).resolves.toEqual(relayOperation);
  });

  it("sends JSON bodies only for endpoints with request payloads", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/settings": runtimeSettingsOperation(),
      "/platform/uninstall": platformWorkflowOperation("uninstall"),
      "DELETE /platform/backups/update": commandResponse(),
      "DELETE /platform/backups/runtime-data": commandResponse()
    });

    await client.applyRuntimeProductSettings({ settings: productSettings() });
    await client.uninstallRuntime({ mode: "clean" });
    await client.deleteUpdateBackup({ backup: { kind: "localPath", value: "/tmp/update" } });
    await client.deleteRuntimeDataBackup({
      backup: { kind: "localPath", value: "/tmp/runtime-data" }
    });

    expect(requests.map((request) => request.init.method)).toEqual([
      "PUT",
      "POST",
      "DELETE",
      "DELETE"
    ]);
    expect(JSON.parse(String(requests[0]?.init.body))).toEqual({
      settings: productSettings()
    });
    expect(requests[0]?.init.headers).toMatchObject({
      "Content-Type": "application/json"
    });
  });

  it("keeps absent JSON bodies distinct from explicit JSON command payloads", async () => {
    const { client, requests } = clientWithResponses({
      "/platform/backups/redis": commandResponse(),
      "/platform/runtime-provider/restart": runtimeProviderCommandResponse()
    });

    await client.createRedisBackup();
    await client.restartRuntimeProvider();

    for (const request of requests) {
      expect(request.init.body).toBeUndefined();
      expect(request.init.headers).not.toMatchObject({
        "Content-Type": "application/json"
      });
    }
  });

  it("preserves the typed Runtime Provider failure returned with 503", async () => {
    const failed = runtimeProviderCommandResponse("failed");
    const { client } = clientWithResponses(
      { "/platform/runtime-provider/restart": failed },
      503
    );

    await expect(client.restartRuntimeProvider()).resolves.toEqual(failed);
  });

  it("reports an unavailable Runtime Provider command without treating it as a failed effect", async () => {
    const { client } = clientWithResponses(
      {
        "/platform/runtime-provider/restart": {
          code: "platformAffordanceUnavailable",
          message: "Runtime Provider control is unavailable."
        }
      },
      501
    );

    await expect(client.restartRuntimeProvider()).rejects.toMatchObject({
      status: 501
    });
  });

  it("accepts the Guest datastore repair operation response", async () => {
    const operation = guestServiceOperation("repair-datastore", "datastore-repair");
    const { client, requests } = clientWithResponses(
      { "/runtime/maintenance/datastore/repair": operation },
      202
    );

    await expect(client.repairDatastore()).resolves.toEqual(operation);
    expect(requests[0]?.init.method).toBe("POST");
    expect(requests[0]?.init.body).toBeUndefined();
  });

  it("rejects undefined query values instead of dropping them", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/events": { events: [], nextCursor: null, matchingCount: 0 }
    });

    await expect(
      client.getRuntimeEvents({ limit: 5, type: undefined })
    ).rejects.toBeInstanceOf(RuntimeControlValidationError);
    expect(requests).toHaveLength(0);
  });

  it("rejects non-operation event types before requesting the Guest ledger", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/events": { events: [], nextCursor: null, matchingCount: 0 }
    });

    await expect(
      client.getRuntimeEvents({ limit: 5, type: "status-changed" as never })
    ).rejects.toBeInstanceOf(RuntimeControlValidationError);
    expect(requests).toHaveLength(0);
  });

  it("covers read endpoints and host affordance endpoints", async () => {
    const { client, requests } = clientWithResponses({
      "/platform/capabilities": platformCapabilities(),
      "/runtime/capabilities": {
        schemaVersion: 1,
        capabilities: [
          "services:start",
          "services:stop",
          "services:restart",
          "lab:scenarios",
          "lab:sessions:list",
          "lab:recorders:start",
          "lab:recorders:stop",
          "maintenance:datastore-repair:create"
        ]
      },
      "/runtime/vitaldb/observations/latest": {
        state: "unavailable",
        observation: null,
        readError: "not observed"
      },
      "/platform": { runtimeInstallationState: "executable", services: platformServices(), platformHealth: "healthy" },
      "/runtime/redis-relay/status": {
        readState: "readFailed",
        document: null,
        readError: "owner unavailable"
      },
      "/platform/operations": {
        activeOperation: "apply-bundle",
        install: {
          state: "unavailable",
          document: null,
          readError: null
        },
        lease: {
          state: "stale",
          document: {
            schemaVersion: 1,
            operationId: "operation-1",
            operation: "apply-bundle",
            ownerPID: 123,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:01Z",
            expiresAt: "2026-07-08T00:00:02Z",
            message: "applying bundle"
          },
          readError: null,
          staleReason: "expired"
        }
      },
      "/runtime/settings": {
        state: "loaded",
        settings: productSettings(),
        readError: null
      },
      "/runtime/lab/scenarios": {
        state: "loaded",
        scenarios: [{ scenarioId: "baseline", name: "Baseline", category: "generated" }],
        readError: null
      },
      "/runtime/lab/beds": {
        state: "loaded",
        beds: [
          {
            bedId: "lab-1-bed-1",
            sessionId: "lab-1",
            name: "OR-A",
            state: "running",
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00"
          }
        ],
        readError: null
      },
      "/runtime/lab/recorders": {
        state: "loaded",
        recorders: [
          {
            recorderId: "lab-1-recorder-1",
            sessionId: "lab-1",
            bedId: "lab-1-bed-1",
            vrcode: "LAB-lab-1-1",
            state: "running",
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            messagesSent: 1,
            lastSendState: "sent",
            lastSendAt: "2026-07-01T00:00:01+00:00",
            lastSendError: null
          }
        ],
        readError: null
      },
      "GET /runtime/lab/sessions": {
        state: "loaded",
        sessions: [labSessionResponse().session],
        readError: null
      },
      "POST /runtime/lab/sessions": labSessionResponse(),
      "/runtime/lab/sessions/lab-1": labSessionResponse(),
      "/runtime/lab/sessions/lab-1/start": labSessionResponse(),
      "/runtime/lab/sessions/lab-1/stop": labSessionResponse(),
      "/runtime/lab/sessions/lab-1/recorders/lab-1-recorder-1/start":
        labRecorderResponse("running"),
      "/runtime/lab/sessions/lab-1/recorders/lab-1-recorder-1/stop":
        labRecorderResponse("stopped"),
      "/runtime/lab/vital-files": {
        state: "loaded",
        vitalFiles: [
          {
            displayName: "case.vital",
            relativePath: "case.vital",
            guestPath: "/mnt/tirosh-vital-files/case.vital",
            sizeBytes: 1024,
            modifiedAt: "2026-07-01T00:00:00+00:00"
          }
        ],
        readError: null
      },
      "/runtime/lab/vital-files/upload": {
        state: "completed",
        files: [
          { fileName: "case.vital", relativePath: "case.vital", sizeBytes: 4 },
          { fileName: "other.vital", relativePath: "other.vital", sizeBytes: 5 }
        ]
      },
      "/runtime/lab/vital-files/replay": labSessionResponse(),
      "/runtime/stack": {
        state: "loaded",
        observedAt: "2026-07-01T00:00:00+00:00",
        services: [
          {
            service: "app",
            state: "running",
            health: "healthy",
            observedAt: "2026-07-01T00:00:00+00:00"
          }
        ],
        probeErrors: []
      },
      "/runtime/services/app/resource": guestServiceResource(),
      "/runtime/services/app/start": guestServiceOperation("start"),
      "/runtime/services/app/stop": guestServiceOperation("stop"),
      "/runtime/services/app/restart": guestServiceOperation("restart"),
      "/runtime/vitaldb/recorders": fullVitalRecorderHistory(),
      "/runtime/vitaldb/recorders/hide": fullVitalRecorderHistory(),
      "/runtime/vitaldb/recorders/unhide": fullVitalRecorderHistory(),
      "/runtime/vitaldb/recorders/delete": fullVitalRecorderHistory(),
      "/runtime/vitaldb/beds": fullVitalBedHistory(),
      "/runtime/vitaldb/beds/hide": fullVitalBedHistory(),
      "/runtime/vitaldb/beds/unhide": fullVitalBedHistory(),
      "/runtime/vitaldb/beds/delete": fullVitalBedHistory(),
      "/runtime/vitaldb/relationships": {
        state: "loaded",
        assignments: [],
        events: [],
        readError: null
      },
      "/platform/logs/read": { text: "log" },
      "/platform/logs/export": { destination: "file:///tmp/logs.zip" },
      "/platform/workflows/current": {
        state: "missing",
        operation: null,
        readError: null
      },
      "/platform/update-bundles/summary": { summary: "ok" },
      "/platform/update-bundles/verify": platformWorkflowOperation("update-verify"),
      "/platform/update-bundles/apply": platformWorkflowOperation("update-apply"),
      "/platform/releases/rollback": platformWorkflowOperation("rollback"),
      "/platform/backups": [{ path: "/tmp/backup", sizeBytes: 1 }],
      "/platform/backups/redis": [{ path: "/tmp/redis", sizeBytes: null }],
      "/platform/backups/runtime-data": [{ path: "/tmp/runtime-data", sizeBytes: 10 }],
      "/platform/backups/rollback": commandResponse(),
      "DELETE /platform/backups/update": commandResponse(),
      "DELETE /platform/backups/runtime-data": commandResponse(),
      "/platform/backups/redis/restore": commandResponse(),
      "/platform/backups/runtime-data/restore": commandResponse(),
      "POST /platform/backups/redis": commandResponse(),
      "POST /platform/backups/runtime-data": commandResponse(),
      "/platform/runtime-provider/restart": runtimeProviderCommandResponse(),
      "/runtime/maintenance/datastore/repair": guestServiceOperation(
        "repair-datastore",
        "datastore-repair"
      )
    });

    await expect(client.getCapabilities()).resolves.toMatchObject({
      canUseLab: true,
      canListLabSessions: true,
      canControlLabRecorders: true,
      canRepairRuntimeDatastore: true
    });
    await expect(client.getLatestVitalDBObservation()).resolves.toEqual({
      state: "unavailable",
      observation: null,
      readError: "not observed"
    });
    await expect(client.getPlatformState()).resolves.toMatchObject({ platformHealth: "healthy" });
    await expect(client.getRedisRelayStatus()).resolves.toEqual({
      readState: "readFailed",
      document: null,
      readError: "owner unavailable"
    });
    await expect(client.getOperationState()).resolves.toMatchObject({
      activeOperation: "apply-bundle",
      lease: { state: "stale", staleReason: "expired" }
    });
    await expect(client.getRuntimeProductSettings()).resolves.toMatchObject({
      state: "loaded",
      settings: { publicPort: 80 }
    });
    await expect(client.getLabScenarios()).resolves.toMatchObject({ state: "loaded" });
    await expect(client.getLabBeds()).resolves.toMatchObject({ beds: [{ name: "OR-A" }] });
    await expect(client.getLabRecorders()).resolves.toMatchObject({
      recorders: [{ vrcode: "LAB-lab-1-1", messagesSent: 1, lastSendState: "sent" }]
    });
    await expect(client.getLabSessions()).resolves.toMatchObject({
      sessions: [{ sessionId: "lab-1" }]
    });
    await expect(client.createLabSession({
      scenarioId: "baseline",
      name: "Lab A",
      recorderCount: 2,
      targetURL: null
    })).resolves.toMatchObject({ session: { sessionId: "lab-1" } });
    await expect(client.getLabSession("lab-1")).resolves.toMatchObject({ session: { sessionId: "lab-1" } });
    await expect(client.startLabSession("lab-1")).resolves.toMatchObject({ session: { state: "accepted" } });
    await expect(client.stopLabSession("lab-1")).resolves.toMatchObject({ session: { state: "accepted" } });
    await expect(
      client.startLabRecorder("lab-1", "lab-1-recorder-1")
    ).resolves.toMatchObject({ recorder: { state: "running" } });
    await expect(
      client.stopLabRecorder("lab-1", "lab-1-recorder-1")
    ).resolves.toMatchObject({ recorder: { state: "stopped" } });
    await expect(client.getLabVitalFiles()).resolves.toMatchObject({
      vitalFiles: [{ displayName: "case.vital" }]
    });
    const uploadResult = await client.uploadLabVitalFiles({
      files: [
        new File(["case"], "case.vital"),
        new File(["other"], "other.vital")
      ]
    });
    expect(uploadResult.state).toBe("completed");
    expect(uploadResult.files.map((file) => file.fileName)).toEqual(["case.vital", "other.vital"]);
    const uploadBody = requests.find(
      (request) => new URL(request.url).pathname === "/runtime/lab/vital-files/upload"
    )?.init.body;
    expect(uploadBody).toBeInstanceOf(FormData);
    expect((uploadBody as FormData).getAll("files").map((entry) => (entry as File).name)).toEqual([
      "case.vital",
      "other.vital"
    ]);
    await expect(client.replayLabVitalFile({
      vitalFileRelativePath: "sample.vital",
      sessionName: "Replay",
      targetURL: null,
      resourceSelection: { mode: "quickCreate" },
      repeatPolicy: { mode: "once" }
    })).resolves.toMatchObject({ session: { sessionId: "lab-1" } });
    await expect(client.getRuntimeStack()).resolves.toMatchObject({
      state: "loaded",
      services: [{ service: "app" }]
    });
    await expect(client.getGuestServiceResource("app")).resolves.toMatchObject({
      service: "app",
      spec: { desiredState: "running" },
      status: { observedState: "running" },
      lastOperationId: "op-app"
    });
    await expect(client.startGuestService({ service: "app" })).resolves.toMatchObject({ command: "start" });
    await expect(client.stopGuestService({ service: "app" })).resolves.toMatchObject({ command: "stop" });
    await expect(client.restartGuestService({ service: "app" })).resolves.toMatchObject({ command: "restart" });
    await expect(client.getRecorders()).resolves.toMatchObject({ recorders: [] });
    await expect(client.hideRecorders({ vrcodes: ["VR_A"] })).resolves.toMatchObject({ recorders: [] });
    await expect(client.unhideRecorders({ vrcodes: ["VR_A"] })).resolves.toMatchObject({ recorders: [] });
    await expect(client.deleteRecorders({ vrcodes: ["VR_A"] })).resolves.toMatchObject({ recorders: [] });
    await expect(client.getBeds()).resolves.toMatchObject({ beds: [] });
    await expect(client.hideBeds({ bedIDs: ["bed-a"] })).resolves.toMatchObject({ beds: [] });
    await expect(client.unhideBeds({ bedIDs: ["bed-a"] })).resolves.toMatchObject({ beds: [] });
    await expect(client.deleteBeds({ bedIDs: ["bed-a"] })).resolves.toMatchObject({ beds: [] });
    await expect(client.getRelationships()).resolves.toMatchObject({ assignments: [] });
    await expect(client.readLogs({ source: "containers", helperMessage: "", lineLimit: 100 })).resolves.toEqual({ text: "log" });
    await expect(client.exportLogs({ destination: { kind: "localPath", value: "/tmp/logs.zip" } })).resolves.toEqual({ destination: "file:///tmp/logs.zip" });
    await expect(client.getPlatformWorkflow()).resolves.toEqual({
      state: "missing",
      operation: null,
      readError: null
    });
    await expect(client.summarizeUpdateBundle({ bundle: { kind: "localPath", value: "/tmp/u.zip" } })).resolves.toEqual({ summary: "ok" });
    await expect(client.verifyUpdateBundle({ bundle: { kind: "localPath", value: "/tmp/u.zip" } })).resolves.toEqual(platformWorkflowOperation("update-verify"));
    await expect(client.applyUpdateBundle({ bundle: { kind: "localPath", value: "/tmp/u.zip" } })).resolves.toEqual(platformWorkflowOperation("update-apply"));
    await expect(client.rollbackRelease()).resolves.toEqual(platformWorkflowOperation("rollback"));
    await expect(client.listHostBackups()).resolves.toHaveLength(1);
    await expect(client.listRedisBackups()).resolves.toHaveLength(1);
    await expect(client.listRuntimeDataBackups()).resolves.toHaveLength(1);
    await expect(client.rollbackBackup({ backup: { kind: "localPath", value: "/tmp/backup" } })).resolves.toEqual(commandResponse());
    await expect(client.deleteUpdateBackup({ backup: { kind: "localPath", value: "/tmp/backup" } })).resolves.toEqual(commandResponse());
    await expect(client.deleteRuntimeDataBackup({ backup: { kind: "localPath", value: "/tmp/runtime-data" } })).resolves.toEqual(commandResponse());
    await expect(client.restoreRedisBackup({ backup: { kind: "localPath", value: "/tmp/redis" } })).resolves.toEqual(commandResponse());
    await expect(client.restoreRuntimeDataBackup({ backup: { kind: "localPath", value: "/tmp/runtime-data" } })).resolves.toEqual(commandResponse());
    await expect(client.createRedisBackup()).resolves.toEqual(commandResponse());
    await expect(client.createRuntimeDataBackup()).resolves.toEqual(commandResponse());
    await expect(client.restartRuntimeProvider()).resolves.toEqual(
      runtimeProviderCommandResponse()
    );
    await expect(client.repairDatastore()).resolves.toEqual(
      guestServiceOperation("repair-datastore", "datastore-repair")
    );
  });

  it("throws API, contract, and network errors", async () => {
    const api = clientWithResponses({ "/platform": { message: "nope" } }, 500);
    await expect(api.client.getPlatformState()).rejects.toBeInstanceOf(RuntimeControlAPIError);

    const logContract = clientWithResponses({ "/platform/logs/read": {} });
    await expect(
      logContract.client.readLogs({ source: "containers", helperMessage: null, lineLimit: 100 })
    ).rejects.toBeInstanceOf(RuntimeControlContractError);

    const exportContract = clientWithResponses({ "/platform/logs/export": {} });
    await expect(
      exportContract.client.exportLogs({ destination: { kind: "localPath", value: "/tmp/logs.zip" } })
    ).rejects.toBeInstanceOf(RuntimeControlContractError);

    const updateSummaryContract = clientWithResponses({ "/platform/update-bundles/summary": {} });
    await expect(
      updateSummaryContract.client.summarizeUpdateBundle({
        bundle: { kind: "localPath", value: "/tmp/u.zip" }
      })
    ).rejects.toBeInstanceOf(RuntimeControlContractError);

    const network = new RuntimeControlApiClient({
      baseURL: "http://helper.local/",
      fetchImpl: vi.fn(async () => {
        throw new Error("offline");
      }) as typeof fetch
    });
    await expect(network.getPlatformState()).rejects.toBeInstanceOf(RuntimeControlNetworkError);
  });

  it("keeps PWA API contract chaos failures typed by boundary", async () => {
    const api = clientWithResponses(
      { "/platform": { code: "handlerFailed", message: "permission denied" } },
      500
    );
    await expect(api.client.getPlatformState()).rejects.toMatchObject({
      kind: "api",
      status: 500,
      body: JSON.stringify({ code: "handlerFailed", message: "permission denied" })
    });

    const contract = clientWithResponses({
      "/platform": { runtimeInstallationState: "executable", services: platformServices(), platformHealth: 42 }
    });
    await expect(contract.client.getPlatformState()).rejects.toMatchObject({
      kind: "contract",
      path: "/platform"
    });

    const network = new RuntimeControlApiClient({
      baseURL: "http://helper.local/",
      fetchImpl: vi.fn(async () => {
        throw new TypeError("fetch failed");
      }) as typeof fetch
    });
    await expect(network.getPlatformState()).rejects.toMatchObject({
      kind: "network",
      url: "http://helper.local/platform"
    });

    const summary = summarizeRuntimeControlError(
      new RuntimeControlContractError("/platform", new Error("invalid shape"))
    );
    expect(summary).toMatchObject({
      kind: "contract",
      title: "Runtime Control API contract mismatch"
    });
  });
});

function clientWithResponses(
  responses: Record<string, unknown>,
  status = 200
): { client: RuntimeControlApiClient; requests: RecordedRequest[] } {
  const requests: RecordedRequest[] = [];
  const fetchImpl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const path = new URL(url).pathname;
    const method = init?.method ?? "GET";
    requests.push({ url, init: init ?? {} });
    return new Response(JSON.stringify(responses[`${method} ${path}`] ?? responses[path] ?? commandResponse()), {
      status,
      headers: { "Content-Type": "application/json" }
    });
  }) as typeof fetch;

  return {
    client: new RuntimeControlApiClient({
      baseURL: "http://helper.local/",
      token: "token-a",
      fetchImpl
    }),
    requests
  };
}

function fullCapabilities() {
  return {
    canInstallRuntime: true,
    canUninstallRuntime: true,
    canApplyBundle: true,
    canRollback: true,
    canRollbackRelease: true,
    canEditRuntimeProviderResources: true,
    canEditNetworkExposure: true,
    canResetAdminPassword: true,
    canOpenLocalFiles: true,
    canStreamLogs: true,
    canControlRuntimeServices: true,
    canControlGuestServices: true,
    canExportLogs: true,
    canViewReleaseMetadata: true,
    canUseLab: true,
    canListLabSessions: true,
    canControlLabRecorders: true
  };
}

function platformCapabilities() {
  const {
    canControlGuestServices: _,
    canUseLab: __,
    canListLabSessions: ___,
    canControlLabRecorders: ____,
    ...platform
  } = fullCapabilities();
  return platform;
}

function fullSettings(overrides: Partial<ReturnType<typeof fullSettingsShape>> = {}) {
  return {
    ...fullSettingsShape(),
    ...overrides
  };
}

function productSettings() {
  const settings = fullSettings({ publicPort: 80 });
  return {
    automaticBackupEnabled: settings.automaticBackupEnabled,
    backupRetentionCount: settings.backupRetentionCount,
    backupScheduleTimes: settings.backupScheduleTimes,
    containerMemoryLimitsEnabled: settings.containerMemoryLimitsEnabled,
    publicHost: settings.publicHost,
    publicPort: settings.publicPort,
    recorderIngress: settings.recorderIngress,
    recorderIngressContainerMemoryLimitMiB:
      settings.recorderIngressContainerMemoryLimitMiB,
    recorderIngressSendDataMode: settings.recorderIngressSendDataMode,
    recorderIngressSendDataReplayBatchSize:
      settings.recorderIngressSendDataReplayBatchSize,
    recorderIngressSendDataReplayMaxMiBPerSecond:
      settings.recorderIngressSendDataReplayMaxMiBPerSecond,
    redisContainerMemoryLimitMiB: settings.redisContainerMemoryLimitMiB,
    remoteConsoleURL: settings.remoteConsoleURL,
    vitalServerContainerMemoryLimitMiB:
      settings.vitalServerContainerMemoryLimitMiB,
    vitalServerURL: settings.vitalServerURL
  };
}

function runtimeSettingsOperation(
  command:
    | "apply-settings"
    | "apply-admin-password"
    | "apply-redis-relay-settings" = "apply-settings",
  service = "runtime-settings"
) {
  return {
    operationId: "op_settings_1",
    service,
    command,
    state: "completed",
    createdAt: "2026-07-01T00:00:00Z",
    updatedAt: "2026-07-01T00:00:01Z"
  };
}

function platformServices() {
  return [
    { role: "runtime-provider", state: "running", readError: null },
    { role: "public-proxy", state: "running", readError: null },
    { role: "log-sync", state: "running", readError: null },
    { role: "sleep-prevention", state: "running", readError: null },
    { role: "watchdog", state: "running", readError: null }
  ];
}

function fullSettingsShape() {
  return {
    readIssues: [],
    cpuCount: 2,
    memoryGiB: 4,
    diskGiB: 32,
    minimumDiskGiB: 4,
    networkMode: "shared" as const,
    bridgedInterface: "" as string | null,
    proxyPort: 80,
    runtimeControlPort: 18321,
    vitalFilesDirectory: "/Users/shared/vital",
    vitalServerURL: "http://127.0.0.1:80/",
    remoteConsoleURL: "http://127.0.0.1:18321/",
    publicHost: "",
    publicPort: 80,
    recorderIngressSendDataMode: "spool_and_replay" as const,
    recorderIngressSendDataReplayBatchSize: 10,
    recorderIngressSendDataReplayMaxMiBPerSecond: 20,
    recorderIngress: recorderIngressSettings(),
    containerMemoryLimitsEnabled: true,
    vitalServerContainerMemoryLimitMiB: 4096,
    recorderIngressContainerMemoryLimitMiB: 512,
    redisContainerMemoryLimitMiB: 1024,
    adminPassword: "",
    changeAdminPassword: false,
    startOnBoot: true,
    startOnBootConfigurable: true,
    autoRecoveryEnabled: true,
    preventSystemSleep: true,
    automaticBackupEnabled: true,
    backupScheduleTimes: ["03:15"],
    backupRetentionCount: 30,
    logArchiveRetentionDays: 14,
    logArchiveMaximumGiB: 1,
    redisRelay: {
      enabled: false,
      target: {
        url: "redis://redis.example:6379/0",
        username: "",
        password: "",
        clearPassword: false,
        passwordConfigured: false,
        tls: false
      },
      scope: "vital_reconstruction" as const,
      includeRecorderNetworkContext: false,
      intervalSeconds: 1,
      scanCount: 1000
    },
    restartAfterSave: true
  };
}

function recorderIngressSettings() {
  return {
    sendDataMaxPendingItems: 100000,
    sendDataMaxPendingMiB: 512,
    sendDataMaxPayloadMiB: 10,
    sendDataReplayedMaxItems: 10000,
    sendDataRealtimeMaxPendingItems: 2000,
    sendDataReplayIntervalMs: 1000,
    sendDataReplayMaxAttempts: 3,
    sendDataReplayTargetTimeoutMs: 5000,
    sendDataReplayAdaptiveMinConcurrency: 1,
    sendDataReplayAdaptiveMaxConcurrency: 8,
    rawArchiveEnabled: true,
    rawArchiveMaxFileMiB: 512,
    rawArchiveMaxFiles: 24,
    rawArchiveAutoExportEnabled: true,
    rawArchiveAutoExportQuietSeconds: 300,
    rawArchiveAutoExportScanIntervalSeconds: 60,
    rawArchiveAutoExportCursorStableSeconds: 60,
    rawArchiveAutoExportRetryDelaySeconds: 60,
    rawArchiveAutoExportMaxAttempts: 3,
    rawArchiveAutoExportRequestTimeoutSeconds: 300
  };
}

function commandResponse() {
  return {
    result: {
      exitCode: 0,
      stdout: "ok",
      stderr: "",
      outputIssues: [],
      executionIssue: null
    }
  };
}

function platformWorkflowOperation(kind: "update-verify" | "update-apply" | "rollback" | "uninstall") {
  return {
    schemaVersion: 1,
    operationId: `${kind}-1`,
    kind,
    state: "completed" as const,
    startedAt: "2026-07-01T00:00:00Z",
    updatedAt: "2026-07-01T00:00:01Z",
    release: null,
    artifact: null,
    failure: null
  };
}

function guestServiceOperation(
  command: "start" | "stop" | "restart" | "repair-datastore",
  service = "app"
) {
  return {
    operationId: `${command}-${service}`,
    service,
    command,
    state: "completed" as const,
    createdAt: "2026-07-01T00:00:00+00:00",
    updatedAt: "2026-07-01T00:00:01+00:00",
    failure: null
  };
}

function runtimeProviderCommandResponse(state: "completed" | "failed" = "completed") {
  return {
    operationId: "provider-restart-1",
    action: "restart" as const,
    state,
    provider: {
      state: "missing" as const,
      document: null,
      readError: null
    },
    failure:
      state === "failed"
        ? {
            kind: "systemd-restart-failed",
            message: "systemd could not restart vitalserver"
          }
        : null
  };
}

function guestServiceResource() {
  return {
    service: "app",
    spec: {
      state: "configured",
      desiredState: "running",
      updatedAt: "2026-07-01T00:00:00+00:00"
    },
    status: {
      state: "loaded",
      observedState: "running",
      observedAt: "2026-07-01T00:00:01+00:00",
      serviceStatus: {
        service: "app",
        state: "running",
        health: "healthy",
        observedAt: "2026-07-01T00:00:01+00:00"
      }
    },
    conditions: [
      {
        type: "Reconciled",
        status: "true",
        reason: "DesiredStateObserved",
        message: "matched desired state",
        observedAt: "2026-07-01T00:00:01+00:00"
      }
    ],
    lastOperationId: "op-app"
  };
}

function labSessionResponse() {
  return {
    state: "loaded" as const,
    operationId: "op-1",
    labOperationId: "lab-op-1",
    readError: null,
    session: {
      sessionId: "lab-1",
      state: "accepted" as const,
      scenarioId: "baseline",
      name: "Lab A",
      recorderCount: 2,
      targetURL: "http://edge/",
      createdAt: null,
      updatedAt: null
    }
  };
}

function labRecorderResponse(state: "running" | "stopped") {
  return {
    state: "loaded" as const,
    operationId: `op-recorder-${state}`,
    labOperationId: `lab-op-recorder-${state}`,
    readError: null,
    recorder: {
      recorderId: "lab-1-recorder-1",
      sessionId: "lab-1",
      bedId: "lab-1-bed-1",
      vrcode: "LAB-lab-1-1",
      state,
      messagesSent: 1,
      lastSendState: "sent" as const
    }
  };
}

function fullVitalRecorderHistory() {
  return {
    state: "loaded",
    updatedAt: null,
    recorders: [],
    beds: [],
    summary: {
      knownRecorders: 0,
      currentRecorders: 0,
      onlineRecorders: 0,
      staleRecorders: 0,
      recorderAnomalies: 0,
      knownBeds: 0,
      onlineBeds: 0,
      staleBeds: 0,
      bedAssignments: 0,
      bedAnomalies: 0
    },
    activityHistory: {
      source: "notProvided",
      bucketCount: 0,
      earliestBucketStartedAt: null,
      latestBucketStartedAt: null,
      readError: null
    },
    recorderIngressStatusRead: null,
    readError: null
  };
}

function fullVitalBedHistory() {
  return {
    state: "loaded",
    updatedAt: null,
    beds: [],
    summary: {
      knownBeds: 0,
      onlineBeds: 0,
      staleBeds: 0,
      bedAssignments: 0,
      bedAnomalies: 0
    },
    readError: null
  };
}
