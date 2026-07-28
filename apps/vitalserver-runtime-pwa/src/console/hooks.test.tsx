import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { PropsWithChildren, ReactElement } from "react";
import { describe, expect, it, vi } from "vitest";

import { RuntimeControlGatewayProvider } from "@/console/runtimeControlGatewayContext";
import type { RuntimeControlGateway } from "./runtimeControlGateway";
import {
  useApplyRuntimeAdminPassword,
  useApplyRuntimeProductSettings,
  useApplyUpdateBundle,
  useCreatePlatformSupportExport,
  useRollbackRelease,
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
  useLabSessions,
  useLabVitalFiles,
  useReplayLabVitalFile,
  useRedisBackups,
  useRedisRelayStatus,
  useLatestVitalDBObservation,
  useRepairDatastore,
  useRecorderObservabilityDetail,
  useRecorderObservabilityIncidents,
  useRecorderObservabilityTimeline,
  useRestartRuntimeProvider,
  useRestartGuestService,
  useStartLabSession,
  useStartLabRecorder,
  useRollbackBackup,
  useRestoreRuntimeDataBackup,
  useControlCapabilities,
  useRuntimeDataBackups,
  useRuntimeEvents,
  usePlatformOperationState,
  useRuntimeServiceResources,
  useRuntimeStack,
  useRuntimeProductSettings,
  useStartGuestService,
  useStopGuestService,
  useStopLabSession,
  useFinishLabSession,
  useStopLabRecorder,
  useSummarizeUpdateBundle,
  useUnhideVitalDBBeds,
  useUnhideVitalDBRecorders,
  useUninstallRuntime,
  useUploadLabVitalFiles,
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

    await expectQuery(
      useLatestVitalDBObservation,
      wrapper,
      gateway.getLatestVitalDBObservation
    );
    await expectQuery(useRuntimeStack, wrapper, gateway.getRuntimeStack);
    await expectQuery(useRedisRelayStatus, wrapper, gateway.getRedisRelayStatus);
    await expectQuery(usePlatformOperationState, wrapper, gateway.getOperationState);
    await expectQuery(useControlCapabilities, wrapper, gateway.getCapabilities);
    await expectQuery(
      useRuntimeProductSettings,
      wrapper,
      gateway.getRuntimeProductSettings
    );
    await expectQuery(useVitalDBRecorders, wrapper, gateway.getRecorders);
    await expectQuery(useVitalDBBeds, wrapper, gateway.getBeds);
    await expectQuery(useVitalDBRelationships, wrapper, gateway.getRelationships);
    await expectQuery(useLabScenarios, wrapper, gateway.getLabScenarios);
    await expectQuery(useLabBeds, wrapper, gateway.getLabBeds);
    await expectQuery(useLabRecorders, wrapper, gateway.getLabRecorders);
    await expectQuery(useLabSessions, wrapper, gateway.getLabSessions);
    await expectQuery(useLabVitalFiles, wrapper, gateway.getLabVitalFiles);
    await expectQuery(() => useHostBackups(true), wrapper, gateway.listHostBackups);
    await expectQuery(() => useRedisBackups(true), wrapper, gateway.listRedisBackups);
    await expectQuery(
      () => useRuntimeDataBackups(true),
      wrapper,
      gateway.listRuntimeDataBackups
    );

    const serviceResources = renderHook(
      () => useRuntimeServiceResources(["app"]),
      { wrapper }
    );
    await waitFor(() =>
      expect(serviceResources.result.current[0]?.resource).toEqual(
        guestServiceResource()
      )
    );
    expect(gateway.getGuestServiceResource).toHaveBeenCalledWith("app");

    const events = renderHook(
      () =>
        useRuntimeEvents({
          limit: 5,
          type: "operation-completed",
          since: "2026-05-31T00:00:00Z"
        }),
      { wrapper }
    );
    await waitFor(() => expect(events.result.current.data).toEqual({ events: [] }));
    expect(gateway.getRuntimeEvents).toHaveBeenCalledWith({
      limit: 5,
      type: "operation-completed",
      since: "2026-05-31T00:00:00Z"
    });

    const logs = renderHook(
      () =>
        useHostLogs({
          source: "containers",
          lineLimit: 100,
          live: false,
          enabled: true
        }),
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

  it("does not read optional Host resources without the advertised capability", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);

    renderHook(
      () =>
        useHostLogs({
          source: "containers",
          lineLimit: 100,
          live: true,
          enabled: false
        }),
      { wrapper }
    );
    renderHook(() => useHostBackups(false), { wrapper });
    renderHook(() => useRedisBackups(false), { wrapper });
    renderHook(() => useRuntimeDataBackups(false), { wrapper });

    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(gateway.readLogs).not.toHaveBeenCalled();
    expect(gateway.listHostBackups).not.toHaveBeenCalled();
    expect(gateway.listRedisBackups).not.toHaveBeenCalled();
    expect(gateway.listRuntimeDataBackups).not.toHaveBeenCalled();
  });

  it("loads Recorder observability detail only after a Recorder is selected", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);
    const detail = renderHook(
      ({ vrcode }: { vrcode: string | null }) =>
        useRecorderObservabilityDetail(vrcode),
      { wrapper, initialProps: { vrcode: null as string | null } }
    );

    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(gateway.getRecorderObservability).not.toHaveBeenCalled();

    detail.rerender({ vrcode: "VR_A" });
    await waitFor(() =>
      expect(gateway.getRecorderObservability).toHaveBeenCalledWith("VR_A")
    );
  });

  it("loads bounded Recorder history only after an explicit query exists", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);
    const timeline = renderHook(
      ({ enabled }: { enabled: boolean }) =>
        useRecorderObservabilityTimeline(enabled ? {
          vrcode: "VR_A",
          from: "2026-07-23T00:00:00Z",
          until: "2026-07-24T00:00:00Z",
          bucketSeconds: 900
        } : null),
      { wrapper, initialProps: { enabled: false } }
    );
    const incidents = renderHook(
      ({ enabled }: { enabled: boolean }) =>
        useRecorderObservabilityIncidents(enabled ? {
          vrcode: "VR_A",
          from: "2026-07-23T00:00:00Z",
          until: "2026-07-24T00:00:00Z",
          limit: 20
        } : null),
      { wrapper, initialProps: { enabled: false } }
    );

    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(gateway.getRecorderObservabilityTimeline).not.toHaveBeenCalled();
    expect(gateway.getRecorderObservabilityIncidents).not.toHaveBeenCalled();

    timeline.rerender({ enabled: true });
    incidents.rerender({ enabled: true });
    await waitFor(() => {
      expect(gateway.getRecorderObservabilityTimeline).toHaveBeenCalledTimes(1);
      expect(gateway.getRecorderObservabilityIncidents).toHaveBeenCalledTimes(1);
    });
  });

  it("runs runtime, update, backup, and repair mutations through the gateway", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);

    await mutateHook(
      () => useApplyRuntimeProductSettings(),
      { settings: productSettings() },
      wrapper
    );
    expect(gateway.applyRuntimeProductSettings).toHaveBeenCalledWith({
      settings: productSettings()
    });
    await mutateHook(
      () => useApplyRuntimeAdminPassword(),
      { password: "new-admin-secret" },
      wrapper
    );
    expect(gateway.applyRuntimeAdminPassword).toHaveBeenCalledWith({
      password: "new-admin-secret"
    });

    await mutateHook(() => useExportHostLogs(), "/tmp/logs.zip", wrapper);
    expect(gateway.exportLogs).toHaveBeenCalledWith({
      destination: { kind: "localPath", value: "/tmp/logs.zip" }
    });
    await mutateHook(() => useCreatePlatformSupportExport(), undefined, wrapper);
    expect(gateway.createPlatformSupportExport).toHaveBeenCalledWith();

    await mutateHook(() => useSummarizeUpdateBundle(), "/tmp/update.tar.gz", wrapper);
    await mutateHook(() => useVerifyUpdateBundle(), "/tmp/update.tar.gz", wrapper);
    await mutateHook(() => useApplyUpdateBundle(), "/tmp/update.tar.gz", wrapper);
    await mutateHook(() => useRollbackRelease(), undefined, wrapper);
    expect(gateway.summarizeUpdateBundle).toHaveBeenCalledWith({
      bundle: { kind: "localPath", value: "/tmp/update.tar.gz" }
    });
    expect(gateway.verifyUpdateBundle).toHaveBeenCalledWith({
      bundle: { kind: "localPath", value: "/tmp/update.tar.gz" }
    });
    expect(gateway.applyUpdateBundle).toHaveBeenCalledWith({
      bundle: { kind: "localPath", value: "/tmp/update.tar.gz" }
    });
    expect(gateway.rollbackRelease).toHaveBeenCalledWith();

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

    await mutateHook(() => useRestartRuntimeProvider(), undefined, wrapper);
    await mutateHook(() => useRepairDatastore(), undefined, wrapper);
    await mutateHook(() => useStartGuestService(), "app", wrapper);
    await mutateHook(() => useStopGuestService(), "app", wrapper);
    await mutateHook(() => useRestartGuestService(), "app", wrapper);
    await mutateHook(() => useUninstallRuntime(), true, wrapper);
    expect(gateway.restartRuntimeProvider).toHaveBeenCalledWith();
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
    await mutateHook(() => useFinishLabSession(), "lab-1", wrapper);
    expect(gateway.startLabSession).toHaveBeenCalledWith("lab-1");
    expect(gateway.stopLabSession).toHaveBeenCalledWith("lab-1");
    expect(gateway.finishLabSession).toHaveBeenCalledWith("lab-1");

    const recorderCommand = { sessionId: "lab-1", recorderId: "recorder-1" };
    await mutateHook(() => useStartLabRecorder(), recorderCommand, wrapper);
    await mutateHook(() => useStopLabRecorder(), recorderCommand, wrapper);
    expect(gateway.startLabRecorder).toHaveBeenCalledWith("lab-1", "recorder-1");
    expect(gateway.stopLabRecorder).toHaveBeenCalledWith("lab-1", "recorder-1");

    await mutateHook(
      () => useReplayLabVitalFile(),
      {
        vitalFileRelativePath: "sample.vital",
        sessionName: "Replay",
        targetURL: null,
        resourceSelection: { mode: "quickCreate" },
        repeatPolicy: { mode: "once" }
      },
      wrapper
    );
    expect(gateway.replayLabVitalFile).toHaveBeenCalledWith({
      vitalFileRelativePath: "sample.vital",
      sessionName: "Replay",
      targetURL: null,
      resourceSelection: { mode: "quickCreate" },
      repeatPolicy: { mode: "once" }
    });

    await mutateHook(
      () => useUploadLabVitalFiles(),
      {
        files: [
          new File(["first"], "first.vital"),
          new File(["second"], "second.vital")
        ]
      },
      wrapper
    );
    expect(gateway.uploadLabVitalFiles).toHaveBeenCalledWith({
      files: expect.arrayContaining([
        expect.objectContaining({ name: "first.vital" }),
        expect.objectContaining({ name: "second.vital" })
      ])
    });
  });

  it("forwards every selected file so the owner can report per-file failures", async () => {
    const gateway = createGateway();
    const wrapper = createWrapper(gateway);
    const rendered = renderHook(() => useUploadLabVitalFiles(), { wrapper });

    await expect(rendered.result.current.mutateAsync({
      files: [
        new File(["valid"], "valid.vital"),
        new File(["invalid"], "invalid.txt")
      ]
    })).resolves.toEqual(expect.anything());
    expect(gateway.uploadLabVitalFiles).toHaveBeenCalledWith({
      files: expect.arrayContaining([
        expect.objectContaining({ name: "valid.vital" }),
        expect.objectContaining({ name: "invalid.txt" })
      ])
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
  return {
    applyRuntimeAdminPassword: vi.fn().mockResolvedValue({
      operationId: "op_admin_1",
      service: "runtime-admin",
      command: "apply-admin-password",
      state: "completed",
      createdAt: "2026-07-01T00:00:00Z",
      updatedAt: "2026-07-01T00:00:01Z"
    }),
    applyRuntimeRedisRelaySettings: vi.fn().mockResolvedValue({
      operationId: "op_relay_settings_1",
      service: "redis-relay-settings",
      command: "apply-redis-relay-settings",
      state: "completed",
      createdAt: "2026-07-01T00:00:00Z",
      updatedAt: "2026-07-01T00:00:01Z"
    }),
    applyRuntimeProductSettings: vi.fn().mockResolvedValue({
      operationId: "op_settings_1",
      service: "runtime-settings",
      command: "apply-settings",
      state: "completed",
      createdAt: "2026-07-01T00:00:00Z",
      updatedAt: "2026-07-01T00:00:01Z"
    }),
    applyRuntimePlatformSettings: vi.fn().mockResolvedValue(commandResult),
    applyUpdateBundle: vi.fn().mockResolvedValue(commandResult),
    rollbackRelease: vi.fn().mockResolvedValue(commandResult),
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
    deleteBeds: vi.fn().mockResolvedValue(fullVitalBedHistory()),
    deleteRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    deleteRuntimeDataBackup: vi.fn().mockResolvedValue(commandResult),
    deleteUpdateBackup: vi.fn().mockResolvedValue(commandResult),
    exportLogs: vi.fn().mockResolvedValue({ destination: "file:///tmp/logs.zip" }),
    createPlatformSupportExport: vi.fn().mockResolvedValue(platformWorkflowOperation("update-verify")),
    getBeds: vi.fn().mockResolvedValue(fullVitalBedHistory()),
    getCapabilities: vi.fn().mockResolvedValue(fullCapabilities()),
    getPlatformCapabilities: vi.fn().mockResolvedValue(platformCapabilities()),
    getRuntimeCapabilities: vi.fn().mockResolvedValue({
      schemaVersion: 1,
      capabilities: [
        "services:start",
        "services:stop",
        "services:restart",
        "lab:scenarios",
        "lab:sessions:list",
        "lab:recorders:start",
        "lab:recorders:stop"
      ]
    }),
    getOperationState: vi.fn().mockResolvedValue({
      activeOperation: "apply-bundle",
      install: { state: "unavailable", document: null, readError: null },
      lease: { state: "unavailable", document: null, readError: null, staleReason: null }
    }),
    getRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    getRecorderActivity: vi.fn().mockResolvedValue({
      state: "empty",
      query: { vrcode: "VR_A", bucketSeconds: 60, period: "lastHour" },
      page: {
        index: 0,
        count: 1,
        windowSeconds: 3600,
        windowStartedAt: null,
        windowEndedAt: null,
        firstBucketStartedAt: null,
        latestBucketStartedAt: null
      },
      buckets: [],
      latestSampleAt: null,
      readError: null
    }),
    getRecorderVitalFiles: vi.fn().mockResolvedValue({
      state: "loaded",
      vrcode: "VR_A",
      files: [],
      unattributedCount: 0,
      sources: {
        nativeUpload: { state: "loaded", readError: null },
        coldPathRecovery: { state: "loaded", readError: null }
      },
      readError: null
    }),
    getRecorderObservability: vi.fn().mockResolvedValue({
      state: "loaded",
      vrcode: "VR_A"
    }),
    getRecorderObservabilityTimeline: vi.fn().mockResolvedValue({
      state: "notReported",
      vrcode: "VR_A",
      supportState: "supported",
      timeBasis: "receivedAt",
      query: null,
      buckets: [],
      readError: null
    }),
    getRecorderObservabilityIncidents: vi.fn().mockResolvedValue({
      state: "loaded",
      vrcode: "VR_A",
      timeBasis: "receivedAt",
      incidents: [],
      nextCursor: null,
      readError: null
    }),
    getReleaseInfo: vi.fn().mockResolvedValue({
      helperVersion: "1.0.0",
      vitalServerVersion: "1.0.0",
      services: []
    }),
    getInstallInfo: vi.fn().mockResolvedValue({}),
    getRelationships: vi.fn().mockResolvedValue({
      state: "loaded",
      assignments: [],
      events: [],
      readError: null
    }),
    hideBeds: vi.fn().mockResolvedValue(fullVitalBedHistory()),
    hideRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    getRuntimeEvents: vi.fn().mockResolvedValue({ events: [] }),
    getRuntimeStack: vi.fn().mockResolvedValue({
      state: "loaded",
      observedAt: "2026-07-01T00:00:00+00:00",
      services: [],
      probeErrors: []
    }),
    getGuestServiceResource: vi.fn().mockResolvedValue(guestServiceResource()),
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
    getLabSessions: vi.fn().mockResolvedValue({
      state: "loaded",
      sessions: [labSessionResponse().session],
      readError: null
    }),
    getLabVitalFiles: vi.fn().mockResolvedValue({
      state: "loaded",
      vitalFiles: [],
      readError: null
    }),
    getLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    getLatestVitalDBObservation: vi.fn().mockResolvedValue({
      state: "missing",
      observation: null,
      readError: null
    }),
    getRuntimeProductSettings: vi.fn().mockResolvedValue({
      state: "loaded",
      settings: productSettings(),
      readError: null
    }),
    getRuntimePlatformSettings: vi.fn().mockResolvedValue({
      state: "unavailable",
      settings: null,
      readIssues: [],
      readError: "Platform settings are unavailable in this test adapter."
    }),
    getPlatformState: vi.fn().mockResolvedValue({
      runtimeInstallationState: "executable",
      services: [],
      platformHealth: "healthy"
    }),
    getRedisRelayStatus: vi.fn().mockResolvedValue({
      readState: "readFailed",
      document: null,
      readError: "runtime owner unavailable"
    }),
    getRuntimeRedisRelaySettings: vi.fn().mockResolvedValue({
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
    }),
    getPlatformWorkflow: vi.fn().mockResolvedValue({
      state: "missing",
      operation: null,
      readError: null
    }),
    listHostBackups: vi.fn().mockResolvedValue([]),
    listRedisBackups: vi.fn().mockResolvedValue([]),
    listRuntimeDataBackups: vi.fn().mockResolvedValue([]),
    readLogs: vi.fn().mockResolvedValue({ text: "logs" }),
    repairDatastore: vi.fn().mockResolvedValue(
      guestServiceOperation("repair-datastore", "datastore-repair")
    ),
    restartRuntimeProvider: vi.fn().mockResolvedValue(runtimeProviderCommandResponse()),
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
    startLabRecorder: vi.fn().mockResolvedValue(labRecorderResponse("running")),
    stopGuestService: vi.fn().mockResolvedValue(guestServiceOperation("stop")),
    stopLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    finishLabSession: vi.fn().mockResolvedValue(labSessionResponse()),
    stopLabRecorder: vi.fn().mockResolvedValue(labRecorderResponse("stopped")),
    summarizeUpdateBundle: vi.fn().mockResolvedValue({ summary: "ok" }),
    uninstallRuntime: vi.fn().mockResolvedValue(platformWorkflowOperation("uninstall")),
    unhideBeds: vi.fn().mockResolvedValue(fullVitalBedHistory()),
    unhideRecorders: vi.fn().mockResolvedValue(fullVitalRecorderHistory()),
    uploadLabVitalFiles: vi.fn().mockResolvedValue({
      state: "completed",
      files: [],
      failedFiles: []
    }),
    verifyUpdateBundle: vi.fn().mockResolvedValue(commandResult)
  };
}

function labRecorderResponse(state: "running" | "stopped") {
  return {
    state: "loaded" as const,
    operationId: `op-recorder-${state}`,
    labOperationId: `lab-op-recorder-${state}`,
    readError: null,
    recorder: {
      recorderId: "recorder-1",
      sessionId: "lab-1",
      bedId: "bed-1",
      vrcode: "LAB-REC001",
      state,
      messagesSent: 0,
      lastSendState: "notAttempted" as const
    }
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
    canRepairRuntimeDatastore: true,
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
    canRepairRuntimeDatastore: ___,
    canListLabSessions: ____,
    canControlLabRecorders: _____,
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
  const settings = fullSettings();
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

const commandResult = {
  result: {
    exitCode: 0,
    stdout: "ok",
    stderr: "",
    outputIssues: [],
    executionIssue: null
  }
};

function platformWorkflowOperation(
  kind: "update-verify" | "update-apply" | "rollback" | "uninstall"
) {
  return {
    schemaVersion: 1 as const,
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

function runtimeProviderCommandResponse() {
  return {
    operationId: "provider-restart-1",
    action: "restart" as const,
    state: "completed" as const,
    provider: {
      state: "missing" as const,
      document: null,
      readError: null
    },
    failure: null
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
