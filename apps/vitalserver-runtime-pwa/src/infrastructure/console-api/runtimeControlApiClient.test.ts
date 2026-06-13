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
      "DELETE /host/backups/runtime-data": commandResponse()
    });

    await client.applySettings({ settings: fullSettings({ proxyPort: 18080 }) });
    await client.uninstallRuntime({ clean: true });
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
      "/runtime/services/start": commandResponse(),
      "/runtime/services/repair-proxy": commandResponse()
    });

    await client.startRuntimeServices();
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
    const session = testKitSession();
    const { client } = clientWithResponses({
      "/runtime/capabilities": fullCapabilities(),
      "/runtime/overview": fullRuntimeOverview(),
      "/runtime/status": { runtimeState: "healthy" },
      "/runtime/settings": fullSettings({ proxyPort: 80 }),
      "/vitaldb/recorders": fullVitalRecorderHistory(),
      "/vitaldb/beds": [],
      "/vitaldb/relationships": {
        state: "loaded",
        assignments: [],
        events: [],
        readError: null
      },
      "/dev/testkit/status": testKitStatus(),
      "/dev/testkit/beds/create": [{ roomName: "OR-A", bedId: "bed-a" }],
      "/dev/testkit/beds/delete": [{ roomName: "OR-A", bedId: "bed-a" }],
      "/dev/testkit/beds/reset": [],
      "/dev/testkit/virtual-recorders/start": session,
      "/dev/testkit/virtual-recorders/stop": session,
      "/dev/testkit/virtual-recorders/pause": session,
      "/dev/testkit/virtual-recorders/resume": session,
      "/dev/testkit/virtual-recorders/restart": session,
      "/dev/testkit/virtual-recorders/delete": session,
      "/dev/testkit/virtual-recorders/reset": testKitStatus(),
      "/dev/testkit/virtual-recorders/delete-orphan": {
        vrcode: "VR_A",
        targetUrl: "http://edge/",
        deleted: true,
        error: null
      },
      "/host/logs/read": { text: "log" },
      "/host/logs/export": { destination: "file:///tmp/logs.zip" },
      "/host/update-bundles/summary": { summary: "ok" },
      "/host/update-bundles/verify": commandResponse(),
      "/host/update-bundles/apply": commandResponse(),
      "/host/backups": [{ path: "/tmp/backup", sizeBytes: 1 }],
      "/host/backups/redis": [{ path: "/tmp/redis", sizeBytes: null }],
      "/host/backups/runtime-data": [{ path: "/tmp/runtime-data", sizeBytes: 10 }],
      "/host/backups/rollback": commandResponse(),
      "DELETE /host/backups/update": commandResponse(),
      "DELETE /host/backups/runtime-data": commandResponse(),
      "/host/backups/redis/restore": commandResponse(),
      "/host/backups/runtime-data/restore": commandResponse(),
      "/runtime/redis/backups": commandResponse(),
      "/runtime/data/backups": commandResponse(),
      "/runtime/services/start": commandResponse(),
      "/runtime/services/stop": commandResponse(),
      "/runtime/services/repair-runtime": commandResponse(),
      "/runtime/services/repair-datastore": commandResponse(),
      "/runtime/services/repair-vm-disk": commandResponse()
    });

    await expect(client.getCapabilities()).resolves.toMatchObject({ canUseTestTools: true });
    await expect(client.getOverview()).resolves.toMatchObject({ status: { runtimeState: "healthy" } });
    await expect(client.getStatus()).resolves.toMatchObject({ runtimeState: "healthy" });
    await expect(client.getSettings()).resolves.toMatchObject({ proxyPort: 80 });
    await expect(client.getRecorders()).resolves.toMatchObject({ recorders: [] });
    await expect(client.getBeds()).resolves.toEqual([]);
    await expect(client.getRelationships()).resolves.toMatchObject({ assignments: [] });
    await expect(client.getTestKitStatus()).resolves.toMatchObject({ enabled: true });
    await expect(client.createTestKitBeds({ count: 1, roomNames: [], prefix: "OR", adminUserId: "admin" })).resolves.toHaveLength(1);
    await expect(client.deleteTestKitBeds({ roomNames: ["OR-A"] })).resolves.toHaveLength(1);
    await expect(client.resetTestKitBeds()).resolves.toEqual([]);
    await expect(client.startTestKitVirtualRecorders(testKitStartRequest())).resolves.toMatchObject({ id: "s1" });
    await expect(client.stopTestKitVirtualRecorders({ sessionID: "s1" })).resolves.toMatchObject({ id: "s1" });
    await expect(client.pauseTestKitVirtualRecorders({ sessionID: "s1" })).resolves.toMatchObject({ id: "s1" });
    await expect(client.resumeTestKitVirtualRecorders({ sessionID: "s1" })).resolves.toMatchObject({ id: "s1" });
    await expect(client.restartTestKitVirtualRecorders({ sessionID: "s1", bedRoomNames: ["OR-A"] })).resolves.toMatchObject({ id: "s1" });
    await expect(client.deleteTestKitVirtualRecorders({ sessionID: "s1" })).resolves.toMatchObject({ id: "s1" });
    await expect(client.resetTestKitVirtualRecorders()).resolves.toMatchObject({ enabled: true });
    await expect(client.deleteTestKitOrphanVRecorder({ vrcode: "VR_A" })).resolves.toMatchObject({ deleted: true });
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
    await expect(client.startRuntimeServices()).resolves.toEqual(commandResponse());
    await expect(client.stopRuntimeServices()).resolves.toEqual(commandResponse());
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

    const contract = clientWithResponses({ "/dev/testkit/status": { enabled: true } });
    await expect(contract.client.getTestKitStatus()).rejects.toBeInstanceOf(
      RuntimeControlContractError
    );

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
    canExportLogs: true,
    canViewReleaseMetadata: true,
    canUseTestTools: true
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
    adminPassword: "",
    changeAdminPassword: false,
    startOnBoot: true,
    startOnBootConfigurable: true,
    autoRecoveryEnabled: true,
    preventSystemSleep: true,
    redisBackupRetentionCount: 30,
    restartAfterSave: true
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
    }
  };
}

