import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { PropsWithChildren, ReactElement } from "react";
import { describe, expect, it, vi } from "vitest";

import { RuntimeControlGatewayProvider } from "@/console/runtimeControlGatewayContext";
import type { RuntimeControlGateway } from "./runtimeControlGateway";
import {
  useApplyRuntimeSettings,
  useApplyUpdateBundle,
  useCreateRedisBackup,
  useCreateRuntimeDataBackup,
  useCreateTestKitBeds,
  useDeleteHostBackup,
  useDeleteRuntimeDataBackup,
  useDeleteUpdateBackup,
  useDeleteTestKitBeds,
  useDeleteTestKitOrphanVRecorder,
  useExportHostLogs,
  useHostBackups,
  useHostLogs,
  useRedisBackups,
  useRepairDatastore,
  useRepairProxy,
  useRepairRuntime,
  useRepairVMDisk,
  useResetTestKitBeds,
  useResetTestKitVirtualRecorders,
  useRestartTestKitVirtualRecorders,
  useRollbackBackup,
  useRestoreRuntimeDataBackup,
  useRuntimeCapabilities,
  useRuntimeDataBackups,
  useRuntimeEvents,
  useRuntimeOverview,
  useRuntimeSettings,
  useSessionTestKitAction,
  useStartRuntimeServices,
  useStartTestKitVirtualRecorders,
  useStopRuntimeServices,
  useSummarizeUpdateBundle,
  useTestKitStatus,
  useUninstallRuntime,
  useVerifyUpdateBundle,
  useVitalDBBeds,
  useVitalDBRelationships,
  useVitalDBRecorders
} from "./hooks";

type GatewayMock = {
  [K in keyof RuntimeControlGateway]: ReturnType<typeof vi.fn>;
};

