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
  it("sends authenticated GET requests with query parameters", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/events": { events: [], nextCursor: null, matchingCount: 0 }
    });

    await expect(client.getRuntimeEvents({ limit: 5, type: "update" })).resolves.toEqual({
      events: [],
      nextCursor: null,
      matchingCount: 0
    });

    expect(requests[0]?.url).toBe(
      "http://helper.local/runtime/events?limit=5&type=update"
    );
    expect(requests[0]?.init.method).toBe("GET");
    expect(requests[0]?.init.headers).toMatchObject({
      Accept: "application/json",
      "X-Runtime-Control-Token": "token-a"
    });
  });

  it("sends JSON bodies for runtime command endpoints", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/settings": commandResponse(),
      "/runtime/uninstall": commandResponse(),
      "/runtime/services/repair-proxy": commandResponse(),
      "DELETE /host/backups/update": commandResponse(),
      "DELETE /host/backups/vitalserver-helper": commandResponse()
    });

    await client.applySettings({ settings: fullSettings({ proxyPort: 18080 }) });
    await client.uninstallRuntime({ mode: "clean" });
    await client.repairProxy(18080);
    await client.deleteUpdateBackup({ backup: { kind: "localPath", value: "/tmp/update" } });
    await client.deleteRuntimeDataBackup({
      backup: { kind: "localPath", value: "/tmp/runtime-data" }
    });

    expect(requests.map((request) => request.init.method)).toEqual([
      "PUT",
      "POST",
      "POST",
      "DELETE",
      "DELETE"
    ]);
    expect(JSON.parse(String(requests[0]?.init.body))).toEqual({
      settings: fullSettings({ proxyPort: 18080 })
    });
    expect(JSON.parse(String(requests[2]?.init.body))).toEqual({
      proxyPort: 18080
    });
    expect(requests[0]?.init.headers).toMatchObject({
      "Content-Type": "application/json"
    });
  });

  it("keeps absent JSON bodies distinct from explicit JSON command payloads", async () => {
    const { client, requests } = clientWithResponses({
      "/runtime/redis/backups": commandResponse(),
      "/runtime/services/repair-proxy": commandResponse()
    });

    await client.createRedisBackup();
    await client.repairProxy(18080);

    expect(requests[0]?.init.body).toBeUndefined();
    expect(requests[0]?.init.headers).not.toMatchObject({
      "Content-Type": "application/json"
    });
    expect(JSON.parse(String(requests[1]?.init.body))).toEqual({
      proxyPort: 18080
    });
    expect(requests[1]?.init.headers).toMatchObject({
      "Content-Type": "application/json"
    });
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

  it("covers read endpoints and host affordance endpoints", async () => {
    const { client } = clientWithResponses({
      "/runtime/capabilities": fullCapabilities(),
      "/runtime/overview": fullRuntimeOverview(),
      "/runtime/status": { runtimeState: "healthy" },
      "/runtime/operation-state": {
        activeOperation: "apply-bundle",
        runtimeStatusUpdatedAt: "2026-07-08T00:00:00Z",
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
      "/runtime/settings": fullSettings({ proxyPort: 80 }),
      "/lab/scenarios": {
        state: "loaded",
        scenarios: [{ scenarioId: "baseline", name: "Baseline", category: "generated" }],
        readError: null
      },
      "/lab/beds": {
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
      "/lab/recorders": {
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
      "/lab/sessions": labSessionResponse(),
      "/lab/sessions/lab-1": labSessionResponse(),
      "/lab/sessions/lab-1/start": labSessionResponse(),
      "/lab/sessions/lab-1/stop": labSessionResponse(),
      "/lab/vital-files": {
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
      "/lab/vital-files/upload": {
        state: "loaded",
        upload: null,
        operationId: "lab-vital-file-upload",
        labOperationId: null,
        readError: null
      },
      "/lab/vital-files/replay": labSessionResponse(),
      "/runtime/guest/stack/status": {
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
      "/runtime/guest/services/start": guestServiceOperation("start"),
      "/runtime/guest/services/stop": guestServiceOperation("stop"),
      "/runtime/guest/services/restart": guestServiceOperation("restart"),
      "/vitaldb/recorders": fullVitalRecorderHistory(),
      "/vitaldb/recorders/hide": fullVitalRecorderHistory(),
      "/vitaldb/recorders/unhide": fullVitalRecorderHistory(),
      "/vitaldb/recorders/delete": fullVitalRecorderHistory(),
      "/vitaldb/beds": [],
      "/vitaldb/beds/hide": fullVitalRecorderHistory(),
      "/vitaldb/beds/unhide": fullVitalRecorderHistory(),
      "/vitaldb/beds/delete": fullVitalRecorderHistory(),
      "/vitaldb/relationships": {
        state: "loaded",
        assignments: [],
        events: [],
        readError: null
      },
      "/host/logs/read": { text: "log" },
      "/host/logs/export": { destination: "file:///tmp/logs.zip" },
      "/host/update-bundles/summary": { summary: "ok" },
      "/host/update-bundles/verify": commandResponse(),
      "/host/update-bundles/apply": commandResponse(),
      "/host/backups": [{ path: "/tmp/backup", sizeBytes: 1 }],
      "/host/backups/redis": [{ path: "/tmp/redis", sizeBytes: null }],
      "/host/backups/vitalserver-helper": [{ path: "/tmp/runtime-data", sizeBytes: 10 }],
      "/host/backups/rollback": commandResponse(),
      "DELETE /host/backups/update": commandResponse(),
      "DELETE /host/backups/vitalserver-helper": commandResponse(),
      "/host/backups/redis/restore": commandResponse(),
      "/host/backups/vitalserver-helper/restore": commandResponse(),
      "/runtime/redis/backups": commandResponse(),
      "/runtime/data/backups": commandResponse(),
      "/runtime/services/repair-runtime": commandResponse(),
      "/runtime/services/repair-datastore": commandResponse(),
      "/runtime/services/repair-vm-disk": commandResponse()
    });

    await expect(client.getCapabilities()).resolves.toMatchObject({ canUseLab: true });
    await expect(client.getOverview()).resolves.toMatchObject({ status: { runtimeState: "healthy" } });
    await expect(client.getStatus()).resolves.toMatchObject({ runtimeState: "healthy" });
    await expect(client.getOperationState()).resolves.toMatchObject({
      activeOperation: "apply-bundle",
      lease: { state: "stale", staleReason: "expired" }
    });
    await expect(client.getSettings()).resolves.toMatchObject({ proxyPort: 80 });
    await expect(client.getLabScenarios()).resolves.toMatchObject({ state: "loaded" });
    await expect(client.getLabBeds()).resolves.toMatchObject({ beds: [{ name: "OR-A" }] });
    await expect(client.getLabRecorders()).resolves.toMatchObject({
      recorders: [{ vrcode: "LAB-lab-1-1", messagesSent: 1, lastSendState: "sent" }]
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
    await expect(client.getLabVitalFiles()).resolves.toMatchObject({
      vitalFiles: [{ displayName: "case.vital" }]
    });
    await expect(client.uploadLabVitalFile({
      vitalFilePath: "/mnt/tirosh-vital-files/case.vital",
      targetURL: "http://edge/",
      endpoint: null,
      vrcode: null
    })).resolves.toMatchObject({ state: "loaded" });
    await expect(client.replayLabVitalFile({
      vitalFilePath: "/mnt/tirosh-vital-files/sample.vital",
      sessionName: "Replay",
      targetURL: null
    })).resolves.toMatchObject({ session: { sessionId: "lab-1" } });
    await expect(client.getGuestStackStatus()).resolves.toMatchObject({
      state: "loaded",
      services: [{ service: "app" }]
    });
    await expect(client.startGuestService({ service: "app" })).resolves.toMatchObject({ command: "start" });
    await expect(client.stopGuestService({ service: "app" })).resolves.toMatchObject({ command: "stop" });
    await expect(client.restartGuestService({ service: "app" })).resolves.toMatchObject({ command: "restart" });
    await expect(client.getRecorders()).resolves.toMatchObject({ recorders: [] });
    await expect(client.hideRecorders({ vrcodes: ["VR_A"] })).resolves.toMatchObject({ recorders: [] });
    await expect(client.unhideRecorders({ vrcodes: ["VR_A"] })).resolves.toMatchObject({ recorders: [] });
    await expect(client.deleteRecorders({ vrcodes: ["VR_A"] })).resolves.toMatchObject({ recorders: [] });
    await expect(client.getBeds()).resolves.toEqual([]);
    await expect(client.hideBeds({ bedIDs: ["bed-a"] })).resolves.toMatchObject({ beds: [] });
    await expect(client.unhideBeds({ bedIDs: ["bed-a"] })).resolves.toMatchObject({ beds: [] });
    await expect(client.deleteBeds({ bedIDs: ["bed-a"] })).resolves.toMatchObject({ beds: [] });
    await expect(client.getRelationships()).resolves.toMatchObject({ assignments: [] });
    await expect(client.readLogs({ source: "containers", helperMessage: "", lineLimit: 100 })).resolves.toEqual({ text: "log" });
    await expect(client.exportLogs({ destination: { kind: "localPath", value: "/tmp/logs.zip" } })).resolves.toEqual({ destination: "file:///tmp/logs.zip" });
    await expect(client.summarizeUpdateBundle({ bundle: { kind: "localPath", value: "/tmp/u.zip" } })).resolves.toEqual({ summary: "ok" });
    await expect(client.verifyUpdateBundle({ bundle: { kind: "localPath", value: "/tmp/u.zip" } })).resolves.toEqual(commandResponse());
    await expect(client.applyUpdateBundle({ bundle: { kind: "localPath", value: "/tmp/u.zip" } })).resolves.toEqual(commandResponse());
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
    await expect(client.repairRuntime()).resolves.toEqual(commandResponse());
    await expect(client.repairDatastore()).resolves.toEqual(commandResponse());
    await expect(client.repairVMDisk()).resolves.toEqual(commandResponse());
  });

  it("accepts explicit null bridged interface in runtime overview settings", async () => {
    const { client } = clientWithResponses({
      "/runtime/overview": {
        ...fullRuntimeOverview(),
        settings: fullSettings({ bridgedInterface: null })
      }
    });

    await expect(client.getOverview()).resolves.toMatchObject({
      settings: {
        bridgedInterface: null
      }
    });
  });

  it("throws API, contract, and network errors", async () => {
    const api = clientWithResponses({ "/runtime/status": { message: "nope" } }, 500);
    await expect(api.client.getStatus()).rejects.toBeInstanceOf(RuntimeControlAPIError);

    const logContract = clientWithResponses({ "/host/logs/read": {} });
    await expect(
      logContract.client.readLogs({ source: "containers", helperMessage: null, lineLimit: 100 })
    ).rejects.toBeInstanceOf(RuntimeControlContractError);

    const exportContract = clientWithResponses({ "/host/logs/export": {} });
    await expect(
      exportContract.client.exportLogs({ destination: { kind: "localPath", value: "/tmp/logs.zip" } })
    ).rejects.toBeInstanceOf(RuntimeControlContractError);

    const updateSummaryContract = clientWithResponses({ "/host/update-bundles/summary": {} });
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
    await expect(network.getStatus()).rejects.toBeInstanceOf(RuntimeControlNetworkError);
  });

  it("keeps PWA API contract chaos failures typed by boundary", async () => {
    const api = clientWithResponses(
      { "/runtime/status": { code: "handlerFailed", message: "permission denied" } },
      500
    );
    await expect(api.client.getStatus()).rejects.toMatchObject({
      kind: "api",
      status: 500,
      body: JSON.stringify({ code: "handlerFailed", message: "permission denied" })
    });

    const contract = clientWithResponses({ "/runtime/status": { runtimeState: 42 } });
    await expect(contract.client.getStatus()).rejects.toMatchObject({
      kind: "contract",
      path: "/runtime/status"
    });

    const network = new RuntimeControlApiClient({
      baseURL: "http://helper.local/",
      fetchImpl: vi.fn(async () => {
        throw new TypeError("fetch failed");
      }) as typeof fetch
    });
    await expect(network.getStatus()).rejects.toMatchObject({
      kind: "network",
      url: "http://helper.local/runtime/status"
    });

    const summary = summarizeRuntimeControlError(
      new RuntimeControlContractError("/runtime/status", new Error("invalid shape"))
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
    canEditVMResources: true,
    canEditNetworkExposure: true,
    canResetAdminPassword: true,
    canOpenLocalFiles: true,
    canStreamLogs: true,
    canControlRuntimeServices: true,
    canControlGuestServices: true,
    canExportLogs: true,
    canViewReleaseMetadata: true,
    canUseLab: true
  };
}

function fullSettings(overrides: Partial<ReturnType<typeof fullSettingsShape>> = {}) {
  return {
    ...fullSettingsShape(),
    ...overrides
  };
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

function fullRuntimeOverview() {
  return {
    status: {
      runtimeState: "healthy"
    },
    settings: fullSettings(),
    release: {},
    install: {},
    vitalDBObservation: null,
    vitalDBObservationSnapshot: {
      state: "unavailable",
      observation: null,
      readError: null
    },
    vitalRecorder: {
      source: "unavailable",
      observedAt: null,
      latestRecorder: null
    },
    conditions: [
      {
        type: "VitalDBObservationReady",
        status: "Unknown",
        reason: "Unavailable",
        message: null,
        observedAt: null
      }
    ]
  };
}

function commandResponse() {
  return { result: { exitCode: 0, stdout: "ok", stderr: "" } };
}

function guestServiceOperation(command: "start" | "stop" | "restart") {
  return {
    operationId: `${command}-app`,
    service: "app",
    command,
    state: "completed" as const,
    createdAt: "2026-07-01T00:00:00+00:00",
    updatedAt: "2026-07-01T00:00:01+00:00",
    failure: null
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
