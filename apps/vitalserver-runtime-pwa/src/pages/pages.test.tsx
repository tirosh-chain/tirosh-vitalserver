import { fireEvent, render, screen, within } from "@testing-library/react";
import type { PropsWithChildren, ReactElement } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";
import { AppSettingsProvider } from "@/config/AppSettingsContext";

const hooks = vi.hoisted(() => ({
  useApplyRuntimeSettings: vi.fn(),
  useApplyUpdateBundle: vi.fn(),
  useCreateRedisBackup: vi.fn(),
  useCreateTestKitBeds: vi.fn(),
  useDeleteHostBackup: vi.fn(),
  useDeleteTestKitBeds: vi.fn(),
  useDeleteTestKitOrphanVRecorder: vi.fn(),
  useExportHostLogs: vi.fn(),
  useHostBackups: vi.fn(),
  useHostLogs: vi.fn(),
  useRedisBackups: vi.fn(),
  useRepairDatastore: vi.fn(),
  useRepairProxy: vi.fn(),
  useRepairRuntime: vi.fn(),
  useRepairVMDisk: vi.fn(),
  useResetTestKitBeds: vi.fn(),
  useResetTestKitVirtualRecorders: vi.fn(),
  useRestartTestKitVirtualRecorders: vi.fn(),
  useRollbackBackup: vi.fn(),
  useRuntimeCapabilities: vi.fn(),
  useRuntimeEvents: vi.fn(),
  useRuntimeOverview: vi.fn(),
  useRuntimeSettings: vi.fn(),
  useSessionTestKitAction: vi.fn(),
  useStartRuntimeServices: vi.fn(),
  useStartTestKitVirtualRecorders: vi.fn(),
  useStopRuntimeServices: vi.fn(),
  useSummarizeUpdateBundle: vi.fn(),
  useTestKitStatus: vi.fn(),
  useVerifyUpdateBundle: vi.fn(),
  useVitalDBBeds: vi.fn(),
  useVitalDBRecorders: vi.fn(),
  useUninstallRuntime: vi.fn()
}));

vi.mock("@/console/hooks", () => hooks);

import { AdvancedPage } from "./advanced/AdvancedPage";
import { BedsPage } from "./beds/BedsPage";
import { DangerZonePage } from "./danger-zone/DangerZonePage";
import { LogsPage } from "./logs/LogsPage";
import { ObservabilityPage } from "./observability/ObservabilityPage";
import { RecordersPage } from "./recorders/RecordersPage";
import { SettingsPage } from "./settings/SettingsPage";
import { StatusPage } from "./status/StatusPage";
import { TestKitPage } from "./testkit/TestKitPage";
import { UpdatePage } from "./update/UpdatePage";

const commandResult = { result: { exitCode: 0, stdout: "ok", stderr: "" } };

function Wrapper({ children }: PropsWithChildren) {
  return (
    <AppSettingsProvider settings={DEFAULT_APP_SETTINGS}>
      {children}
    </AppSettingsProvider>
  );
}

function renderPage(element: ReactElement) {
  return render(element, { wrapper: Wrapper });
}

function query<T>(data: T) {
  return {
    data,
    error: null,
    isError: false,
    isFetching: false,
    isLoading: false,
    isPending: false,
    refetch: vi.fn()
  };
}

function failedQuery(error = new Error("failed")) {
  return {
    data: undefined,
    error,
    isError: true,
    isFetching: false,
    isLoading: false,
    isPending: false,
    refetch: vi.fn()
  };
}

function mutation<TData = typeof commandResult>(data: TData = commandResult as TData) {
  const mutate = vi.fn((_value?: unknown, options?: { onSuccess?: (data: TData) => void }) => {
    options?.onSuccess?.(data);
  });
  return {
    data,
    error: null,
    isError: false,
    isPending: false,
    mutate
  };
}

function pendingMutation() {
  return {
    data: undefined,
    error: null,
    isError: false,
    isPending: false,
    mutate: vi.fn()
  };
}

beforeEach(() => {
  vi.restoreAllMocks();
  vi.spyOn(globalThis, "confirm").mockReturnValue(true);
  setupDefaultHooks();
});