describe("console hooks", () => {
  it("reads runtime console queries through the gateway", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);

    await expectQuery(useRuntimeOverview, wrapper, gateway.getOverview);
    await expectQuery(useRuntimeCapabilities, wrapper, gateway.getCapabilities);
    await expectQuery(useRuntimeSettings, wrapper, gateway.getSettings);
    await expectQuery(useVitalDBRecorders, wrapper, gateway.getRecorders);
    await expectQuery(useVitalDBBeds, wrapper, gateway.getBeds);
    await expectQuery(useVitalDBRelationships, wrapper, gateway.getRelationships);
    await expectQuery(useTestKitStatus, wrapper, gateway.getTestKitStatus);
    await expectQuery(useHostBackups, wrapper, gateway.listHostBackups);
    await expectQuery(useRedisBackups, wrapper, gateway.listRedisBackups);
    await expectQuery(useRuntimeDataBackups, wrapper, gateway.listRuntimeDataBackups);

    const events = renderHook(
      () => useRuntimeEvents({ limit: 5, type: "update", since: "2026-05-31T00:00:00Z" }),
      { wrapper }
    );
    await waitFor(() => expect(events.result.current.data).toEqual({ events: [] }));
    expect(gateway.getRuntimeEvents).toHaveBeenCalledWith({
      limit: 5,
      type: "update",
      since: "2026-05-31T00:00:00Z"
    });

    const logs = renderHook(
      () => useHostLogs({ source: "containers", lineLimit: 100, live: false }),
      { wrapper }
    );
    await waitFor(() => expect(logs.result.current.data).toEqual({ text: "logs" }));
    expect(gateway.readLogs).toHaveBeenCalledWith({
      source: "containers",
      helperMessage: null,
      lineLimit: 100
    });
  });

  it("runs runtime, update, backup, and repair mutations through the gateway", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);

    await mutateHook(
      () => useApplyRuntimeSettings(),
      { settings: fullSettings({ proxyPort: 18080 }) },
      wrapper
    );
    expect(gateway.applySettings).toHaveBeenCalledWith({
      settings: fullSettings({ proxyPort: 18080 })
    });

    await mutateHook(() => useExportHostLogs(), "/tmp/logs.zip", wrapper);
    expect(gateway.exportLogs).toHaveBeenCalledWith({
      destination: { kind: "localPath", value: "/tmp/logs.zip" }
    });

    await mutateHook(() => useSummarizeUpdateBundle(), "/tmp/update.tar.gz", wrapper);
    await mutateHook(() => useVerifyUpdateBundle(), "/tmp/update.tar.gz", wrapper);
    await mutateHook(() => useApplyUpdateBundle(), "/tmp/update.tar.gz", wrapper);
    expect(gateway.summarizeUpdateBundle).toHaveBeenCalledWith({
      bundle: { kind: "localPath", value: "/tmp/update.tar.gz" }
    });
    expect(gateway.verifyUpdateBundle).toHaveBeenCalledWith({
      bundle: { kind: "localPath", value: "/tmp/update.tar.gz" }
    });
    expect(gateway.applyUpdateBundle).toHaveBeenCalledWith({
      bundle: { kind: "localPath", value: "/tmp/update.tar.gz" }
    });

    await mutateHook(() => useRollbackBackup(), "/tmp/backup", wrapper);
    await mutateHook(() => useDeleteHostBackup(), "/tmp/backup", wrapper);
    await mutateHook(() => useDeleteUpdateBackup(), "/tmp/update-backup", wrapper);
    await mutateHook(() => useDeleteRuntimeDataBackup(), "/tmp/runtime-data", wrapper);
    await mutateHook(() => useCreateRedisBackup(), "", wrapper);
    await mutateHook(() => useCreateRuntimeDataBackup(), "", wrapper);
    await mutateHook(() => useRestoreRuntimeDataBackup(), "/tmp/runtime-data", wrapper);
    expect(gateway.rollbackBackup).toHaveBeenCalledWith({
      backup: { kind: "localPath", value: "/tmp/backup" }
    });
    expect(gateway.deleteHostBackup).toHaveBeenCalledWith({
      backup: { kind: "localPath", value: "/tmp/backup" }
    });
    expect(gateway.deleteUpdateBackup).toHaveBeenCalledWith({
      backup: { kind: "localPath", value: "/tmp/update-backup" }
    });
    expect(gateway.deleteRuntimeDataBackup).toHaveBeenCalledWith({
      backup: { kind: "localPath", value: "/tmp/runtime-data" }
    });
    expect(gateway.createRedisBackup).toHaveBeenCalled();
    expect(gateway.createRuntimeDataBackup).toHaveBeenCalled();
    expect(gateway.restoreRuntimeDataBackup).toHaveBeenCalledWith({
      backup: { kind: "localPath", value: "/tmp/runtime-data" }
    });

    await mutateHook(() => useRepairRuntime(), undefined, wrapper);
    await mutateHook(() => useRepairProxy(), 18444, wrapper);
    await mutateHook(() => useRepairDatastore(), undefined, wrapper);
    await mutateHook(() => useRepairVMDisk(), undefined, wrapper);
    await mutateHook(() => useStartRuntimeServices(), undefined, wrapper);
    await mutateHook(() => useStopRuntimeServices(), undefined, wrapper);
    await mutateHook(() => useUninstallRuntime(), true, wrapper);
    expect(gateway.repairProxy).toHaveBeenCalledWith(18444);
    expect(gateway.uninstallRuntime).toHaveBeenCalledWith({ mode: "clean" });
  });

  it("runs TestKit mutations with decoded request payloads", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);

    await mutateHook(
      () => useCreateTestKitBeds(),
      { count: 2, prefix: "OR", roomNames: ["OR-1"] },
      wrapper
    );
    expect(gateway.createTestKitBeds).toHaveBeenCalledWith({
      count: 2,
      prefix: "OR",
      roomNames: ["OR-1"],
      adminUserId: "admin"
    });

    await mutateHook(() => useDeleteTestKitBeds(), ["OR-1"], wrapper);
    await mutateHook(() => useResetTestKitBeds(), undefined, wrapper);
    expect(gateway.deleteTestKitBeds).toHaveBeenCalledWith({ roomNames: ["OR-1"] });
    expect(gateway.resetTestKitBeds).toHaveBeenCalled();

    await mutateHook(() => useStartTestKitVirtualRecorders(), testKitStart(), wrapper);
    expect(gateway.startTestKitVirtualRecorders).toHaveBeenCalledWith(testKitStart());

    for (const action of ["stop", "pause", "resume", "delete"] as const) {
      await mutateHook(() => useSessionTestKitAction(action), "session-1", wrapper);
    }
    expect(gateway.stopTestKitVirtualRecorders).toHaveBeenCalledWith({
      sessionID: "session-1"
    });
    expect(gateway.pauseTestKitVirtualRecorders).toHaveBeenCalledWith({
      sessionID: "session-1"
    });
    expect(gateway.resumeTestKitVirtualRecorders).toHaveBeenCalledWith({
      sessionID: "session-1"
    });
    expect(gateway.deleteTestKitVirtualRecorders).toHaveBeenCalledWith({
      sessionID: "session-1"
    });

    await mutateHook(
      () => useRestartTestKitVirtualRecorders(),
      { sessionID: "session-1", bedRoomNames: ["OR-1"] },
      wrapper
    );
    await mutateHook(() => useResetTestKitVirtualRecorders(), undefined, wrapper);
    await mutateHook(() => useDeleteTestKitOrphanVRecorder(), "VR_A", wrapper);
    expect(gateway.restartTestKitVirtualRecorders).toHaveBeenCalledWith({
      sessionID: "session-1",
      bedRoomNames: ["OR-1"]
    });
    expect(gateway.resetTestKitVirtualRecorders).toHaveBeenCalled();
    expect(gateway.deleteTestKitOrphanVRecorder).toHaveBeenCalledWith({
      vrcode: "VR_A"
    });
  });
});