function commandResponse() {
  return { result: { exitCode: 0, stdout: "ok", stderr: "" } };
}

function fullVitalRecorderHistory() {
  return {
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
    readError: null
  };
}

function testKitStartRequest() {
  return {
    scenario: "normal" as const,
    signalProfile: "normal" as const,
    recorders: 1,
    bedRoomNames: ["OR-A"],
    vrcode: "VR_A",
    version: "testkit",
    intervalSeconds: 1,
    durationSeconds: null,
    maxMessages: null,
    shiftTime: true,
    generateFrames: true
  };
}

function testKitStatus() {
  return {
    enabled: true,
    state: "running",
    serviceName: "testkit",
    apiBaseURL: "http://testkit.local",
    recorderTargetURL: "http://edge/",
    startedAt: null,
    activeSession: null,
    sessions: [],
    beds: [],
    lastError: null
  };
}

function testKitSession() {
  return {
    id: "s1",
    state: "running",
    targetUrl: "http://edge/",
    recordersRequested: 1,
    bedsRequested: 1,
    bedRoomNames: ["OR-A"],
    vrcode: "VR_A",
    version: "testkit",
    intervalSeconds: 1,
    durationSeconds: null,
    maxMessages: null,
    shiftTime: true,
    generateFrames: true,
    scenario: "normal",
    defaultScenario: "normal",
    createdAt: null,
    startedAt: null,
    stoppedAt: null,
    messagesSent: 0,
    bytesSent: 0,
    lastError: null,
    cleanupErrors: [],
    recorders: []
  };
}
