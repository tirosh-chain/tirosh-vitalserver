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
  useDeleteHostBackup,
  useDeleteRuntimeDataBackup,
  useDeleteVitalDBBeds,
  useDeleteVitalDBRecorders,
  useDeleteUpdateBackup,
  useExportHostLogs,
  useHostBackups,
  useHostLogs,
  useHideVitalDBBeds,
  useHideVitalDBRecorders,
  useLabBeds,
  useCreateLabSession,
  useLabRecorders,
  useLabScenarios,
  useLabSession,
  useLabVitalFiles,
  useReplayLabVitalFile,
  useRedisBackups,
  useRepairDatastore,
  useRepairProxy,
  useRepairRuntime,
  useRepairVMDisk,
  useRestartGuestService,
  useStartLabSession,
  useRollbackBackup,
  useRestoreRuntimeDataBackup,
  useRuntimeCapabilities,
  useRuntimeDataBackups,
  useRuntimeEvents,
  useRuntimeOperationState,
  useRuntimeOverview,
  useRuntimeSettings,
  useStartGuestService,
  useStopGuestService,
  useStopLabSession,
  useSummarizeUpdateBundle,
  useUnhideVitalDBBeds,
  useUnhideVitalDBRecorders,
  useUninstallRuntime,
  useUploadLabVitalFile,
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
    await expectQuery(useRuntimeOperationState, wrapper, gateway.getOperationState);
    await expectQuery(useRuntimeCapabilities, wrapper, gateway.getCapabilities);
    await expectQuery(useRuntimeSettings, wrapper, gateway.getSettings);
    await expectQuery(useVitalDBRecorders, wrapper, gateway.getRecorders);
    await expectQuery(useVitalDBBeds, wrapper, gateway.getBeds);
    await expectQuery(useVitalDBRelationships, wrapper, gateway.getRelationships);
    await expectQuery(useLabScenarios, wrapper, gateway.getLabScenarios);
    await expectQuery(useLabBeds, wrapper, gateway.getLabBeds);
    await expectQuery(useLabRecorders, wrapper, gateway.getLabRecorders);
    await expectQuery(useLabVitalFiles, wrapper, gateway.getLabVitalFiles);
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

    const labSession = renderHook(() => useLabSession("lab-1"), { wrapper });
    await waitFor(() =>
      expect(labSession.result.current.data).toEqual(labSessionResponse())
    );
    expect(gateway.getLabSession).toHaveBeenCalledWith("lab-1");
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
    await mutateHook(() => useStartGuestService(), "app", wrapper);
    await mutateHook(() => useStopGuestService(), "app", wrapper);
    await mutateHook(() => useRestartGuestService(), "app", wrapper);
    await mutateHook(() => useUninstallRuntime(), true, wrapper);
    expect(gateway.repairProxy).toHaveBeenCalledWith(18444);
    expect(gateway.startGuestService).toHaveBeenCalledWith({ service: "app" });
    expect(gateway.stopGuestService).toHaveBeenCalledWith({ service: "app" });
    expect(gateway.restartGuestService).toHaveBeenCalledWith({ service: "app" });
    expect(gateway.uninstallRuntime).toHaveBeenCalledWith({ mode: "clean" });

    await mutateHook(() => useHideVitalDBRecorders(), { vrcodes: ["VR_A"] }, wrapper);
    await mutateHook(() => useUnhideVitalDBRecorders(), { vrcodes: ["VR_A"] }, wrapper);
    await mutateHook(() => useDeleteVitalDBRecorders(), { vrcodes: ["VR_A"] }, wrapper);
    await mutateHook(() => useHideVitalDBBeds(), { bedIDs: ["bed-a"] }, wrapper);
    await mutateHook(() => useUnhideVitalDBBeds(), { bedIDs: ["bed-a"] }, wrapper);
    await mutateHook(() => useDeleteVitalDBBeds(), { bedIDs: ["bed-a"] }, wrapper);
    expect(gateway.hideRecorders).toHaveBeenCalledWith({ vrcodes: ["VR_A"] });
    expect(gateway.unhideRecorders).toHaveBeenCalledWith({ vrcodes: ["VR_A"] });
    expect(gateway.deleteRecorders).toHaveBeenCalledWith({ vrcodes: ["VR_A"] });
    expect(gateway.hideBeds).toHaveBeenCalledWith({ bedIDs: ["bed-a"] });
    expect(gateway.unhideBeds).toHaveBeenCalledWith({ bedIDs: ["bed-a"] });
    expect(gateway.deleteBeds).toHaveBeenCalledWith({ bedIDs: ["bed-a"] });
  });

  it("runs Product Lab mutations with decoded request payloads", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);

    await mutateHook(
      () => useCreateLabSession(),
      {
        scenarioId: "baseline",
        name: "Lab A",
        recorderCount: 2,
        targetURL: null
      },
      wrapper
    );
    expect(gateway.createLabSession).toHaveBeenCalledWith({
      scenarioId: "baseline",
      name: "Lab A",
      recorderCount: 2,
      targetURL: null
    });

    await mutateHook(() => useStartLabSession(), "lab-1", wrapper);
    await mutateHook(() => useStopLabSession(), "lab-1", wrapper);
    expect(gateway.startLabSession).toHaveBeenCalledWith("lab-1");
    expect(gateway.stopLabSession).toHaveBeenCalledWith("lab-1");

    await mutateHook(
      () => useReplayLabVitalFile(),
      {
        vitalFilePath: "/mnt/tirosh-vital-files/sample.vital",
        sessionName: "Replay",
        targetURL: null
      },
      wrapper
    );
    expect(gateway.replayLabVitalFile).toHaveBeenCalledWith({
      vitalFilePath: "/mnt/tirosh-vital-files/sample.vital",
      sessionName: "Replay",
      targetURL: null
    });

    await mutateHook(
      () => useUploadLabVitalFile(),
      {
        vitalFilePath: "/mnt/tirosh-vital-files/sample.vital",
        targetURL: "http://vitalserver:8000",
        endpoint: null,
        vrcode: null
      },
      wrapper
    );
    expect(gateway.uploadLabVitalFile).toHaveBeenCalledWith({
      vitalFilePath: "/mnt/tirosh-vital-files/sample.vital",
      targetURL: "http://vitalserver:8000",
      endpoint: null,
      vrcode: null
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
    createLabBeds: vi.fn().mockResolvedValue({
      state: "loaded",
      beds: [],
      readError: null
    }),
    createLabRecorders: vi.fn().mockResolvedValue({
      state: "loaded",
      recorders: [],
      readError: null
    }),
    createLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    deleteLabBeds: vi.fn().mockResolvedValue({
      state: "loaded",
      beds: [],
      readError: null
    }),
    deleteLabRecorders: vi.fn().mockResolvedValue({
      state: "loaded",
      recorders: [],
      readError: null
    }),
    deleteHostBackup: vi.fn().mockResolvedValue(commandResult),
    deleteBeds: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    deleteRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    deleteRuntimeDataBackup: vi.fn().mockResolvedValue(commandResult),
    deleteUpdateBackup: vi.fn().mockResolvedValue(commandResult),
    exportLogs: vi.fn().mockResolvedValue({ destination: "file:///tmp/logs.zip" }),
    getBeds: vi.fn().mockResolvedValue([]),
    getCapabilities: vi.fn().mockResolvedValue(fullCapabilities()),
    getOverview: vi.fn().mockResolvedValue({ status: { runtimeState: "healthy" } }),
    getOperationState: vi.fn().mockResolvedValue({
      activeOperation: "apply-bundle",
      runtimeStatusUpdatedAt: "2026-07-08T00:00:00Z",
      install: { state: "unavailable", document: null, readError: null },
      lease: { state: "unavailable", document: null, readError: null, staleReason: null }
    }),
    getRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    getRelationships: vi.fn().mockResolvedValue({
      state: "loaded",
      assignments: [],
      events: [],
      readError: null
    }),
    hideBeds: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    hideRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    getRuntimeEvents: vi.fn().mockResolvedValue({ events: [] }),
    getGuestStackStatus: vi.fn().mockResolvedValue({
      state: "loaded",
      observedAt: "2026-07-01T00:00:00+00:00",
      services: [],
      probeErrors: []
    }),
    getLabScenarios: vi.fn().mockResolvedValue({
      state: "loaded",
      scenarios: [{ scenarioId: "baseline", name: "Baseline", category: "generated" }],
      readError: null
    }),
    getLabBeds: vi.fn().mockResolvedValue({
      state: "loaded",
      beds: [],
      readError: null
    }),
    getLabRecorders: vi.fn().mockResolvedValue({
      state: "loaded",
      recorders: [],
      readError: null
    }),
    getLabVitalFiles: vi.fn().mockResolvedValue({
      state: "loaded",
      vitalFiles: [],
      readError: null
    }),
    getLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    getSettings: vi.fn().mockResolvedValue(fullSettings({ proxyPort: 18080 })),
    getStatus: vi.fn().mockResolvedValue({ runtimeState: "healthy" }),
    listHostBackups: vi.fn().mockResolvedValue([]),
    listRedisBackups: vi.fn().mockResolvedValue([]),
    listRuntimeDataBackups: vi.fn().mockResolvedValue([]),
    readLogs: vi.fn().mockResolvedValue({ text: "logs" }),
    repairDatastore: command,
    repairProxy: vi.fn().mockResolvedValue(commandResult),
    repairRuntime: command,
    repairVMDisk: command,
    restoreRedisBackup: vi.fn().mockResolvedValue(commandResult),
    restoreRuntimeDataBackup: vi.fn().mockResolvedValue(commandResult),
    rollbackBackup: vi.fn().mockResolvedValue(commandResult),
    replayLabVitalFile: vi.fn().mockResolvedValue(labSessionResponse()),
    resetLabBeds: vi.fn().mockResolvedValue({
      state: "loaded",
      beds: [],
      readError: null
    }),
    resetLabRecorders: vi.fn().mockResolvedValue({
      state: "loaded",
      recorders: [],
      readError: null
    }),
    restartGuestService: vi.fn().mockResolvedValue(guestServiceOperation("restart")),
    startGuestService: vi.fn().mockResolvedValue(guestServiceOperation("start")),
    startLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    stopGuestService: vi.fn().mockResolvedValue(guestServiceOperation("stop")),
    stopLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    summarizeUpdateBundle: vi.fn().mockResolvedValue({ summary: "ok" }),
    uninstallRuntime: vi.fn().mockResolvedValue(commandResult),
    unhideBeds: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    unhideRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    uploadLabVitalFile: vi.fn().mockResolvedValue({
      state: "loaded",
      upload: null,
      operationId: "lab-vital-file-upload",
      labOperationId: null,
      readError: null
    }),
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