async function expectQuery(
  hook: () => unknown,
  wrapper: ({ children }: PropsWithChildren) => ReactElement,
  gatewayMethod: ReturnType<typeof vi.fn>
) {
  const rendered = renderHook(hook, { wrapper });
  await waitFor(() =>
    expect((rendered.result.current as { data?: unknown }).data).not.toBeUndefined()
  );
  expect(gatewayMethod).toHaveBeenCalled();
}

async function mutateHook<TVariables>(
  hook: () => { mutateAsync: (variables: TVariables) => Promise<unknown> },
  variables: TVariables,
  wrapper: ({ children }: PropsWithChildren) => ReactElement
) {
  const rendered = renderHook(hook, { wrapper });
  await act(async () => {
    await rendered.result.current.mutateAsync(variables);
  });
}

function createWrapper(gateway: GatewayMock) {
  const queryClient = new QueryClient({
    defaultOptions: {
      mutations: { retry: false },
      queries: { retry: false }
    }
  });
  return function Wrapper({ children }: PropsWithChildren) {
    return (
      <RuntimeControlGatewayProvider gateway={gateway as unknown as RuntimeControlGateway}>
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
      </RuntimeControlGatewayProvider>
    );
  };
}

function createGateway(): GatewayMock {
  const command = vi.fn().mockResolvedValue(commandResult);
  return {
    applySettings: vi.fn().mockResolvedValue(commandResult),
    applyUpdateBundle: vi.fn().mockResolvedValue(commandResult),
    createRedisBackup: vi.fn().mockResolvedValue(commandResult),
    createRuntimeDataBackup: vi.fn().mockResolvedValue(commandResult),
    createTestKitBeds: vi.fn().mockResolvedValue([]),
    deleteHostBackup: vi.fn().mockResolvedValue(commandResult),
    deleteRuntimeDataBackup: vi.fn().mockResolvedValue(commandResult),
    deleteUpdateBackup: vi.fn().mockResolvedValue(commandResult),
    deleteTestKitBeds: vi.fn().mockResolvedValue([]),
    deleteTestKitOrphanVRecorder: vi.fn().mockResolvedValue({ deleted: true }),
    deleteTestKitVirtualRecorders: vi.fn().mockResolvedValue(testKitSession()),
    exportLogs: vi.fn().mockResolvedValue({ destination: "file:///tmp/logs.zip" }),
    getBeds: vi.fn().mockResolvedValue([]),
    getCapabilities: vi.fn().mockResolvedValue(fullCapabilities()),
    getOverview: vi.fn().mockResolvedValue({ status: { runtimeState: "healthy" } }),
    getRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    getRelationships: vi.fn().mockResolvedValue({
      state: "loaded",
      assignments: [],
      events: [],
      readError: null
    }),
    getRuntimeEvents: vi.fn().mockResolvedValue({ events: [] }),
    getSettings: vi.fn().mockResolvedValue(fullSettings({ proxyPort: 18080 })),
    getStatus: vi.fn().mockResolvedValue({ runtimeState: "healthy" }),
    getTestKitStatus: vi.fn().mockResolvedValue({ enabled: true, sessions: [], beds: [] }),
    listHostBackups: vi.fn().mockResolvedValue([]),
    listRedisBackups: vi.fn().mockResolvedValue([]),
    listRuntimeDataBackups: vi.fn().mockResolvedValue([]),
    pauseTestKitVirtualRecorders: vi.fn().mockResolvedValue(testKitSession()),
    readLogs: vi.fn().mockResolvedValue({ text: "logs" }),
    repairDatastore: command,
    repairProxy: vi.fn().mockResolvedValue(commandResult),
    repairRuntime: command,
    repairVMDisk: command,
    resetTestKitBeds: vi.fn().mockResolvedValue([]),
    resetTestKitVirtualRecorders: vi.fn().mockResolvedValue({ enabled: true }),
    restartTestKitVirtualRecorders: vi.fn().mockResolvedValue(testKitSession()),
    restoreRedisBackup: vi.fn().mockResolvedValue(commandResult),
    restoreRuntimeDataBackup: vi.fn().mockResolvedValue(commandResult),
    rollbackBackup: vi.fn().mockResolvedValue(commandResult),
    resumeTestKitVirtualRecorders: vi.fn().mockResolvedValue(testKitSession()),
    startRuntimeServices: command,
    startTestKitVirtualRecorders: vi.fn().mockResolvedValue(testKitSession()),
    stopRuntimeServices: command,
    stopTestKitVirtualRecorders: vi.fn().mockResolvedValue(testKitSession()),
    summarizeUpdateBundle: vi.fn().mockResolvedValue({ summary: "ok" }),
    uninstallRuntime: vi.fn().mockResolvedValue(commandResult),
    verifyUpdateBundle: vi.fn().mockResolvedValue(commandResult)
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
    bridgedInterface: "",
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

const commandResult = { result: { exitCode: 0, stdout: "ok", stderr: "" } };

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

function testKitStart() {
  return {
    scenario: "normal" as const,
    signalProfile: "normal" as const,
    recorders: 1,
    bedRoomNames: ["OR-1"],
    vrcode: "VR_A",
    version: "testkit",
    intervalSeconds: 1,
    durationSeconds: null,
    maxMessages: null,
    shiftTime: true,
    generateFrames: true,
    exportVital: true,
    uploadVital: true,
    vitalUploadEndpoint: "/upload"
  };
}

function testKitSession() {
  return {
    id: "session-1",
    state: "running",
    targetUrl: "http://edge/",
    recordersRequested: 1,
    bedsRequested: 1,
    bedRoomNames: ["OR-1"],
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
    vital: {
      exportStatus: "not-requested",
      uploadStatus: "not-requested",
      exportError: null,
      uploadError: null,
      artifact: null,
      uploadResult: null
    },
    recorders: []
  };
}
