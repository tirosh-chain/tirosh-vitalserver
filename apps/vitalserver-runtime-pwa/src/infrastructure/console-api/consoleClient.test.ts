import { describe, expect, it, vi } from "vitest";

import { RuntimeControlAPIError, RuntimeControlContractError, RuntimeControlNetworkError } from "@/domain/runtime-control/errors/runtimeControlError";
import { ConsoleClient } from "./consoleClient";

type RecordedRequest = {
  url: string;
  init: RequestInit;
};

describe("ConsoleClient", () => {
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
      "/host/backups": commandResponse()
    });

    await client.applySettings({ settings: { proxyPort: 18080 } });
    await client.uninstallRuntime({ clean: true });
    await client.repairProxy(18080);
    await client.deleteHostBackup({ backup: { kind: "localPath", value: "/tmp/b" } });

    expect(requests.map((request) => request.init.method)).toEqual([
      "PUT",
      "POST",
      "POST",
      "DELETE"
    ]);
    expect(JSON.parse(String(requests[0]?.init.body))).toEqual({
      settings: { proxyPort: 18080 }
    });
    expect(JSON.parse(String(requests[2]?.init.body))).toEqual({
      proxyPort: 18080
    });
    expect(requests[0]?.init.headers).toMatchObject({
      "Content-Type": "application/json"
    });
  });

  it("covers read endpoints and host affordance endpoints", async () => {
    const session = testKitSession();
    const { client } = clientWithResponses({
      "/runtime/capabilities": { canUseTestTools: true },
      "/runtime/overview": { status: { runtimeState: "healthy" } },
      "/runtime/status": { runtimeState: "healthy" },
      "/runtime/settings": { proxyPort: 80 },
      "/vitaldb/recorders": { updatedAt: null, recorders: [], beds: [] },
      "/vitaldb/beds": [],
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
      "/host/backups/rollback": commandResponse(),
      "/host/backups/redis/restore": commandResponse(),
      "/runtime/redis/backups": commandResponse(),
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
    await expect(client.rollbackBackup({ backup: { kind: "localPath", value: "/tmp/backup" } })).resolves.toEqual(commandResponse());
    await expect(client.restoreRedisBackup({ backup: { kind: "localPath", value: "/tmp/redis" } })).resolves.toEqual(commandResponse());
    await expect(client.createRedisBackup()).resolves.toEqual(commandResponse());
    await expect(client.startRuntimeServices()).resolves.toEqual(commandResponse());
    await expect(client.stopRuntimeServices()).resolves.toEqual(commandResponse());
    await expect(client.repairRuntime()).resolves.toEqual(commandResponse());
    await expect(client.repairDatastore()).resolves.toEqual(commandResponse());
    await expect(client.repairVMDisk()).resolves.toEqual(commandResponse());
  });

  it("throws API, contract, and network errors", async () => {
    const api = clientWithResponses({ "/runtime/status": { message: "nope" } }, 500);
    await expect(api.client.getStatus()).rejects.toBeInstanceOf(RuntimeControlAPIError);

    const contract = clientWithResponses({ "/dev/testkit/status": { enabled: true } });
    await expect(contract.client.getTestKitStatus()).rejects.toBeInstanceOf(
      RuntimeControlContractError
    );

    const network = new ConsoleClient({
      baseURL: "http://helper.local/",
      fetchImpl: vi.fn(async () => {
        throw new Error("offline");
      }) as typeof fetch
    });
    await expect(network.getStatus()).rejects.toBeInstanceOf(RuntimeControlNetworkError);
  });
});

function clientWithResponses(
  responses: Record<string, unknown>,
  status = 200
): { client: ConsoleClient; requests: RecordedRequest[] } {
  const requests: RecordedRequest[] = [];
  const fetchImpl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const path = new URL(url).pathname;
    requests.push({ url, init: init ?? {} });
    return new Response(JSON.stringify(responses[path] ?? commandResponse()), {
      status,
      headers: { "Content-Type": "application/json" }
    });
  }) as typeof fetch;

  return {
    client: new ConsoleClient({
      baseURL: "http://helper.local/",
      token: "token-a",
      fetchImpl
    }),
    requests
  };
}

function commandResponse() {
  return { result: { exitCode: 0, stdout: "ok", stderr: "" } };
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