describe("runtime console pages", () => {
  it("renders status metrics from the overview document", () => {
    renderPage(<StatusPage />);

    expect(screen.getByText("Overall health")).toBeInTheDocument();
    expect(screen.getByText("Healthy")).toBeInTheDocument();
    expect(screen.getByText("VitalServer")).toBeInTheDocument();
    expect(screen.getByText(/2.0 KiB \/ 4.0 KiB/)).toBeInTheDocument();
  });

  it("renders settings, validation, and applies edited values", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimeSettings.mockReturnValue(apply);

    renderPage(<SettingsPage />);

    fireEvent.change(screen.getByLabelText("CPU cores"), {
      target: { value: "3" }
    });
    fireEvent.change(screen.getByLabelText("Custom advertised host"), {
      target: { value: "edge.local" }
    });
    fireEvent.change(screen.getByLabelText("Advertised port"), {
      target: { value: "443" }
    });
    fireEvent.click(screen.getByLabelText("Start on boot"));
    fireEvent.click(screen.getByLabelText("Auto recovery"));
    fireEvent.click(screen.getByLabelText("Prevent system sleep"));
    fireEvent.click(screen.getByLabelText("Restart services after save"));
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    expect(apply.mutate).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({
          cpuCount: 3,
          publicHost: "edge.local",
          publicPort: 443,
          startOnBoot: false,
          autoRecoveryEnabled: false,
          preventSystemSleep: false,
          restartAfterSave: false
        })
      }),
      expect.any(Object)
    );
  });

  it("renders recorder lists, filters history, and selects recorder details", () => {
    renderPage(<RecordersPage />);

    expect(screen.getByText("Known recorders")).toBeInTheDocument();
    expect(screen.getAllByText("VR_A").length).toBeGreaterThan(0);
    expect(screen.getByRole("img", { name: /Packet activity/ })).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Search VRecorders"), {
      target: { value: "missing" }
    });
    expect(screen.getByText("No VRecorders have been observed.")).toBeInTheDocument();
  });

  it("renders beds, filters rows, and shows selected bed details", () => {
    renderPage(<BedsPage />);

    expect(screen.getByText("Known beds")).toBeInTheDocument();
    expect(screen.getAllByText("OR-1").length).toBeGreaterThan(0);
    expect(screen.getByText("Bed Details")).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Search beds"), {
      target: { value: "none" }
    });
    expect(screen.getByText("No beds have been observed.")).toBeInTheDocument();
  });

  it("renders observability events and reacts to filters", () => {
    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Observation pipeline")).toBeInTheDocument();
    expect(screen.getByText("runtime updated")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Period"), { target: { value: "7d" } });
    fireEvent.change(screen.getByLabelText("Type"), { target: { value: "update" } });
    fireEvent.change(screen.getByLabelText("Limit"), { target: { value: "100" } });

    expect(hooks.useRuntimeEvents).toHaveBeenCalled();
  });

  it("reads and exports logs with host path validation", () => {
    const exportLogs = mutation({ destination: "file:///tmp/vitalserver-logs.zip" });
    hooks.useExportHostLogs.mockReturnValue(exportLogs);

    renderPage(<LogsPage />);

    expect(screen.getByText(/line one/)).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Source"), {
      target: { value: "helperMessage" }
    });
    fireEvent.change(screen.getByLabelText("Lines"), { target: { value: "100" } });
    fireEvent.click(screen.getByRole("checkbox", { name: "Live" }));
    fireEvent.click(screen.getByRole("button", { name: "Export Logs" }));

    expect(exportLogs.mutate).toHaveBeenCalledWith("/tmp/vitalserver-logs.zip");
    expect(screen.getByText(/Exported to/)).toBeInTheDocument();
  });

  it("runs update inspection, verification, and apply actions", () => {
    const summarize = pendingMutation();
    const verify = pendingMutation();
    const apply = mutation(commandResult);
    hooks.useSummarizeUpdateBundle.mockReturnValue(summarize);
    hooks.useVerifyUpdateBundle.mockReturnValue(verify);
    hooks.useApplyUpdateBundle.mockReturnValue(apply);

    renderPage(<UpdatePage />);

    fireEvent.change(screen.getByLabelText("Offline bundle"), {
      target: { value: "/tmp/update.tar.gz" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Inspect" }));
    fireEvent.click(screen.getByRole("button", { name: "Verify" }));
    fireEvent.click(screen.getByRole("button", { name: "Apply Bundle" }));

    expect(summarize.mutate).toHaveBeenCalledWith("/tmp/update.tar.gz");
    expect(verify.mutate).toHaveBeenCalledWith("/tmp/update.tar.gz");
    expect(apply.mutate).toHaveBeenCalledWith("/tmp/update.tar.gz", expect.any(Object));
    expect(screen.getByText(/Helper is relaunching/)).toBeInTheDocument();
  });

  it("renders advanced recovery controls and dispatches selected actions", () => {
    const rollback = pendingMutation();
    const deleteHostBackup = pendingMutation();
    const createRedisBackup = pendingMutation();
    const repairRuntime = pendingMutation();
    const repairDatastore = pendingMutation();
    const repairVMDisk = pendingMutation();
    const repairProxy = pendingMutation();
    hooks.useRollbackBackup.mockReturnValue(rollback);
    hooks.useDeleteHostBackup.mockReturnValue(deleteHostBackup);
    hooks.useCreateRedisBackup.mockReturnValue(createRedisBackup);
    hooks.useRepairRuntime.mockReturnValue(repairRuntime);
    hooks.useRepairDatastore.mockReturnValue(repairDatastore);
    hooks.useRepairVMDisk.mockReturnValue(repairVMDisk);
    hooks.useRepairProxy.mockReturnValue(repairProxy);

    renderPage(<AdvancedPage />);

    fireEvent.click(screen.getByRole("row", { name: /backup-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Rollback" }));
    fireEvent.click(screen.getByRole("button", { name: "Delete Backup" }));
    fireEvent.click(screen.getByRole("button", { name: "Create Redis Backup" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair Runtime" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair Data Store" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair VM Disk" }));
    fireEvent.change(screen.getByLabelText("Proxy port"), {
      target: { value: "18444" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Repair Proxy" }));

    expect(rollback.mutate).toHaveBeenCalledWith("/tmp/backup-a");
    expect(deleteHostBackup.mutate).toHaveBeenCalledWith("/tmp/backup-a");
    expect(createRedisBackup.mutate).toHaveBeenCalledWith("");
    expect(repairRuntime.mutate).toHaveBeenCalled();
    expect(repairDatastore.mutate).toHaveBeenCalled();
    expect(repairVMDisk.mutate).toHaveBeenCalled();
    expect(repairProxy.mutate).toHaveBeenCalledWith(18444);
  });

  it("controls runtime services and gated uninstall flow", () => {
    const start = pendingMutation();
    const stop = pendingMutation();
    const uninstall = pendingMutation();
    hooks.useStartRuntimeServices.mockReturnValue(start);
    hooks.useStopRuntimeServices.mockReturnValue(stop);
    hooks.useUninstallRuntime.mockReturnValue(uninstall);

    renderPage(<DangerZonePage />);

    fireEvent.click(screen.getByRole("button", { name: "Start Runtime" }));
    fireEvent.click(screen.getByRole("button", { name: "Stop Runtime" }));
    fireEvent.change(screen.getByLabelText("Confirmation"), {
      target: { value: "UNINSTALL" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Uninstall" }));
    fireEvent.click(screen.getByLabelText("Clean uninstall"));
    fireEvent.change(screen.getByLabelText("Confirmation"), {
      target: { value: "CLEAN UNINSTALL" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Clean Uninstall" }));

    expect(start.mutate).toHaveBeenCalled();
    expect(stop.mutate).toHaveBeenCalled();
    expect(uninstall.mutate).toHaveBeenNthCalledWith(1, false);
    expect(uninstall.mutate).toHaveBeenNthCalledWith(2, true);
  });

  it("manages TestKit beds, sessions, and orphan cleanup", () => {
    const createBeds = pendingMutation();
    const deleteBeds = pendingMutation();
    const resetBeds = pendingMutation();
    const startSession = mutation(testKitSession("running"));
    const resetSessions = pendingMutation();
    const deleteOrphan = pendingMutation();
    const sessionAction = pendingMutation();
    hooks.useCreateTestKitBeds.mockReturnValue(createBeds);
    hooks.useDeleteTestKitBeds.mockReturnValue(deleteBeds);
    hooks.useResetTestKitBeds.mockReturnValue(resetBeds);
    hooks.useStartTestKitVirtualRecorders.mockReturnValue(startSession);
    hooks.useResetTestKitVirtualRecorders.mockReturnValue(resetSessions);
    hooks.useDeleteTestKitOrphanVRecorder.mockReturnValue(deleteOrphan);
    hooks.useSessionTestKitAction.mockReturnValue(sessionAction);

    renderPage(<TestKitPage />);

    const bedCheckbox = within(screen.getByText("OR-1").closest("label")!).getByRole(
      "checkbox"
    );
    fireEvent.click(bedCheckbox);
    fireEvent.click(screen.getByRole("button", { name: "Create" }));
    fireEvent.click(screen.getByRole("button", { name: "Delete selected" }));
    fireEvent.click(screen.getByRole("button", { name: "Reset" }));
    fireEvent.click(screen.getByRole("button", { name: "Start" }));
    fireEvent.click(screen.getByRole("button", { name: "Reset sessions" }));
    fireEvent.click(screen.getByRole("button", { name: "Pause" }));
    fireEvent.click(screen.getByRole("button", { name: "Resume" }));
    fireEvent.click(screen.getByRole("button", { name: "Stop" }));
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    fireEvent.change(screen.getByLabelText("Orphan VRecorder code"), {
      target: { value: "VR_ORPHAN" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Delete VRecorder" }));

    expect(createBeds.mutate).toHaveBeenCalledWith({
      count: 1,
      prefix: "testkit-bed"
    });
    expect(deleteBeds.mutate).toHaveBeenCalledWith(["OR-1"]);
    expect(resetBeds.mutate).toHaveBeenCalledWith(undefined);
    expect(startSession.mutate).toHaveBeenCalledWith(
      expect.objectContaining({ bedRoomNames: ["OR-1"], recorders: 1 }),
      expect.any(Object)
    );
    expect(resetSessions.mutate).toHaveBeenCalledWith(undefined);
    expect(sessionAction.mutate).toHaveBeenCalledWith("session-1");
    expect(deleteOrphan.mutate).toHaveBeenCalledWith("VR_ORPHAN");
  });

  it("shows page-level query errors", () => {
    hooks.useRuntimeOverview.mockReturnValue(failedQuery(new Error("overview denied")));
    hooks.useVitalDBBeds.mockReturnValue(failedQuery(new Error("beds denied")));

    const { rerender } = renderPage(<StatusPage />);
    expect(screen.getByRole("alert")).toHaveTextContent("overview denied");

    rerender(
      <Wrapper>
        <BedsPage />
      </Wrapper>
    );
    expect(screen.getByRole("alert")).toHaveTextContent("beds denied");
  });
});

function setupDefaultHooks() {
  hooks.useRuntimeCapabilities.mockReturnValue(query(capabilities()));
  hooks.useRuntimeOverview.mockReturnValue(query(overview()));
  hooks.useRuntimeSettings.mockReturnValue(query(settings()));
  hooks.useVitalDBRecorders.mockReturnValue(query(recorders()));
  hooks.useVitalDBBeds.mockReturnValue(query(beds()));
  hooks.useRuntimeEvents.mockReturnValue(query(events()));
  hooks.useHostLogs.mockReturnValue(query({ text: "line one\nline two" }));
  hooks.useHostBackups.mockReturnValue(query([{ path: "/tmp/backup-a", sizeBytes: 2048 }]));
  hooks.useRedisBackups.mockReturnValue(query([{ path: "/tmp/redis-a", sizeBytes: 1024 }]));
  hooks.useTestKitStatus.mockReturnValue(query(testKitStatus()));

  for (const mock of [
    hooks.useApplyRuntimeSettings,
    hooks.useApplyUpdateBundle,
    hooks.useCreateRedisBackup,
    hooks.useCreateTestKitBeds,
    hooks.useDeleteHostBackup,
    hooks.useDeleteTestKitBeds,
    hooks.useDeleteTestKitOrphanVRecorder,
    hooks.useExportHostLogs,
    hooks.useRepairDatastore,
    hooks.useRepairProxy,
    hooks.useRepairRuntime,
    hooks.useRepairVMDisk,
    hooks.useResetTestKitBeds,
    hooks.useResetTestKitVirtualRecorders,
    hooks.useRestartTestKitVirtualRecorders,
    hooks.useRollbackBackup,
    hooks.useStartRuntimeServices,
    hooks.useStartTestKitVirtualRecorders,
    hooks.useStopRuntimeServices,
    hooks.useSummarizeUpdateBundle,
    hooks.useUninstallRuntime,
    hooks.useVerifyUpdateBundle
  ]) {
    mock.mockReturnValue(pendingMutation());
  }

  hooks.useSessionTestKitAction.mockImplementation(() => pendingMutation());
}

function capabilities() {
  return {
    canApplySettings: true,
    canApplyRuntimeSettings: true,
    canControlRecovery: true,
    canControlRuntimeServices: true,
    canEditLocalFiles: true,
    canEditNetworkExposure: true,
    canEditVMResources: true,
    canExportLogs: true,
    canOpenLocalFiles: true,
    canRollback: true,
    canUninstallRuntime: true,
    canUseTestTools: true
  };
}

function overview() {
  return {
    settings: {
      proxyPort: 18080,
      runtimeControlPort: 18321,
      vitalFilesDirectory: "/Users/shared/vital"
    },
    status: {
      runtimeState: "healthy",
      operation: "idle",
      runtimeVersion: "1.2.3",
      vmIP: "192.168.64.8",
      proxyPort: 18080,
      startedAt: "2026-05-31T00:00:00Z",
      runtimeControlStartedAt: "2026-05-31T00:00:00Z",
      guestHTTP: "HTTP 200",
      hostProxyHTTP: "HTTP 200",
      runtimeControlHTTP: "HTTP 200",
      vmServiceLoaded: true,
      proxyServiceLoaded: true,
      watchdogServiceLoaded: true,
      guestLogSyncServiceLoaded: true,
      cpuUsagePercent: 12,
      dataDirectoryStats: { fileCount: 2, sizeBytes: 4096 },
      memory: { usedBytes: 2048, totalBytes: 4096 },
      systemDisk: { availableBytes: 8192, totalBytes: 16384 },
      dataStorage: { usedBytes: 1024, totalBytes: 2048 },
      containerObservation: { auditProxyHTTP: "HTTP 200" },
      failureReasons: []
    },
    vitalDBObservation: { ready: true },
    vitalRecorder: {
      observedAt: "2026-05-31T01:00:00Z",
      activeConnections: 1,
      knownRecorders: 1,
      onlineRecorders: 1,
      staleRecorders: 0,
      knownBeds: 1,
      recorderAnomalies: 0
    }
  };
}

function settings() {
  return {
    cpuCount: 2,
    memoryGiB: 4,
    diskGiB: 20,
    minimumDiskGiB: 20,
    proxyPort: 18080,
    runtimeControlPort: 18321,
    publicHost: "host.local",
    publicPort: 18080,
    vitalFilesDirectory: "/Users/shared/vital",
    redisBackupRetentionCount: 7,
    startOnBoot: true,
    startOnBootConfigurable: true,
    autoRecoveryEnabled: true,
    preventSystemSleep: true,
    restartAfterSave: true,
    readIssues: [
      {
        source: "guestRuntimeConfig",
        message: "permission denied"
      }
    ]
  };
}

function recorders() {
  return {
    updatedAt: "2026-05-31T01:00:00Z",
    recorders: [
      {
        vrcode: "VR_A",
        status: "online",
        lastIP: "192.168.64.20",
        version: "1.0",
        bedID: "bed-1",
        bedName: "OR-1",
        patientConnected: true,
        firstSeenAt: "2026-05-31T00:00:00Z",
        lastSeenAt: "2026-05-31T01:00:00Z",
        observationCount: 3,
        currentAnomalyCount: 0,
        presentInLatestObservation: true,
        activityTimeline: [
          {
            observedAt: "2026-05-31T00:59:00Z",
            messageCount: 3,
            byteCount: 2048,
            roomCount: 1,
            bytesPerSecond: 128
          }
        ]
      }
    ],
    beds: beds(),
    activityHistory: {}
  };
}

function beds() {
  return [
    {
      bedID: "bed-1",
      name: "OR-1",
      vrcode: "VR_A",
      status: "online",
      patientConnected: true,
      firstSeenAt: "2026-05-31T00:00:00Z",
      lastSeenAt: "2026-05-31T01:00:00Z",
      observationCount: 2,
      currentAnomalyCount: 0
    }
  ];
}

function events() {
  return {
    events: [
      {
        id: "event-1",
        timestamp: "2026-05-31T01:00:00Z",
        eventType: "update",
        status: "healthy",
        operation: "apply",
        source: "runtime",
        message: "runtime updated",
        failureReasons: []
      }
    ],
    nextCursor: null,
    matchingCount: 1
  };
}

function testKitStatus() {
  return {
    enabled: true,
    state: "running",
    serviceName: "testkit",
    apiBaseURL: "http://testkit.local",
    recorderTargetURL: "http://edge/",
    startedAt: "2026-05-31T00:00:00Z",
    activeSession: null,
    sessions: [testKitSession("running")],
    beds: [{ roomName: "OR-1", bedId: "bed-1" }],
    lastError: null
  };
}

function testKitSession(state: string) {
  return {
    id: "session-1",
    state,
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
    createdAt: "2026-05-31T00:00:00Z",
    startedAt: "2026-05-31T00:00:00Z",
    stoppedAt: null,
    messagesSent: 5,
    bytesSent: 2048,
    lastError: null,
    cleanupErrors: [],
    recorders: []
  };
}
