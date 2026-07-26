import { fireEvent, render, screen, within } from "@testing-library/react";
import type { PropsWithChildren, ReactElement } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";
import { AppSettingsProvider } from "@/config/AppSettingsContext";

const hooks = vi.hoisted(() => ({
  useApplyRuntimeAdminPassword: vi.fn(),
  useApplyRuntimeRedisRelaySettings: vi.fn(),
  useApplyRuntimeProductSettings: vi.fn(),
  useApplyRuntimePlatformSettings: vi.fn(),
  useApplyUpdateBundle: vi.fn(),
  useCreateRedisBackup: vi.fn(),
  useCreateRuntimeDataBackup: vi.fn(),
  useDeleteHostBackup: vi.fn(),
  useDeleteRuntimeDataBackup: vi.fn(),
  useDeleteVitalDBBeds: vi.fn(),
  useDeleteVitalDBRecorders: vi.fn(),
  useDeleteUpdateBackup: vi.fn(),
  useCreatePlatformSupportExport: vi.fn(),
  useCreateLabBeds: vi.fn(),
  useCreateLabRecorders: vi.fn(),
  useCreateLabSession: vi.fn(),
  useDeleteLabBeds: vi.fn(),
  useDeleteLabRecorders: vi.fn(),
  useRuntimeStack: vi.fn(),
  useRuntimeServiceResources: vi.fn(),
  useHideVitalDBBeds: vi.fn(),
  useHideVitalDBRecorders: vi.fn(),
  useHostBackups: vi.fn(),
  useHostLogs: vi.fn(),
  useLabBeds: vi.fn(),
  useLabRecorders: vi.fn(),
  useLabScenarios: vi.fn(),
  useLabSession: vi.fn(),
  useLabSessions: vi.fn(),
  useLabVitalFiles: vi.fn(),
  useReplayLabVitalFile: vi.fn(),
  useResetLabBeds: vi.fn(),
  useResetLabRecorders: vi.fn(),
  useRedisBackups: vi.fn(),
  useRepairDatastore: vi.fn(),
  useRecorderObservabilityDetail: vi.fn(),
  useRecorderObservabilityTimeline: vi.fn(),
  useRecorderObservabilityIncidents: vi.fn(),
  useRestartRuntimeProvider: vi.fn(),
  useRestartGuestService: vi.fn(),
  useRollbackBackup: vi.fn(),
  useRollbackRelease: vi.fn(),
  useRestoreRuntimeDataBackup: vi.fn(),
  useControlCapabilities: vi.fn(),
  useRuntimeDataBackups: vi.fn(),
  useRuntimeEvents: vi.fn(),
  usePlatformOperationState: vi.fn(),
  usePlatformWorkflow: vi.fn(),
  useLatestVitalDBObservation: vi.fn(),
  usePlatformState: vi.fn(),
  useRuntimeProductSettings: vi.fn(),
  useRuntimePlatformSettings: vi.fn(),
  useRuntimeRedisRelaySettings: vi.fn(),
  useStartLabSession: vi.fn(),
  useStartLabRecorder: vi.fn(),
  useStartGuestService: vi.fn(),
  useStopGuestService: vi.fn(),
  useStopLabSession: vi.fn(),
  useFinishLabSession: vi.fn(),
  useStopLabRecorder: vi.fn(),
  useSummarizeUpdateBundle: vi.fn(),
  useUnhideVitalDBBeds: vi.fn(),
  useUnhideVitalDBRecorders: vi.fn(),
  useUploadLabVitalFiles: vi.fn(),
  useVerifyUpdateBundle: vi.fn(),
  useVitalDBBeds: vi.fn(),
  useVitalDBRecorderActivity: vi.fn(),
  useVitalDBRecorderVitalFiles: vi.fn(),
  useVitalDBRelationships: vi.fn(),
  useVitalDBRecorders: vi.fn(),
  useReleaseInfo: vi.fn(),
  useInstallInfo: vi.fn(),
  useUninstallRuntime: vi.fn()
}));

vi.mock("@/console/hooks", () => hooks);

import { AdvancedPage } from "./advanced/AdvancedPage";
import { BedsPage } from "./beds/BedsPage";
import { DangerZonePage } from "./danger-zone/DangerZonePage";
import { LabPage } from "./lab/LabPage";
import { LogsPage } from "./logs/LogsPage";
import { InfoPage } from "./info/InfoPage";
import { ObservabilityPage } from "./observability/ObservabilityPage";
import { RecordersPage } from "./recorders/RecordersPage";
import { SettingsPage } from "./settings/SettingsPage";
import { StatusPage } from "./status/StatusPage";
import { UpdatePage } from "./update/UpdatePage";

const commandResult = {
  result: {
    exitCode: 0,
    stdout: "ok",
    stderr: "",
    outputIssues: [],
    executionIssue: null
  }
};

const completedApplyWorkflow = {
  schemaVersion: 1 as const,
  operationId: "update-apply-1",
  kind: "update-apply" as const,
  state: "completed" as const,
  startedAt: "2026-07-01T00:00:00Z",
  updatedAt: "2026-07-01T00:00:01Z",
  release: null,
  artifact: null,
  failure: null
};

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

function selectVitalRecorder(vrcode: string) {
  const recorderPanel = screen
    .getByRole("heading", { name: "Recorders" })
    .closest("section")!;
  const recorderTable = within(recorderPanel).getByRole("table");
  fireEvent.click(within(recorderTable).getByText(vrcode).closest("tr")!);
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

afterEach(() => {
  vi.useRealTimers();
});

describe("runtime console pages", () => {
  it("renders status metrics without using container observation as recorder ingress source", () => {
    renderPage(<StatusPage />);

    expect(screen.getByText("Platform health")).toBeInTheDocument();
    expect(screen.getByText("Healthy")).toBeInTheDocument();
    expect(screen.getByText("VitalServer")).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "http://vital.example.test/" })
    ).toHaveAttribute("href", "http://vital.example.test/");
    expect(
      screen.getByRole("link", { name: "http://console.example.test/" })
    ).toHaveAttribute("href", "http://console.example.test/");
    expect(
      screen.getByText("draining, 5 pending, 9.0 KiB, oldest 34s, replay lag 12s")
    ).toBeInTheDocument();
    expect(screen.getByText("2 active / 3 WebSockets")).toBeInTheDocument();
    expect(
      screen.getByText("in 2.0 MiB/s, replay 1.0 MiB/s, queue +1.0 MiB/s")
    ).toBeInTheDocument();
    expect(
      screen.getByText("5.0 MiB/s, adaptive 1.0 MiB/s-10.0 MiB/s, guard unavailable, 500 items/tick, concurrency 8")
    ).toBeInTheDocument();
    expect(screen.getByText("/var/lib/vitalserver/vital-files")).toBeInTheDocument();
    expect(screen.queryByText("VitalServer memory")).not.toBeInTheDocument();
    expect(screen.queryByText("Recorder ingress memory")).not.toBeInTheDocument();
    expect(screen.queryByText("Redis memory")).not.toBeInTheDocument();
    expect(screen.queryByText("100.0 MiB / 512.0 MiB")).not.toBeInTheDocument();
    expect(screen.getByText(/2.0 KiB \/ 4.0 KiB/)).toBeInTheDocument();
  });

  it("renders same-host service URLs as browser-reachable links", () => {
    hooks.useRuntimeProductSettings.mockReturnValue(query({
      state: "loaded",
      settings: {
        ...productSettings(),
        vitalServerURL: "",
        remoteConsoleURL: "",
        publicHost: "",
        publicPort: 18080
      },
      readError: null
    }));

    renderPage(<StatusPage />);

    const hostname = globalThis.location.hostname;
    expect(
      screen.getByRole("link", { name: `http://${hostname}:18080/` })
    ).toHaveAttribute("href", `http://${hostname}:18080/`);
    expect(screen.queryByRole("link", { name: /18321/ })).not.toBeInTheDocument();
  });

  it("does not infer missing status endpoint or resource fields", () => {
    hooks.useRuntimeProductSettings.mockReturnValue(query({
      state: "unavailable",
      settings: null,
      readError: "settings unavailable"
    }));
    hooks.usePlatformState.mockReturnValue(
      query({
        ...platformState(),
        proxyPort: undefined,
        dataDirectoryStats: {
          sizeBytes: 4096
        }
      })
    );
    hooks.useRuntimeStack.mockReturnValue(
      query({
        ...guestStackStatus(),
        cpuUsagePercent: undefined,
        memory: { usedBytes: 2048 },
        systemDisk: undefined
      })
    );

    renderPage(<StatusPage />);

    expect(screen.getAllByText("Not reported").length).toBeGreaterThanOrEqual(3);
    expect(screen.getByText("File count not reported · 4.0 KiB")).toBeInTheDocument();
    expect(screen.getByText("Incomplete resource usage")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /18080/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /18321/ })).not.toBeInTheDocument();
  });

  it("keeps a failed Platform settings read distinct from a missing data directory", () => {
    hooks.useRuntimePlatformSettings.mockReturnValue(query({
      state: "failed",
      settings: null,
      readIssues: [],
      readError: "host settings database is unreadable"
    }));

    renderPage(<StatusPage />);

    expect(screen.getByText("Read failed")).toBeInTheDocument();
    expect(screen.getByText(/host settings database is unreadable/)).toBeInTheDocument();
  });


  it("edits and applies Runtime-owned product settings", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimeProductSettings.mockReturnValue(apply);

    renderPage(<SettingsPage />);

    expect(screen.getByText("Advertised product endpoints")).toBeInTheDocument();
    expect(screen.getByText("Recorder load control")).toBeInTheDocument();
    expect(screen.queryByText("VM resources")).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Advertised port"), {
      target: { value: "8080" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    expect(apply.mutate).toHaveBeenCalledWith({
      settings: expect.objectContaining({ publicPort: 8080 })
    });
  });

  it("keeps Platform-owned Host settings separate and applies only mutable fields", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimePlatformSettings.mockReturnValue(apply);

    renderPage(<SettingsPage />);

    expect(screen.getByText("Platform settings")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("CPU count"), {
      target: { value: "6" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Apply Host settings" }));

    expect(apply.mutate).toHaveBeenCalledWith({
      settings: expect.objectContaining({ cpuCount: 6, diskGiB: 128 })
    });
    expect(apply.mutate.mock.calls[0]?.[0].settings).not.toHaveProperty("minimumDiskGiB");
    expect(apply.mutate.mock.calls[0]?.[0].settings).not.toHaveProperty("startOnBootConfigurable");
  });

  it("does not apply Runtime settings when the Runtime Controller omits settings:apply", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimeProductSettings.mockReturnValue(apply);
    hooks.useControlCapabilities.mockReturnValue(
      query({
        ...capabilities(),
        canApplyRuntimeProductSettings: false
      })
    );

    renderPage(<SettingsPage />);

    const button = screen.getByRole("button", { name: "Apply" });
    expect(button).toBeDisabled();
    fireEvent.click(button);
    expect(apply.mutate).not.toHaveBeenCalled();
  });

  it("replaces the Runtime administrator password without placing it in settings", () => {
    const applyAdmin = pendingMutation();
    hooks.useApplyRuntimeAdminPassword.mockReturnValue(applyAdmin);

    renderPage(<SettingsPage />);

    fireEvent.change(screen.getByLabelText("New administrator password"), {
      target: { value: "new-admin-secret" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Replace password" }));

    expect(applyAdmin.mutate).toHaveBeenCalledWith(
      { password: "new-admin-secret" },
      expect.objectContaining({ onSuccess: expect.any(Function) })
    );
  });

  it("applies Runtime-owned Redis Relay settings without reading a password", () => {
    const applyRelay = pendingMutation();
    hooks.useApplyRuntimeRedisRelaySettings.mockReturnValue(applyRelay);
    renderPage(<SettingsPage />);

    expect(screen.getByText("Password currently configured: no")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Target URL"), {
      target: { value: "redis://relay.example:6379/1" }
    });
    fireEvent.change(screen.getByLabelText("New target password"), {
      target: { value: "relay-secret" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Apply relay" }));

    expect(applyRelay.mutate).toHaveBeenCalledWith(
      expect.objectContaining({
        target: expect.objectContaining({
          url: "redis://relay.example:6379/1",
          password: "relay-secret"
        })
      })
    );
  });

  it("keeps unavailable Runtime settings distinct from an empty settings form", () => {
    hooks.useRuntimeProductSettings.mockReturnValue(query({
      state: "unavailable",
      settings: null,
      readError: "settings owner missing"
    }));

    renderPage(<SettingsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent("settings owner missing");
    expect(screen.queryByLabelText("Advertised port")).not.toBeInTheDocument();
  });

  it("reports invalid advanced recorder settings without applying", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimeProductSettings.mockReturnValue(apply);
    renderPage(<SettingsPage />);

    fireEvent.change(screen.getByLabelText("Recorder ingress advanced settings"), {
      target: { value: "{" }
    });

    expect(screen.getByText(/Recorder ingress settings JSON is invalid/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Apply" })).toBeDisabled();
  });

  it("renders recorder lists, filters history, and selects recorder details", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-31T01:00:30Z"));
    const hideRecorder = mutation({});
    const unhideRecorder = mutation({});
    hooks.useHideVitalDBRecorders.mockReturnValue(hideRecorder);
    hooks.useUnhideVitalDBRecorders.mockReturnValue(unhideRecorder);

    renderPage(<RecordersPage />);

    expect(screen.getByText("Known recorders")).toBeInTheDocument();
    expect(screen.getAllByText("VR_A").length).toBeGreaterThan(0);
    expect(screen.getAllByText("IP verified").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Recorder anomalies").length).toBeGreaterThan(0);
    expect(screen.getByText("Data updated")).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "Recorder Details" })
    ).not.toBeInTheDocument();
    expect(hooks.useVitalDBRecorderVitalFiles).toHaveBeenLastCalledWith(null);
    expect(hooks.useRecorderObservabilityDetail).toHaveBeenLastCalledWith(null);
    expect(hooks.useRecorderObservabilityTimeline).toHaveBeenLastCalledWith(null);
    expect(hooks.useRecorderObservabilityIncidents).toHaveBeenLastCalledWith(null);

    const recorderPanel = screen.getByRole("heading", { name: "Recorders" }).closest("section")!;
    const recorderTable = within(recorderPanel).getByRole("table");
    expect(
      within(recorderTable)
        .getAllByRole("columnheader")
        .map((header) => header.textContent)
    ).toEqual([
      "Status",
      "VRecorder",
      "Bed",
      "Last seen",
      "Device health",
      "Anomaly",
      "IP"
    ]);
    expect(within(recorderTable).queryByText("Visibility")).not.toBeInTheDocument();
    expect(within(recorderTable).queryByRole("button", { name: "Hide" })).not.toBeInTheDocument();
    expect(within(recorderTable).getByText("30s ago")).toBeInTheDocument();
    expect(within(recorderTable).getByText("Warning (1)")).toBeInTheDocument();
    expect(within(recorderTable).getByText("Report Current")).toBeInTheDocument();

    fireEvent.click(within(recorderTable).getByText("VR_A").closest("tr")!);
    expect(hooks.useVitalDBRecorderVitalFiles).toHaveBeenLastCalledWith("VR_A");
    expect(hooks.useRecorderObservabilityDetail).toHaveBeenLastCalledWith("VR_A");
    expect(hooks.useRecorderObservabilityTimeline).toHaveBeenLastCalledWith(
      expect.objectContaining({ vrcode: "VR_A", bucketSeconds: 900 })
    );
    expect(hooks.useRecorderObservabilityIncidents).toHaveBeenLastCalledWith(
      expect.objectContaining({ vrcode: "VR_A", limit: 20 })
    );

    const recorderDetails = screen
      .getByRole("heading", { name: "Recorder Details" })
      .closest("section")!;
    expect(within(recorderDetails).queryByText("Visibility")).not.toBeInTheDocument();
    expect(within(recorderDetails).getByText("Network access")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Health report")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Supported")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("52.5 °C")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Publisher buffer")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Latest reported issues")).toBeInTheDocument();
    expect(
      within(recorderDetails).getByText("System service state is not fully running")
    ).toBeInTheDocument();
    expect(
      within(recorderDetails).getByText(
        "degraded; failed units: rpi-eeprom-update.service"
      )
    ).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Last 24 hours")).toBeInTheDocument();
    expect(
      within(recorderDetails).getByText("No health report was received during this window.")
    ).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Recent incidents")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Active IP")).toBeInTheDocument();
    expect(within(recorderDetails).queryByText("Redis key")).not.toBeInTheDocument();
    expect(within(recorderDetails).queryByText("x-forwarded-for")).not.toBeInTheDocument();
    expect(within(recorderDetails).getByRole("img", { name: /Packet activity/ })).toBeInTheDocument();
    expect(within(recorderDetails).getByText("34 B/s")).toBeInTheDocument();
    expect(within(recorderDetails).queryByText("Room entries")).not.toBeInTheDocument();
    expect(within(recorderDetails).getByText("Relationship history")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Assignments")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Events")).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Vital files")).toBeInTheDocument();
    expect(
      within(recorderDetails).getByText(
        "No tracked Vital files are attributed to this VRecorder."
      )
    ).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Bed has no linked VRecorder.")).toBeInTheDocument();
    const lastSeenRow = within(recorderDetails)
      .getByText("Last seen")
      .closest(".key-value-row");
    expect(lastSeenRow).toHaveTextContent("2026-05-31");
    expect(lastSeenRow).not.toHaveTextContent("ago");

    fireEvent.click(
      within(recorderDetails).getByRole("button", { name: "Hide from list" })
    );
    expect(hideRecorder.mutate).toHaveBeenCalledWith(
      { vrcodes: ["VR_A"] },
      expect.objectContaining({ onSuccess: expect.any(Function) })
    );
    expect(
      screen.queryByRole("heading", { name: "Recorder Details" })
    ).not.toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent(
      "VR_A hidden from recorder list."
    );

    fireEvent.click(screen.getByRole("button", { name: "Undo" }));
    expect(unhideRecorder.mutate).toHaveBeenCalledWith(
      { vrcodes: ["VR_A"] },
      expect.objectContaining({ onSuccess: expect.any(Function) })
    );
    expect(
      screen.getByRole("heading", { name: "Recorder Details" })
    ).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Search VRecorders"), {
      target: { value: "missing" }
    });
    expect(
      screen.getByText("No VitalDB VRecorder observations found.")
    ).toBeInTheDocument();
  });

  it("labels hidden recorders and keeps destructive management secondary", () => {
    const hiddenRecorders = recorders();
    hiddenRecorders.recorders[0].visibility = "hidden";
    const unhideRecorder = mutation({});
    const deleteRecorder = mutation({});
    hooks.useVitalDBRecorders.mockReturnValue(query(hiddenRecorders));
    hooks.useUnhideVitalDBRecorders.mockReturnValue(unhideRecorder);
    hooks.useDeleteVitalDBRecorders.mockReturnValue(deleteRecorder);

    renderPage(<RecordersPage />);

    expect(screen.queryByText("VR_A")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("checkbox", { name: "Show hidden" }));

    const recorderPanel = screen.getByRole("heading", { name: "Recorders" }).closest("section")!;
    const recorderTable = within(recorderPanel).getByRole("table");
    expect(within(recorderTable).getByText("Hidden")).toBeInTheDocument();
    fireEvent.click(within(recorderTable).getByText("VR_A").closest("tr")!);

    const recorderDetails = screen
      .getByRole("heading", { name: "Recorder Details" })
      .closest("section")!;
    expect(within(recorderDetails).getByText("Hidden from list")).toBeInTheDocument();
    expect(within(recorderDetails).queryByText("Visibility")).not.toBeInTheDocument();
    expect(
      within(recorderDetails).getByRole("button", { name: "Show in list" })
    ).toBeInTheDocument();
    expect(within(recorderDetails).getByText("Data management")).toBeInTheDocument();
    expect(
      within(recorderDetails).getByRole("button", { name: "Delete hidden recorder" })
    ).toBeInTheDocument();

    fireEvent.click(
      within(recorderDetails).getByRole("button", { name: "Show in list" })
    );
    expect(unhideRecorder.mutate).toHaveBeenCalledWith(
      { vrcodes: ["VR_A"] },
      expect.objectContaining({ onSuccess: expect.any(Function) })
    );
  });

  it("keeps recorder details selected when hiding fails", () => {
    const hideRecorder = {
      ...pendingMutation(),
      error: new Error("visibility owner unavailable"),
      isError: true
    };
    hooks.useHideVitalDBRecorders.mockReturnValue(hideRecorder);

    renderPage(<RecordersPage />);
    selectVitalRecorder("VR_A");

    const recorderDetails = screen
      .getByRole("heading", { name: "Recorder Details" })
      .closest("section")!;
    fireEvent.click(
      within(recorderDetails).getByRole("button", { name: "Hide from list" })
    );

    expect(hideRecorder.mutate).toHaveBeenCalledWith(
      { vrcodes: ["VR_A"] },
      expect.objectContaining({ onSuccess: expect.any(Function) })
    );
    expect(
      screen.getByRole("heading", { name: "Recorder Details" })
    ).toBeInTheDocument();
    expect(screen.getByText("visibility owner unavailable")).toBeInTheDocument();
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("shows Product Lab recorders separately from VitalDB recorder observations", () => {
    hooks.useLabRecorders.mockReturnValue(query({
      state: "loaded",
      readError: null,
      recorders: [
        {
          recorderId: "lab-session-1-recorder-1",
          sessionId: "lab-session-1",
          bedId: "lab-session-1-bed-1",
          vrcode: "LAB-lab-session-1-1",
          state: "running",
          createdAt: "2026-05-31T00:00:00Z",
          updatedAt: "2026-05-31T00:00:10Z",
          messagesSent: 1,
          lastSendState: "sent",
          lastSendAt: "2026-05-31T00:00:10Z",
          lastSendError: null
        }
      ]
    }));

    renderPage(<RecordersPage />);

    expect(screen.getByText("Product Lab recorders")).toBeInTheDocument();
    expect(screen.getAllByText("LAB-lab-session-1-1").length).toBeGreaterThan(0);
    expect(screen.getAllByText("lab-session-1-recorder-1").length).toBeGreaterThan(0);
    fireEvent.click(screen.getAllByText("LAB-lab-session-1-1")[0]!);
    expect(screen.getByText("Messages")).toBeInTheDocument();
    expect(screen.getByText("Last send at")).toBeInTheDocument();
  });

  it("browses all recorder activity in twelve hour windows with one minute buckets", () => {
    hooks.useVitalDBRecorders.mockReturnValue(query(recordersWithLongActivity()));
    hooks.useVitalDBRecorderActivity.mockReturnValue(
      query(recorderActivityWindow({
        page: {
          ...recorderActivityWindow().page,
          index: 1,
          count: 2,
          windowStartedAt: "2026-05-31T04:00:00Z",
          windowEndedAt: "2026-05-31T16:00:00Z"
        }
      }))
    );

    renderPage(<RecordersPage />);
    selectVitalRecorder("VR_A");

    expect(screen.queryByLabelText("Window")).not.toBeInTheDocument();
    expect(screen.getByLabelText("Bucket")).toHaveValue("60");
    expect(
      within(screen.getByLabelText("Period")).getByRole("option", {
        name: "Last 12 hours"
      })
    ).toBeInTheDocument();
    expect(
      within(screen.getByLabelText("Period")).queryByRole("option", {
        name: "Last 24 hours"
      })
    ).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Period"), {
      target: { value: "all" }
    });

    const windowSlider = screen.getByLabelText("Window") as HTMLInputElement;
    expect(windowSlider.max).toBe("1");
    expect(windowSlider.value).toBe("1");
    fireEvent.change(windowSlider, { target: { value: "0" } });
    expect(hooks.useVitalDBRecorderActivity).toHaveBeenLastCalledWith(
      expect.objectContaining({ period: "all", pageIndex: 0 })
    );
  });

  it("shows missing recorder activity history as not reported", () => {
    hooks.useVitalDBRecorders.mockReturnValue(
      query({
        ...recorders(),
        recorders: [
          {
            ...recorders().recorders[0],
            status: "notObserved",
            activityTimeline: null
          }
        ]
      })
    );
    hooks.useVitalDBRecorderActivity.mockReturnValue(
      query(recorderActivityWindow({ state: "empty", buckets: [] }))
    );

    renderPage(<RecordersPage />);
    selectVitalRecorder("VR_A");

    expect(screen.getAllByText("Not observed").length).toBeGreaterThan(0);
    expect(
      screen.getByText("No recent data activity has been observed for this VRecorder.")
    ).toBeInTheDocument();
    expect(screen.queryByRole("img", { name: /Packet activity/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/Last sample/)).not.toBeInTheDocument();
  });

  it("does not render recorder activity charts when activity history read failed", () => {
    hooks.useVitalDBRecorders.mockReturnValue(
      query({
        ...recorders(),
        activityHistory: {
          ...recorders().activityHistory,
          source: "unavailable",
          readError: "activity projection denied"
        }
      })
    );
    hooks.useVitalDBRecorderActivity.mockReturnValue(
      query(recorderActivityWindow({
        state: "readFailed",
        buckets: [],
        readError: "activity projection denied"
      }))
    );

    renderPage(<RecordersPage />);
    selectVitalRecorder("VR_A");

    expect(
      screen.getByText("Recorder activity data is unavailable")
    ).toBeInTheDocument();
    expect(screen.getByText(/activity projection denied/)).toBeInTheDocument();
    expect(screen.queryByRole("img", { name: /Packet activity/ })).not.toBeInTheDocument();
  });

  it("renders beds, filters rows, and shows selected bed details", () => {
    hooks.useVitalDBRecorders.mockReturnValue(failedQuery(new Error("recorders denied")));

    renderPage(<BedsPage />);

    expect(screen.getByText("Known beds")).toBeInTheDocument();
    expect(screen.getAllByText("OR-1").length).toBeGreaterThan(0);
    expect(screen.getByText("Bed Details")).toBeInTheDocument();
    expect(screen.getByText("VRecorder status")).toBeInTheDocument();
    expect(screen.getByText("VRecorder IP")).toBeInTheDocument();
    expect(screen.getAllByText(/Offline · warning/).length).toBeGreaterThan(0);
    expect(screen.getByText("Relationship history")).toBeInTheDocument();
    expect(screen.getAllByText("Assignments").length).toBeGreaterThan(0);
    expect(screen.getByText("Events")).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Search beds"), {
      target: { value: "none" }
    });
    expect(
      screen.getByText("No VitalDB bed observations found.")
    ).toBeInTheDocument();
  });

  it("shows Product Lab beds separately from VitalDB bed observations", () => {
    hooks.useLabBeds.mockReturnValue(query({
      state: "loaded",
      readError: null,
      beds: [
        {
          bedId: "lab-session-1-bed-1",
          sessionId: "lab-session-1",
          name: "Lab OR-1",
          state: "accepted",
          createdAt: "2026-05-31T00:00:00Z",
          updatedAt: "2026-05-31T00:00:10Z"
        },
        {
          bedId: "lab-session-1-bed-2",
          sessionId: "lab-session-1",
          name: "Lab OR-2",
          state: "running",
          createdAt: "2026-05-31T00:01:00Z",
          updatedAt: "2026-05-31T00:01:10Z"
        }
      ]
    }));

    renderPage(<BedsPage />);

    expect(screen.getByText("Product Lab beds")).toBeInTheDocument();
    expect(screen.getByText("Product Lab Bed Details")).toBeInTheDocument();
    expect(screen.getAllByText("Lab OR-1").length).toBeGreaterThan(0);
    expect(screen.getAllByText("lab-session-1-bed-1").length).toBeGreaterThan(0);

    fireEvent.click(screen.getAllByText("Lab OR-2")[0]);

    expect(screen.getAllByText("Lab OR-2").length).toBeGreaterThan(1);
    expect(screen.getAllByText("lab-session-1-bed-2").length).toBeGreaterThan(1);
    expect(screen.getByText("Created")).toBeInTheDocument();
    expect(screen.getAllByText("Updated").length).toBeGreaterThan(0);
  });

  it("does not render missing bed query data as an empty bed list", () => {
    hooks.useVitalDBBeds.mockReturnValue(query(undefined));

    renderPage(<BedsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Bed history response is incomplete"
    );
    expect(
      screen.queryByText("No VitalDB bed observations found.")
    ).not.toBeInTheDocument();
  });

  it("renders observability events and reacts to filters", () => {
    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Observation pipeline")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Recorder anomalies" })).toBeInTheDocument();
    expect(screen.getByText("duplicate-ip")).toBeInTheDocument();
    expect(screen.getByText("10.0.0.10")).toBeInTheDocument();
    expect(screen.getByText("runtime updated")).toBeInTheDocument();
    expect(screen.getByText("runtime reconcile failed")).toBeInTheDocument();
    expect(
      screen.getByText("runtime reconcile failed").compareDocumentPosition(
        screen.getByText("runtime updated")
      ) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();

    fireEvent.change(screen.getByLabelText("Period"), { target: { value: "7d" } });
    fireEvent.change(screen.getByLabelText("Filter"), {
      target: { value: "operation-failed" }
    });
    fireEvent.change(screen.getByLabelText("Limit"), { target: { value: "100" } });

    expect(hooks.useRuntimeEvents).toHaveBeenCalled();
  });

  it("does not present an unknown paged runtime event total as exact", () => {
    hooks.useRuntimeEvents.mockReturnValue(query({
      ...events(),
      nextCursor: "guest-ledger-page-2",
      matchingCount: null
    }));

    renderPage(<ObservabilityPage />);

    expect(screen.getAllByText("2 shown · more available")).toHaveLength(2);
    expect(screen.queryByText("2 events")).not.toBeInTheDocument();
  });

  it("does not present an unavailable runtime event total as exact", () => {
    hooks.useRuntimeEvents.mockReturnValue(query({
      ...events(),
      matchingCount: null
    }));

    renderPage(<ObservabilityPage />);

    expect(screen.getAllByText("2 shown · total unavailable")).toHaveLength(2);
    expect(screen.queryByText("2 events")).not.toBeInTheDocument();
  });

  it("keeps observability read failures distinct from empty data", () => {
    hooks.useLatestVitalDBObservation.mockReturnValue(query({
      state: "failed",
      observation: null,
      readError: "sqlite denied"
    }));
    hooks.usePlatformState.mockReturnValue(
      query({
        ...platformState(),
        services: platformState().services.filter((service) => service.role !== "log-sync")
      })
    );
    hooks.useRuntimeEvents.mockReturnValue(query({ nextCursor: null }));

    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Failed")).toBeInTheDocument();
    expect(screen.getAllByText("Not reported").length).toBeGreaterThan(0);
    expect(screen.getByText("VitalDB observation read failed.")).toBeInTheDocument();
    expect(screen.getByText("Runtime event response is incomplete")).toBeInTheDocument();
    expect(screen.getByText("Runtime events response is missing events.")).toBeInTheDocument();
    expect(
      screen.queryByText("No runtime events were found for this period.")
    ).not.toBeInTheDocument();
  });

  it("shows VitalDB source read issues instead of no anomaly fallback", () => {
    const baseOverview = overview();
    const vitalDBObservation = {
      ...baseOverview.vitalDBObservation,
      anomalies: [],
      readIssues: [
        {
          source: "proxyAccessLog",
          message: "proxy access log is not valid UTF-8"
        }
      ]
    };
    hooks.useLatestVitalDBObservation.mockReturnValue(query({
      state: "loaded",
      observation: vitalDBObservation,
      readError: null
    }));

    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Recorder anomaly details are incomplete")).toBeInTheDocument();
    expect(screen.getByText(/proxyAccessLog/)).toBeInTheDocument();
    expect(screen.getByText("Recorder anomaly records are incomplete.")).toBeInTheDocument();
    expect(
      screen.queryByText("No recorder anomalies were reported.")
    ).not.toBeInTheDocument();
  });

  it("groups repeated VitalDB audit event read issues", () => {
    const baseOverview = overview();
    const vitalDBObservation = {
      ...baseOverview.vitalDBObservation,
      anomalies: [],
      readIssues: [
        {
          source: "auditEvents",
          message: "event 2 was skipped: send_data event is missing rooms_count/roomsCount"
        },
        {
          source: "auditEvents",
          message: "event 4 was skipped: send_data event is missing rooms_count/roomsCount"
        },
        {
          source: "auditEvents",
          message: "event 5 was skipped: send_data event is missing rooms_count/roomsCount"
        }
      ]
    };
    hooks.useLatestVitalDBObservation.mockReturnValue(query({
      state: "loaded",
      observation: vitalDBObservation,
      readError: null
    }));

    renderPage(<ObservabilityPage />);

    expect(
      screen.getByText(/auditEvents: 3 events were skipped: send_data event is missing rooms_count\/roomsCount/)
    ).toBeInTheDocument();
    expect(
      screen.queryByText(/event 2 was skipped: send_data event is missing rooms_count\/roomsCount; auditEvents: event 4/)
    ).not.toBeInTheDocument();
  });

  it("keeps loaded VitalDB observation read issues visible", () => {
    const baseOverview = overview();
    const vitalDBObservation = {
      ...baseOverview.vitalDBObservation,
      anomalies: [],
      readIssues: []
    };
    hooks.useLatestVitalDBObservation.mockReturnValue(query({
      state: "loaded",
      observation: vitalDBObservation,
      readError: "projection=read failed"
    }));

    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Ready with issues")).toBeInTheDocument();
    expect(screen.getByText("Recorder anomaly details are incomplete")).toBeInTheDocument();
    expect(screen.getByText(/projection=read failed/)).toBeInTheDocument();
    expect(
      screen.queryByText("No recorder anomalies were reported.")
    ).not.toBeInTheDocument();
  });

  it("does not use event type as fallback event message or source", () => {
    hooks.useRuntimeEvents.mockReturnValue(
      query({
        events: [
          {
            schemaVersion: 1,
            id: "event-missing-message",
            source: "",
            timestamp: "2026-05-31T01:00:00Z",
            eventType: "operation-completed",
            operationId: "operation-1",
            operationService: "runtime-settings",
            operationCommand: "apply-settings",
            operationState: "completed",
            message: "",
            failure: null
          }
        ],
        nextCursor: null,
        matchingCount: 1
      })
    );

    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Message not reported")).toBeInTheDocument();
    expect(screen.getByText("source not reported")).toBeInTheDocument();
  });

  it("reads logs and creates a managed support bundle", () => {
    const exportLogs = mutation({
      ...completedApplyWorkflow,
      operationId: "support-export-1",
      kind: "support-export" as const,
      artifact: {
        path: "/var/lib/vitalserver/support/support.zip",
        sha256: "a".repeat(64),
        sizeBytes: 42
      }
    });
    hooks.useCreatePlatformSupportExport.mockReturnValue(exportLogs);

    renderPage(<LogsPage />);

    expect(screen.getByText(/line one/)).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Source"), {
      target: { value: "helperMessage" }
    });
    fireEvent.change(screen.getByLabelText("Lines"), { target: { value: "100" } });
    fireEvent.click(screen.getByRole("checkbox", { name: "Live" }));
    fireEvent.click(screen.getByRole("button", { name: "Create Support Bundle" }));

    expect(exportLogs.mutate).toHaveBeenCalledWith();
    expect(screen.getByText(/\/var\/lib\/vitalserver\/support\/support.zip/)).toBeInTheDocument();
  });

  it("does not render missing log response data as an empty log", () => {
    hooks.useHostLogs.mockReturnValue(query(undefined));

    renderPage(<LogsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Log response is incomplete"
    );
    expect(
      screen.queryByText("No log lines are available for this source.")
    ).not.toBeInTheDocument();
  });

  it("renders explicit empty log text as an empty log", () => {
    hooks.useHostLogs.mockReturnValue(query({ text: "" }));

    renderPage(<LogsPage />);

    expect(
      screen.getByText("No log lines are available for this source.")
    ).toBeInTheDocument();
  });

  it("shows log export capability read failure separately from unsupported export", () => {
    hooks.useControlCapabilities.mockReturnValue(
      failedQuery(new Error("capabilities denied"))
    );

    renderPage(<LogsPage />);

    expect(screen.getByText("Failed to read log streaming capability")).toBeInTheDocument();
    expect(screen.getByText("Failed to read export capability")).toBeInTheDocument();
    expect(screen.getAllByRole("alert")).toHaveLength(2);
    expect(screen.getAllByRole("alert")[0]).toHaveTextContent("capabilities denied");
    expect(screen.getByRole("button", { name: "Create Support Bundle" })).toBeDisabled();
  });

  it("shows unsupported log export as explicit unsupported capability", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({ ...capabilities(), canExportLogs: false })
    );

    renderPage(<LogsPage />);

    expect(
      screen.getByText("Log export is not supported by this Runtime Control API.")
    ).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create Support Bundle" })).toBeDisabled();
  });

  it("does not request logs when log streaming is unsupported", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({ ...capabilities(), canStreamLogs: false })
    );

    renderPage(<LogsPage />);

    expect(
      screen.getByText("Log streaming is not supported by this Runtime Control API.")
    ).toBeInTheDocument();
    expect(hooks.useHostLogs).toHaveBeenCalledWith(
      expect.objectContaining({ enabled: false })
    );
    expect(screen.getByRole("button", { name: "Refresh" })).toBeDisabled();
  });

  it("does not render missing log export capability as unsupported export", () => {
    hooks.useControlCapabilities.mockReturnValue(query(undefined));

    renderPage(<LogsPage />);

    expect(
      screen.getByText("Log streaming capability response is incomplete")
    ).toBeInTheDocument();
    expect(
      screen.getByText("Export capability response is incomplete")
    ).toBeInTheDocument();
    expect(
      screen.queryByText("Log export is not supported by this Runtime Control API.")
    ).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create Support Bundle" })).toBeDisabled();
  });

  it("runs update inspection, verification, and apply actions", () => {
    const summarize = pendingMutation();
    const verify = mutation({
      ...completedApplyWorkflow,
      operationId: "update-verify-1",
      kind: "update-verify" as const
    });
    const apply = mutation(completedApplyWorkflow);
    hooks.useSummarizeUpdateBundle.mockReturnValue(summarize);
    hooks.useVerifyUpdateBundle.mockReturnValue(verify);
    hooks.useApplyUpdateBundle.mockReturnValue(apply);

    renderPage(<UpdatePage />);

    fireEvent.change(screen.getByLabelText("Offline bundle"), {
      target: { value: "/tmp/update.tar.gz" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Inspect" }));
    fireEvent.click(screen.getByRole("button", { name: "Check Integrity" }));
    fireEvent.click(screen.getByRole("button", { name: "Apply Bundle" }));

    expect(summarize.mutate).toHaveBeenCalledWith("/tmp/update.tar.gz");
    expect(verify.mutate).toHaveBeenCalledWith("/tmp/update.tar.gz");
    expect(apply.mutate).toHaveBeenCalledWith("/tmp/update.tar.gz");
    expect(screen.getByText(/Helper is relaunching/)).toBeInTheDocument();
  });

  it("renders Platform release, installation, and bundled service information", () => {
    renderPage(<InfoPage />);

    expect(screen.getByText("Product information")).toBeInTheDocument();
    expect(screen.getByText("helper-1.0.0")).toBeInTheDocument();
    expect(screen.getByText("runtime.example")).toBeInTheDocument();
    expect(screen.getAllByText("ghcr.io/tirosh/app:1").length).toBeGreaterThan(0);
  });

  it("keeps update apply disabled when the Platform trust policy is verify-only", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({ ...capabilities(), canApplyBundle: false })
    );

    renderPage(<UpdatePage />);

    fireEvent.change(screen.getByLabelText("Offline bundle"), {
      target: { value: "/tmp/update.tar.gz" }
    });
    expect(screen.getByRole("button", { name: "Check Integrity" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Apply Bundle" })).toBeDisabled();
    expect(
      screen.getByText(
        "This 0.2.1 build cannot apply updates because trusted publisher verification is unavailable.",
      ),
    ).toBeInTheDocument();
  });

  it("treats an absent Platform workflow as an initial state, not an error", () => {
    hooks.usePlatformWorkflow.mockReturnValue(query({
      state: "missing",
      operation: null,
      readError: null
    }));

    renderPage(<UpdatePage />);

    expect(screen.getByText("No Platform workflow has run.")).toBeInTheDocument();
    expect(screen.queryByText("Platform workflow is unavailable")).not.toBeInTheDocument();
  });

  it("schedules an owner-selected Platform release rollback", () => {
    const rollback = pendingMutation();
    hooks.useRollbackRelease.mockReturnValue(rollback);

    renderPage(<UpdatePage />);

    fireEvent.click(screen.getByRole("button", { name: "Rollback Release" }));
    expect(rollback.mutate).toHaveBeenCalledWith();
  });

  it("renders advanced recovery controls and dispatches selected actions", () => {
    const applySettings = pendingMutation();
    const rollback = pendingMutation();
    const createRedisBackup = pendingMutation();
    const createRuntimeDataBackup = pendingMutation();
    const restoreRuntimeDataBackup = pendingMutation();
    const startGuestService = pendingMutation();
    const stopGuestService = pendingMutation();
    const restartGuestService = pendingMutation();
    const restartRuntimeProvider = pendingMutation();
    const repairDatastore = pendingMutation();
    hooks.useApplyRuntimeProductSettings.mockReturnValue(applySettings);
    hooks.useRollbackBackup.mockReturnValue(rollback);
    hooks.useCreateRedisBackup.mockReturnValue(createRedisBackup);
    hooks.useCreateRuntimeDataBackup.mockReturnValue(createRuntimeDataBackup);
    hooks.useRestoreRuntimeDataBackup.mockReturnValue(restoreRuntimeDataBackup);
    hooks.useStartGuestService.mockReturnValue(startGuestService);
    hooks.useStopGuestService.mockReturnValue(stopGuestService);
    hooks.useRestartGuestService.mockReturnValue(restartGuestService);
    hooks.useRestartRuntimeProvider.mockReturnValue(restartRuntimeProvider);
    hooks.useRepairDatastore.mockReturnValue(repairDatastore);

    renderPage(<AdvancedPage />);

    expect(screen.getByText("Runtime provider health")).toBeInTheDocument();
    expect(screen.getByText("Advanced network")).toBeInTheDocument();
    expect(screen.queryByText("Admin operations")).not.toBeInTheDocument();
    expect(screen.getAllByText("Sleep prevention").length).toBeGreaterThan(0);
    expect(screen.getByText("Platform services")).toBeInTheDocument();
    expect(screen.getByText("Runtime product services")).toBeInTheDocument();
    expect(screen.getByText("Access endpoints")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Reconnect Runtime Control" })
    ).toBeInTheDocument();
    expect(screen.queryByText("Redis UI service")).not.toBeInTheDocument();
    expect(screen.queryByText("Swagger UI service")).not.toBeInTheDocument();
    expect(screen.getByText("VitalServer API")).toBeInTheDocument();
    expect(screen.getByText("Runtime Control API")).toBeInTheDocument();
    expect(screen.getByText("Recorder Ingress API")).toBeInTheDocument();
    expect(screen.getByText("VitalDB Observer API")).toBeInTheDocument();
    expect(screen.getByText("apply-bundle")).toBeInTheDocument();
    expect(
      screen.getByText("install: unavailable, lease: stale, lease staleReason: expired")
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", {
        name: "http://127.0.0.1:18080/swagger/docs/macos-runtime/runtime-control.openapi.json"
      })
    ).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("VitalServer URL"), {
      target: { value: "http://127.0.0.1:18080/" }
    });
    fireEvent.click(screen.getAllByRole("button", { name: "Apply Settings" })[0]);
    fireEvent.click(screen.getByRole("row", { name: /backup-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Rollback" }));
    fireEvent.click(screen.getByRole("button", { name: "Create Redis-only Backup" }));
    fireEvent.click(screen.getByRole("button", { name: "Create Backup" }));
    fireEvent.click(screen.getByRole("row", { name: /runtime-data-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Restore Backup" }));
    fireEvent.click(screen.getByRole("button", { name: "Restart Runtime Provider" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair Data Store" }));
    fireEvent.click(screen.getAllByRole("button", { name: "Start" })[0]);
    fireEvent.click(screen.getAllByRole("button", { name: "Stop" })[0]);
    fireEvent.click(screen.getAllByRole("button", { name: "Restart" })[0]);

    expect(applySettings.mutate).toHaveBeenNthCalledWith(1, {
      settings: expect.objectContaining({
        vitalServerURL: "http://127.0.0.1:18080/",
        remoteConsoleURL: "http://console.example.test/"
      })
    });
    expect(rollback.mutate).toHaveBeenCalledWith("/tmp/backup-a");
    expect(createRedisBackup.mutate).toHaveBeenCalledWith("");
    expect(createRuntimeDataBackup.mutate).toHaveBeenCalledWith("");
    expect(restoreRuntimeDataBackup.mutate).toHaveBeenCalledWith("/tmp/runtime-data-a");
    expect(restartRuntimeProvider.mutate).toHaveBeenCalled();
    expect(repairDatastore.mutate).toHaveBeenCalled();
    expect(startGuestService.mutate).toHaveBeenCalledWith("app");
    expect(stopGuestService.mutate).toHaveBeenCalledWith("app");
    expect(restartGuestService.mutate).toHaveBeenCalledWith("app");
  });

  it("renders the selected Guest datastore result after a failed Runtime Provider restart", () => {
    const providerFailure = {
      operationId: "provider-restart-failed",
      action: "restart" as const,
      state: "failed" as const,
      provider: {
        state: "loaded" as const,
        document: {
          schemaVersion: 1,
          state: "waiting-for-hypervisor",
          operation: "restart",
          operationID: "provider-restart-failed",
          bootID: "boot-1",
          startedAt: "2026-07-12T00:00:00Z",
          updatedAt: "2026-07-12T00:00:01Z",
          deadlineAt: null,
          terminalReason: "hyperv-provider-exit",
          message: "Hyper-V did not report a running VM"
        },
        readError: null
      },
      failure: {
        kind: "launch-failed",
        message: "Runtime Provider restart failed"
      }
    };
    const datastoreRepair = {
      operationId: "datastore-repair-1",
      service: "datastore-repair",
      command: "repair-datastore" as const,
      state: "accepted" as const,
      createdAt: "2026-07-12T00:00:00Z",
      updatedAt: "2026-07-12T00:00:00Z",
      failure: null
    };
    hooks.useRestartRuntimeProvider.mockReturnValue(mutation(providerFailure));
    hooks.useRepairDatastore.mockReturnValue(mutation(datastoreRepair));

    renderPage(<AdvancedPage />);

    fireEvent.click(screen.getByRole("button", { name: "Restart Runtime Provider" }));
    expect(screen.getByText(/operationId: provider-restart-failed/)).toBeInTheDocument();
    expect(
      screen.getByText(/failure: launch-failed Runtime Provider restart failed/)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/provider lifecycle: waiting-for-hypervisor/)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/provider terminal reason: hyperv-provider-exit/)
    ).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Repair Data Store" }));
    expect(screen.getByText(/operationId: datastore-repair-1/)).toBeInTheDocument();
    expect(screen.getByText(/service: datastore-repair/)).toBeInTheDocument();
    expect(screen.queryByText(/operationId: provider-restart-failed/)).not.toBeInTheDocument();
  });

  it("keeps unsupported maintenance explicit and does not offer platform-specific repair routes", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({
        ...capabilities(),
        canControlRuntimeServices: false,
        canRepairRuntimeDatastore: false
      })
    );

    renderPage(<AdvancedPage />);

    expect(
      screen.getByRole("button", { name: "Restart Runtime Provider" })
    ).toBeDisabled();
    expect(
      screen.getByText("Runtime Provider control is not supported by this Platform Agent.")
    ).toBeInTheDocument();
    expect(
      screen.getByText("Data store repair is not supported by this Runtime Controller.")
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Repair Data Store" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Repair Proxy" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Repair VM Disk" })).not.toBeInTheDocument();
  });

  it("keeps a maintenance capability read failure distinct from unsupported maintenance", () => {
    hooks.useControlCapabilities.mockReturnValue(
      failedQuery(new Error("runtime capability endpoint unavailable"))
    );

    renderPage(<AdvancedPage />);

    expect(screen.getByText("Failed to read control capabilities")).toBeInTheDocument();
    expect(
      screen.getByText("Runtime Provider control capability could not be read.")
    ).toBeInTheDocument();
    expect(
      screen.getByText("Data store repair capability could not be read.")
    ).toBeInTheDocument();
    expect(
      screen.queryByText("Data store repair is not supported by this Runtime Controller.")
    ).not.toBeInTheDocument();
  });

  it("does not read or enable backup resources without rollback capability", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({ ...capabilities(), canRollback: false })
    );

    renderPage(<AdvancedPage />);

    expect(
      screen.getAllByText(
        "Backup and rollback operations are not supported by this Runtime Control API."
      )
    ).toHaveLength(4);
    expect(hooks.useHostBackups).toHaveBeenCalledWith(false);
    expect(hooks.useRedisBackups).toHaveBeenCalledWith(false);
    expect(hooks.useRuntimeDataBackups).toHaveBeenCalledWith(false);
    expect(screen.getByRole("button", { name: "Create Backup" })).toBeDisabled();
    expect(
      screen.getByRole("button", { name: "Create Redis-only Backup" })
    ).toBeDisabled();
  });

  it("shows Guest service read failures without falling back to compose observations", () => {
    hooks.useRuntimeStack.mockReturnValue(
      failedQuery(new Error("guest control api timed out"))
    );

    renderPage(<AdvancedPage />);

    expect(screen.getByText("Observed state and control")).toBeInTheDocument();
    expect(screen.getByText("Failed to read Runtime product services")).toBeInTheDocument();
    expect(screen.getByText("guest control api timed out")).toBeInTheDocument();
    expect(screen.queryByText("VitalDB Observer")).not.toBeInTheDocument();
  });

  it("shows Runtime service desired, observed, and resource read states from direct resources", () => {
    hooks.useRuntimeServiceResources.mockReturnValue([
      {
        service: "app",
        resource:
            {
              service: "app",
              spec: {
                state: "configured",
                desiredState: "running",
                updatedAt: "2026-05-31T01:00:00Z"
              },
              status: {
                state: "loaded",
                observedState: "running",
                observedAt: "2026-05-31T01:00:00Z"
              },
              conditions: [
                {
                  type: "Reconciled",
                  status: "true",
                  reason: "DesiredStateObserved",
                  message: "matched desired state",
                  observedAt: "2026-05-31T01:00:00Z"
                },
                {
                  type: "ResourceFresh",
                  status: "true",
                  reason: "ObservedRecently",
                  message: "resource observation is current",
                  observedAt: "2026-05-31T01:00:01Z"
                }
              ],
              lastOperationId: "op-app-1"
            },
        error: null
      },
      {
        service: "worker",
        resource:
            {
              service: "worker",
              spec: {
                state: "configured",
                desiredState: "running",
                updatedAt: "2026-05-31T01:00:00Z"
              },
              status: {
                state: "failed",
                observedState: null,
                observedAt: null,
                serviceStatus: null,
                readError: {
                  kind: "serviceStatusReadFailed",
                  message: "docker inspect failed"
                }
              },
              conditions: [],
              lastOperationId: "op-worker-2"
            },
        error: null
      },
      {
        service: "scheduler",
        resource:
            {
              service: "scheduler",
              spec: {
                state: "configured",
                desiredState: null,
                updatedAt: "2026-05-31T01:00:00Z"
              },
              status: {
                state: "loaded",
                observedState: null,
                observedAt: null
              },
              conditions: [],
              lastOperationId: null
            },
        error: null
      },
      {
        service: "postgres",
        resource: undefined,
        error: new Error("resource document decode failed")
      }
    ]);

    renderPage(<AdvancedPage />);

    expect(screen.getByRole("columnheader", { name: "Desired" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Spec" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Status read" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Observed" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Conditions" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Last operation" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Resource read" })).toBeInTheDocument();
    const appRow = screen.getByRole("row", { name: /app running healthy configured running loaded running/i });
    expect(
      within(appRow).getByText(
        "Reconciled=true DesiredStateObserved: matched desired state; ResourceFresh=true ObservedRecently: resource observation is current"
      )
    ).toBeInTheDocument();
    expect(within(appRow).getByText("op-app-1")).toBeInTheDocument();
    expect(within(appRow).getByText("OK")).toBeInTheDocument();
    const workerRow = screen.getByRole("row", {
      name: /worker Not reported Not reported configured running serviceStatusReadFailed: docker inspect failed Not reported Not reported op-worker-2 OK/i
    });
    expect(workerRow).toBeInTheDocument();
    const schedulerRow = screen.getByRole("row", {
      name: /scheduler Not reported Not reported configured Not reported loaded Not reported Not reported Not reported OK/i
    });
    expect(schedulerRow).toBeInTheDocument();
    const postgresRow = screen.getByRole("row", {
      name: /postgres Not reported Not reported Not reported Not reported Not reported Not reported Not reported Not reported resource document decode failed/i
    });
    expect(postgresRow).toBeInTheDocument();
  });

  it("shows non-loaded Runtime stack status without treating it as an empty service list", () => {
    hooks.useRuntimeStack.mockReturnValue(
      query({
        state: "failed",
        observedAt: "2026-05-31T01:00:00Z",
        services: []
      })
    );

    renderPage(<AdvancedPage />);

    expect(screen.getByText("Observed state and control")).toBeInTheDocument();
    expect(screen.getByText("Failed to read Runtime product services")).toBeInTheDocument();
    expect(screen.getByText("Runtime stack status is failed.")).toBeInTheDocument();
    expect(screen.queryByText("No Runtime product services are reported.")).not.toBeInTheDocument();
  });

  it("gates Guest service actions with Guest service control capability", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({
        ...capabilities(),
        canControlRuntimeServices: true,
        canControlGuestServices: false
      })
    );

    renderPage(<AdvancedPage />);

    expect(screen.getAllByRole("button", { name: "Start" })[0]).toBeDisabled();
    expect(screen.getAllByRole("button", { name: "Stop" })[0]).toBeDisabled();
    expect(screen.getAllByRole("button", { name: "Restart" })[0]).toBeDisabled();
  });

  it("deletes explicit backup types and keeps gated uninstall flow in danger zone", () => {
    const deleteUpdateBackup = pendingMutation();
    const deleteRuntimeDataBackup = pendingMutation();
    const uninstall = pendingMutation();
    hooks.useDeleteUpdateBackup.mockReturnValue(deleteUpdateBackup);
    hooks.useDeleteRuntimeDataBackup.mockReturnValue(deleteRuntimeDataBackup);
    hooks.useUninstallRuntime.mockReturnValue(uninstall);

    renderPage(<DangerZonePage />);

    fireEvent.click(screen.getByRole("row", { name: /backup-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Delete Update Backup" }));
    fireEvent.click(screen.getByRole("row", { name: /runtime-data-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Delete VitalServer Backup" }));
    fireEvent.change(screen.getByLabelText("Confirmation"), {
      target: { value: "CLEAN UNINSTALL" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Clean Uninstall" }));

    expect(deleteUpdateBackup.mutate).toHaveBeenCalledWith("/tmp/backup-a");
    expect(deleteRuntimeDataBackup.mutate).toHaveBeenCalledWith("/tmp/runtime-data-a");
    fireEvent.click(screen.getByRole("button", { name: "Standard Uninstall" }));
    expect(uninstall.mutate).toHaveBeenCalledTimes(2);
    expect(uninstall.mutate).toHaveBeenNthCalledWith(1, true);
    expect(uninstall.mutate).toHaveBeenNthCalledWith(2, false);
  });

  it("manages Product Lab scenarios, sessions, and vital file replay", () => {
    const createLabSession = mutation(labSessionResponse("accepted"));
    const startLabSession = mutation(labSessionResponse("running"));
    const stopLabSession = mutation(labSessionResponse("stopped"));
    const finishLabSession = mutation(labSessionResponse("finished"));
    const replayLabVitalFile = mutation(labSessionResponse("accepted"));
    hooks.useCreateLabSession.mockReturnValue(createLabSession);
    hooks.useStartLabSession.mockReturnValue(startLabSession);
    hooks.useStopLabSession.mockReturnValue(stopLabSession);
    hooks.useFinishLabSession.mockReturnValue(finishLabSession);
    hooks.useReplayLabVitalFile.mockReturnValue(replayLabVitalFile);
    const uploadLabVitalFile = mutation({
      state: "completed",
      files: [],
      failedFiles: []
    });
    hooks.useUploadLabVitalFiles.mockReturnValue(uploadLabVitalFile);

    renderPage(<LabPage />);

    fireEvent.change(screen.getByLabelText("Target URL"), {
      target: { value: "http://edge/" }
    });
    fireEvent.change(screen.getByLabelText("Recorders"), {
      target: { value: "2" }
    });
    fireEvent.change(screen.getAllByLabelText("Session name")[0]!, {
      target: { value: "Case review" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Create session" }));
    fireEvent.click(screen.getByRole("button", { name: "Start" }));
    fireEvent.click(screen.getByRole("button", { name: "Pause" }));
    fireEvent.click(screen.getByRole("button", { name: "Finish & export" }));
    const selectedFiles = [
      new File(["first"], "first.vital"),
      new File(["second"], "second.vital")
    ];
    fireEvent.change(screen.getByLabelText("Vital files to upload"), {
      target: { files: selectedFiles }
    });
    fireEvent.click(screen.getByRole("button", { name: "Upload 2 file(s)" }));
    fireEvent.click(screen.getByRole("button", { name: "Replay" }));

    expect(createLabSession.mutate).toHaveBeenCalledWith(
      {
        scenarioId: "baseline",
        name: "Case review",
        recorderCount: 2,
        targetURL: "http://edge/",
        bedIds: []
      },
      expect.any(Object)
    );
    expect(startLabSession.mutate).toHaveBeenCalledWith("lab-1", expect.any(Object));
    expect(stopLabSession.mutate).toHaveBeenCalledWith("lab-1", expect.any(Object));
    expect(finishLabSession.mutate).toHaveBeenCalledWith("lab-1", expect.any(Object));
    expect(replayLabVitalFile.mutate).toHaveBeenCalledWith(
      {
        vitalFileRelativePath: "case.vital",
        sessionName: "Vital file replay",
        targetURL: "http://edge/",
        resourceSelection: { mode: "quickCreate" },
        repeatPolicy: { mode: "once" }
      },
      expect.any(Object)
    );
    expect(uploadLabVitalFile.mutate).toHaveBeenCalledWith(
      {
        files: selectedFiles
      },
      expect.any(Object)
    );
  });

  it("shows only failed Vital File uploads after a partial batch", () => {
    hooks.useUploadLabVitalFiles.mockReturnValue(
      mutation({
        state: "partial",
        files: [
          {
            fileName: "valid.vital",
            relativePath: "valid.vital",
            sizeBytes: 42
          }
        ],
        failedFiles: [
          {
            fileName: "broken.vital",
            reason: "Vital file gzip stream is invalid."
          }
        ]
      })
    );

    renderPage(<LabPage />);

    expect(screen.getByRole("alert")).toHaveTextContent("Files that could not be uploaded");
    expect(screen.getByRole("alert")).toHaveTextContent(
      "broken.vital: Vital file gzip stream is invalid."
    );
    expect(screen.getByRole("alert")).not.toHaveTextContent("valid.vital");
  });

  it("keeps Product Lab visible but disables Lab commands when Lab capability is unavailable", () => {
    hooks.useControlCapabilities.mockReturnValue(
      query({
        ...capabilities(),
        canUseLab: false
      })
    );

    renderPage(<LabPage />);

    expect(screen.getByText("Product Lab")).toBeInTheDocument();
    expect(screen.getByText("false")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create session" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Create beds" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Create recorders" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Start" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Pause" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Finish & export" })).toBeDisabled();

    expect(screen.getByRole("button", { name: "Replay" })).toBeDisabled();
  });

  it("shows the ingress-owned archive upload projection for the selected Lab session", () => {
    const finished = labSessionResponse("finished");
    const response = {
      ...finished,
      session: {
        ...finished.session,
        archiveFinalization: {
          state: "processing" as const,
          updatedAt: "2026-05-31T00:05:00Z",
          readError: null
        }
      }
    };
    hooks.useLabSessions.mockReturnValue(query({
      state: "loaded",
      sessions: [response.session],
      readError: null
    }));
    hooks.useLabSession.mockReturnValue(query(response));

    renderPage(<LabPage />);

    expect(screen.getAllByText("Recovery artifact export").length).toBeGreaterThan(0);
    expect(screen.getAllByText("processing").length).toBeGreaterThan(0);
    expect(screen.getByText("2026-05-31T00:05:00Z")).toBeInTheDocument();
  });

  it("shows persisted Vital File replay validation failure evidence", () => {
    const base = labSessionResponse("stopped");
    const response = {
      ...base,
      session: {
        ...base.session,
        state: "failed" as const,
        failure: {
          stage: "fileValidation",
          code: "noVitalServerGraphTracks",
          message: "Vital File contains no VitalServer graph-compatible tracks.",
          failedAt: "2026-07-22T08:45:00Z"
        }
      }
    };
    hooks.useLabSessions.mockReturnValue(query({
      state: "loaded",
      sessions: [response.session],
      readError: null
    }));
    hooks.useLabSession.mockReturnValue(query(response));

    renderPage(<LabPage />);

    expect(screen.getAllByText("fileValidation").length).toBeGreaterThan(0);
    expect(screen.getAllByText("noVitalServerGraphTracks").length).toBeGreaterThan(0);
    expect(
      screen.getAllByText("Vital File contains no VitalServer graph-compatible tracks.").length
    ).toBeGreaterThan(0);
    expect(screen.getAllByText("2026-07-22T08:45:00Z").length).toBeGreaterThan(0);
  });

  it("selects a running Lab session and controls only its recorders", () => {
    const runningSession = labSessionResponse("running");
    const startLabRecorder = mutation({});
    const stopLabRecorder = mutation({});
    hooks.useLabSessions.mockReturnValue(query({
      state: "loaded",
      sessions: [runningSession.session],
      readError: null
    }));
    hooks.useLabSession.mockReturnValue(query(runningSession));
    hooks.useLabRecorders.mockReturnValue(query({
      state: "loaded",
      recorders: [
        labRecorder("recorder-running", "running"),
        labRecorder("recorder-stopped", "stopped"),
        { ...labRecorder("other-session-recorder", "running"), sessionId: "lab-2" }
      ],
      readError: null
    }));
    hooks.useStartLabRecorder.mockReturnValue(startLabRecorder);
    hooks.useStopLabRecorder.mockReturnValue(stopLabRecorder);

    renderPage(<LabPage />);

    expect(screen.getByText("Case review")).toBeInTheDocument();
    const recorderPanel = screen.getByText("Session recorders").closest("section")!;
    expect(within(recorderPanel).queryByText("other-session-recorder")).not.toBeInTheDocument();
    const startButtons = within(recorderPanel).getAllByRole("button", {
      name: "Start recorder"
    });
    const stopButtons = within(recorderPanel).getAllByRole("button", {
      name: "Stop recorder"
    });
    fireEvent.click(startButtons[1]!);
    fireEvent.click(stopButtons[0]!);

    expect(startLabRecorder.mutate).toHaveBeenCalledWith({
      sessionId: "lab-1",
      recorderId: "recorder-stopped"
    });
    expect(stopLabRecorder.mutate).toHaveBeenCalledWith({
      sessionId: "lab-1",
      recorderId: "recorder-running"
    });
  });

  it("creates a Product Lab session for explicit Lab bed IDs", () => {
    const createLabSession = mutation(labSessionResponse("accepted"));
    hooks.useCreateLabSession.mockReturnValue(createLabSession);

    renderPage(<LabPage />);

    fireEvent.change(screen.getByLabelText("Recorders"), {
      target: { value: "5" }
    });
    fireEvent.change(screen.getByLabelText("Session bed IDs"), {
      target: { value: "manual_session_1-bed-1, manual_session_1-bed-2" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Create session" }));

    expect(createLabSession.mutate).toHaveBeenCalledWith(
      {
        scenarioId: "baseline",
        name: "Lab session",
        recorderCount: 2,
        targetURL: null,
        bedIds: ["manual_session_1-bed-1", "manual_session_1-bed-2"]
      },
      expect.any(Object)
    );
  });

  it("shows page-level query errors", () => {
    hooks.usePlatformState.mockReturnValue(failedQuery(new Error("platform denied")));
    hooks.useVitalDBBeds.mockReturnValue(failedQuery(new Error("beds denied")));

    const { rerender } = renderPage(<StatusPage />);
    expect(screen.getByRole("alert")).toHaveTextContent("platform denied");

    rerender(
      <Wrapper>
        <BedsPage />
      </Wrapper>
    );
    expect(screen.getByRole("alert")).toHaveTextContent("beds denied");
  });
});

function setupDefaultHooks() {
  hooks.useControlCapabilities.mockReturnValue(query(capabilities()));
  hooks.useLatestVitalDBObservation.mockReturnValue(
    query(overview().vitalDBObservationSnapshot)
  );
  hooks.usePlatformState.mockReturnValue(query(platformState()));
  hooks.usePlatformOperationState.mockReturnValue(query(operationState()));
  hooks.usePlatformWorkflow.mockReturnValue(query({
    state: "missing",
    operation: null,
    readError: null
  }));
  hooks.useRuntimeStack.mockReturnValue(query(guestStackStatus()));
  hooks.useRuntimeServiceResources.mockReturnValue([]);
  hooks.useRuntimeProductSettings.mockReturnValue(query({
    state: "loaded",
    settings: productSettings(),
    readError: null
  }));
  hooks.useRuntimePlatformSettings.mockReturnValue(query({
    state: "loaded",
    settings: {
      cpuCount: 4,
      memoryGiB: 8,
      diskGiB: 128,
      minimumDiskGiB: 4,
      networkMode: "shared",
      bridgedInterface: null,
      proxyPort: 18080,
      runtimeControlPort: 18321,
      vitalFilesDirectory: "/var/lib/vitalserver/vital-files",
      startOnBoot: true,
      startOnBootConfigurable: true,
      autoRecoveryEnabled: true,
      preventSystemSleep: true,
      automaticBackupEnabled: true,
      backupScheduleTimes: ["03:00"],
      backupRetentionCount: 7,
      logArchiveRetentionDays: 14,
      logArchiveMaximumGiB: 10,
      restartAfterSave: false
    },
    readIssues: [],
    readError: null
  }));
  hooks.useRuntimeRedisRelaySettings.mockReturnValue(query({
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
  }));
  hooks.useVitalDBRecorders.mockReturnValue(query(recorders()));
  hooks.useVitalDBRecorderActivity.mockReturnValue(query(recorderActivityWindow()));
  hooks.useVitalDBRecorderVitalFiles.mockReturnValue(query({
    state: "loaded",
    vrcode: "VR_A",
    files: [],
    unattributedCount: 0,
    sources: {
      nativeUpload: { state: "loaded", readError: null },
      coldPathRecovery: { state: "loaded", readError: null }
    },
    readError: null
  }));
  hooks.useRecorderObservabilityDetail.mockReturnValue(
    query(recorderObservabilityDetail())
  );
  hooks.useRecorderObservabilityTimeline.mockReturnValue(query({
    state: "notReported",
    vrcode: "VR_A",
    supportState: "supported",
    timeBasis: "receivedAt",
    query: {
      from: "2026-07-23T00:00:00Z",
      until: "2026-07-24T00:00:00Z",
      bucketSeconds: 900
    },
    buckets: [],
    readError: null
  }));
  hooks.useRecorderObservabilityIncidents.mockReturnValue(query({
    state: "loaded",
    vrcode: "VR_A",
    timeBasis: "receivedAt",
    incidents: [],
    nextCursor: null,
    readError: null
  }));
  hooks.useVitalDBBeds.mockReturnValue(query(bedHistory()));
  hooks.useVitalDBRelationships.mockReturnValue(query(relationships()));
  hooks.useRuntimeEvents.mockReturnValue(query(events()));
  hooks.useHostLogs.mockReturnValue(query({ text: "line one\nline two" }));
  hooks.useHostBackups.mockReturnValue(query([{ path: "/tmp/backup-a", sizeBytes: 2048 }]));
  hooks.useRedisBackups.mockReturnValue(query([{ path: "/tmp/redis-a", sizeBytes: 1024 }]));
  hooks.useRuntimeDataBackups.mockReturnValue(query([{ path: "/tmp/runtime-data-a", sizeBytes: 4096 }]));
  hooks.useLabScenarios.mockReturnValue(query({
    state: "loaded",
    scenarios: [
      {
        scenarioId: "baseline",
        name: "Baseline monitor",
        category: "generated",
        description: "Stable generated vitals"
      }
    ],
    readError: null
  }));
  hooks.useLabBeds.mockReturnValue(query({
    state: "loaded",
    beds: [],
    readError: null
  }));
  hooks.useLabRecorders.mockReturnValue(query({
    state: "loaded",
    recorders: [],
    readError: null
  }));
  hooks.useReleaseInfo.mockReturnValue(query({
    helperVersion: "helper-1.0.0",
    minimumUpdaterVersion: "updater-1.0.0",
    vitalServerVersion: "vitalserver-1.0.0",
    services: [{ name: "app", image: "ghcr.io/tirosh/app:1", version: "1" }]
  }));
  hooks.useInstallInfo.mockReturnValue(query({
    appBundlePath: "/Applications/VitalServer Helper.app",
    packageIdentifier: "runtime.example",
    runtimeHomePath: "/var/lib/vitalserver",
    backupsPath: "/var/lib/vitalserver/backups",
    redisBackupsPath: "/var/lib/vitalserver/redis-backups",
    runtimeDataBackupsPath: "/var/lib/vitalserver/runtime-data-backups"
  }));
  hooks.useLabVitalFiles.mockReturnValue(query({
    state: "loaded",
    vitalFiles: [
      {
        displayName: "case.vital",
        relativePath: "case.vital",
        guestPath: "/mnt/tirosh-vital-files/case.vital",
        sizeBytes: 1024,
        modifiedAt: "2026-05-31T00:00:00Z"
      }
    ],
    readError: null
  }));
  hooks.useLabSession.mockReturnValue(query(labSessionResponse("accepted")));
  hooks.useLabSessions.mockReturnValue(query({
    state: "loaded",
    sessions: [labSessionResponse("accepted").session],
    readError: null
  }));

  for (const mock of [
    hooks.useApplyRuntimeAdminPassword,
    hooks.useApplyRuntimePlatformSettings,
    hooks.useApplyRuntimeRedisRelaySettings,
    hooks.useApplyUpdateBundle,
    hooks.useCreateRedisBackup,
    hooks.useCreateRuntimeDataBackup,
    hooks.useCreateLabBeds,
    hooks.useCreateLabRecorders,
    hooks.useCreateLabSession,
    hooks.useDeleteLabBeds,
    hooks.useDeleteLabRecorders,
    hooks.useDeleteHostBackup,
    hooks.useDeleteRuntimeDataBackup,
    hooks.useDeleteVitalDBBeds,
    hooks.useDeleteVitalDBRecorders,
    hooks.useDeleteUpdateBackup,
    hooks.useCreatePlatformSupportExport,
    hooks.useHideVitalDBBeds,
    hooks.useHideVitalDBRecorders,
    hooks.useRepairDatastore,
    hooks.useRestartRuntimeProvider,
    hooks.useRollbackRelease,
    hooks.useRestartGuestService,
    hooks.useRollbackBackup,
    hooks.useRestoreRuntimeDataBackup,
    hooks.useReplayLabVitalFile,
    hooks.useResetLabBeds,
    hooks.useResetLabRecorders,
    hooks.useStartLabSession,
    hooks.useStartLabRecorder,
    hooks.useStartGuestService,
    hooks.useStopGuestService,
    hooks.useStopLabSession,
    hooks.useFinishLabSession,
    hooks.useStopLabRecorder,
    hooks.useSummarizeUpdateBundle,
    hooks.useUnhideVitalDBBeds,
    hooks.useUnhideVitalDBRecorders,
    hooks.useUninstallRuntime,
    hooks.useUploadLabVitalFiles,
    hooks.useVerifyUpdateBundle
  ]) {
    mock.mockReturnValue(pendingMutation());
  }

  hooks.useApplyRuntimeProductSettings.mockReturnValue(
    pendingMutation()
  );

}

function guestStackStatus() {
  return {
    state: "loaded",
    observedAt: "2026-05-31T01:00:00Z",
    cpuUsagePercent: 12,
    memory: { usedBytes: 2048, totalBytes: 4096 },
    systemDisk: { availableBytes: 8192, totalBytes: 16384 },
    services: [
      {
        service: "app",
        state: "running",
        health: "healthy",
        source: {
          kind: "compose",
          observedAt: "2026-05-31T01:00:00Z"
        }
      },
      {
        service: "recorder-ingress",
        state: "running",
        health: "healthy",
        source: {
          kind: "compose",
          observedAt: "2026-05-31T01:00:00Z"
        }
      }
    ],
    probeErrors: []
  };
}

function capabilities() {
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
    canControlLabRecorders: true,
    canApplyRuntimeProductSettings: true,
    canApplyRuntimeAdminPassword: true,
    canApplyRuntimeRedisRelaySettings: true,
    canApplySettings: true,
    canApplyRuntimeSettings: true,
    canEditLocalFiles: true
  };
}

function overview() {
  const vitalDBObservation = {
    schemaVersion: 1,
    source: "vitaldb-observer",
    observedAt: "2026-05-31T01:00:00Z",
    ready: true,
    recorderOnlineThresholdSeconds: 120,
    recorders: [],
    beds: [],
    devices: [],
    filters: [],
    proxyConnections: [],
    readIssues: [],
    anomalies: [
      {
        id: "duplicate-ip-10",
        kind: "duplicate-ip",
        severity: "warning",
        observedAt: "2026-05-31T01:00:00Z",
        subject: "10.0.0.10",
        message: "duplicate recorder IP"
      }
    ]
  };

  return {
    settings: settings(),
    vitalDBObservation,
    vitalDBObservationSnapshot: {
      state: "loaded",
      observation: vitalDBObservation,
      readError: null
    },
    vitalRecorder: {
      source: "vitalDBObservation",
      observedAt: "2026-05-31T01:00:00Z",
      activeConnections: 1,
      knownRecorders: 1,
      onlineRecorders: 1,
      staleRecorders: 0,
      knownBeds: 1,
      recorderAnomalies: 1
    },
    conditions: [
      {
        type: "VitalDBObservationReady",
        status: "True",
        reason: "Loaded",
        message: null,
        observedAt: "2026-05-31T01:00:00Z"
      }
    ]
  };
}

function platformState() {
  return {
    runtimeInstallationState: "executable",
    platformHealth: "healthy",
    installedVersion: "1.2.3",
    runtimeEndpoint: "192.168.64.8",
    publicProxyPort: 18080,
    platformAPIStartedAt: "2026-05-31T00:00:00Z",
    runtimeControllerHTTP: "HTTP 200",
    publicProxyHTTP: "HTTP 200",
    platformAPIHTTP: "HTTP 200",
    services: [
      { role: "runtime-provider" as const, state: "running" as const, readError: null },
      { role: "public-proxy" as const, state: "running" as const, readError: null },
      { role: "log-sync" as const, state: "running" as const, readError: null },
      { role: "sleep-prevention" as const, state: "running" as const, readError: null },
      { role: "watchdog" as const, state: "running" as const, readError: null }
    ],
    dataDirectoryStats: { fileCount: 2, sizeBytes: 4096 },
    dataStorage: { usedBytes: 1024, totalBytes: 2048 },
    healthIssues: []
  };
}

function operationState() {
  return {
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
        startedAt: "2026-05-31T00:00:00Z",
        heartbeatAt: "2026-05-31T00:00:05Z",
        expiresAt: "2026-05-31T00:00:10Z",
        message: "applying bundle"
      },
      readError: null,
      staleReason: "expired"
    }
  };
}

function settings(overrides = {}) {
  return {
    cpuCount: 2,
    memoryGiB: 4,
    diskGiB: 20,
    minimumDiskGiB: 20,
    networkMode: "shared" as const,
    bridgedInterface: "",
    proxyPort: 18080,
    runtimeControlPort: 18321,
    publicHost: "host.local",
    publicPort: 18080,
    recorderIngressSendDataMode: "spool_and_replay" as const,
    recorderIngressSendDataReplayBatchSize: 10,
    recorderIngressSendDataReplayMaxMiBPerSecond: 20,
    recorderIngress: recorderIngressSettings(),
    containerMemoryLimitsEnabled: true,
    vitalServerContainerMemoryLimitMiB: 2048,
    recorderIngressContainerMemoryLimitMiB: 256,
    redisContainerMemoryLimitMiB: 512,
    vitalServerURL: "http://vital.example.test/",
    remoteConsoleURL: "http://console.example.test/",
    adminPassword: "",
    changeAdminPassword: false,
    vitalFilesDirectory: "/Users/shared/vital",
    automaticBackupEnabled: true,
    backupScheduleTimes: ["03:15"],
    backupRetentionCount: 7,
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
    ],
    ...overrides
  };
}

function productSettings() {
  const value = settings();
  return {
    automaticBackupEnabled: value.automaticBackupEnabled,
    backupRetentionCount: value.backupRetentionCount,
    backupScheduleTimes: value.backupScheduleTimes,
    containerMemoryLimitsEnabled: value.containerMemoryLimitsEnabled,
    publicHost: value.publicHost,
    publicPort: value.publicPort,
    recorderIngress: value.recorderIngress,
    recorderIngressContainerMemoryLimitMiB:
      value.recorderIngressContainerMemoryLimitMiB,
    recorderIngressSendDataMode: value.recorderIngressSendDataMode,
    recorderIngressSendDataReplayBatchSize:
      value.recorderIngressSendDataReplayBatchSize,
    recorderIngressSendDataReplayMaxMiBPerSecond:
      value.recorderIngressSendDataReplayMaxMiBPerSecond,
    redisContainerMemoryLimitMiB: value.redisContainerMemoryLimitMiB,
    remoteConsoleURL: value.remoteConsoleURL,
    vitalServerContainerMemoryLimitMiB:
      value.vitalServerContainerMemoryLimitMiB,
    vitalServerURL: value.vitalServerURL
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

function recorderObservabilityDetail() {
  const missing = {
    state: "missing" as const,
    value: null,
    detail: "health observation is absent",
    observedAt: null
  };
  return {
    state: "loaded" as const,
    vrcode: "VR_A",
    support: {
      state: "supported" as const,
      source: "accepted_report",
      expectedSince: null,
      recorderVersion: "1.0",
      producerVersion: "1.0",
      protocolVersion: "1"
    },
    report: {
      state: "current" as const,
      receivedAt: "2026-05-31T00:59:30Z",
      deviceObservedAt: "2026-05-31T00:59:29Z",
      collectionState: "complete",
      readIssueCount: 0
    },
    profile: {
      state: "associated" as const,
      receivedAt: "2026-05-31T00:58:00Z",
      deviceObservedAt: "2026-05-31T00:57:59Z",
      deviceId: "observer-1",
      bootId: "boot-1",
      software: {},
      collection: {
        powerIntervalSeconds: 1,
        telemetryIntervalSeconds: 10,
        observationIntervalSeconds: 60
      },
      capabilities: {}
    },
    boot: {
      state: "started" as const,
      orderingState: "ordered" as const,
      bootId: "boot-1",
      startedAt: "2026-05-30T00:00:00Z",
      cleanShutdownAt: null
    },
    evidenceHealth: {
      state: "healthy" as const,
      checkedAt: "2026-05-31T00:59:29Z",
      checkCount: 3,
      detail: null
    },
    incidentState: {
      state: "reported" as const,
      policyVersion: "recorder-incident/v1",
      bootLoopState: "none" as const,
      repeatedUndervoltageState: "none" as const,
      evidenceState: "healthy" as const,
      consecutiveUnexpectedBoots: 0,
      undervoltageBootsConsidered: 0
    },
    operationalHealth: {
      state: "warning" as const,
      evaluatedAt: "2026-05-31T00:59:29Z",
      issueCount: 1,
      issues: [
        {
          code: "systemd-system-degraded",
          category: "service" as const,
          severity: "warning" as const,
          title: "System service state is not fully running",
          detail: "degraded; failed units: rpi-eeprom-update.service",
          field: "payload.services.systemRunning"
        }
      ]
    },
    readings: {
      temperatureCelsius: {
        state: "ok" as const,
        value: 52.5,
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      memoryAvailableBytes: {
        state: "ok" as const,
        value: 4_294_967_296,
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      memoryTotalBytes: {
        state: "ok" as const,
        value: 8_589_934_592,
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      rootUsedPercent: {
        state: "ok" as const,
        value: 41.2,
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      dataUsedPercent: { ...missing },
      recorderActiveState: {
        state: "ok" as const,
        value: "active",
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      publisherActiveState: {
        state: "ok" as const,
        value: "active",
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      publisherBufferBytes: {
        state: "ok" as const,
        value: 2048,
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      publisherBufferLimitBytes: {
        state: "ok" as const,
        value: 8_388_608,
        detail: null,
        observedAt: "2026-05-31T00:59:29Z"
      },
      networkInterfaces: []
    },
    readIssues: [],
    readError: null
  };
}

function recorders() {
  return {
    state: "loaded",
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
        duplicateObservationCount: 0,
        currentAnomalyCount: 1,
        latestAnomalyKind: "stale-recorder",
        latestAnomalySeverity: "warning",
        latestAnomalyMessage: "Recorder activity is stale.",
        latestAnomalyObservedAt: "2026-05-31T01:00:00Z",
        presentInLatestObservation: true,
        visibility: "visible",
        redisIPSync: {
          status: "verified",
          redisKey: "ip_VR_A",
          selectedIp: "192.168.64.20",
          ipSource: "x-forwarded-for",
          redisValue: "192.168.64.20",
          lastWriteAt: "2026-05-31T01:00:01Z",
          lastVerifiedAt: "2026-05-31T01:00:02Z",
          lastFailure: null
        },
        observability: {
          state: "loaded",
          vrcode: "VR_A",
          supportState: "supported",
          supportSource: "accepted_report",
          reportState: "current",
          profileState: "associated",
          collectionState: "ok",
          latestObservationReceivedAt: "2026-05-31T00:59:30Z",
          lastBootStartedAt: "2026-05-30T00:00:00Z",
          readIssueCount: 0,
          operationalHealthState: "warning",
          operationalIssueCount: 1,
          readError: null
        },
        activityTimeline: [
          {
            observedAt: "2026-05-31T00:59:00Z",
            windowSeconds: 60,
            messageCount: 3,
            byteCount: 2048,
            roomCount: 1,
            messagesPerSecond: 0.05,
            bytesPerSecond: 128,
            buckets: []
          }
        ]
      }
    ],
    beds: beds(),
    summary: {
      knownRecorders: 1,
      currentRecorders: 1,
      onlineRecorders: 1,
      staleRecorders: 0,
      recorderAnomalies: 1,
      knownBeds: 1,
      onlineBeds: 1,
      staleBeds: 0,
      bedAssignments: 1,
      bedAnomalies: 1
    },
    activityHistory: {
      source: "notProvided",
      bucketCount: 0,
      earliestBucketStartedAt: null,
      latestBucketStartedAt: null,
      readError: null
    },
    recorderIngressStatusRead: {
      readState: "loaded",
      httpStatus: "200",
      readError: null,
      document: {
        activeWebSockets: 3,
        activeRecorderConnections: 2,
        recorders: [],
        httpRequests: 4,
        socketIoEventsSeen: 5,
        socketIoParseFailures: 0,
        auditWriteFailures: 0,
        auditFileWriteFailures: 0,
        auditStdoutWriteFailures: 0,
        redisIpWriteFailures: 0,
        redisIpVerifyFailures: 0,
        redisIpVerifyMismatches: 0,
        throughput: {
          windowSeconds: 10,
          observedBytesPerSecond: 2097152,
          spooledBytesPerSecond: 2097152,
          replayedBytesPerSecond: 1048576,
          queueGrowthBytesPerSecond: 1048576
        },
        spool: {
          mode: "spool_and_replay",
          status: "draining",
          storage: "redis",
          acceptedEvents: 10,
          spooledEvents: 9,
          rejectedEvents: 0,
          writeFailures: 0,
          pendingItems: 5,
          pendingBytes: 9216,
          oldestPendingAgeSeconds: 34,
          lastAcceptedAt: "2026-05-31T01:00:00Z",
          lastSpooledAt: "2026-05-31T01:00:00Z",
          lastFailure: null
        },
        replay: {
          status: "replaying",
          pendingItems: 5,
          inFlightItems: 1,
          replayedEvents: 4,
          retryableFailures: 0,
          deadLetteredEvents: 0,
          replayLagSeconds: 12,
          maxBytesPerSecond: 5242880,
          configuredMaxBytesPerSecond: 10485760,
          adaptive: {
            enabled: true,
            minBytesPerSecond: 1048576,
            maxBytesPerSecond: 10485760,
            currentMaxBytesPerSecond: 5242880,
            minItemsPerTick: 50,
            maxItemsPerTick: 1000,
            currentItemsPerTick: 500,
            minConcurrency: 1,
            maxConcurrency: 8,
            currentConcurrency: 8,
            lastDecision: "increase",
            lastReason: "queue_growth",
            lastChangedAt: "2026-05-31T01:00:00Z",
            memoryGuardStatus: "unavailable"
          },
          lastReplayAt: "2026-05-31T01:00:00Z",
          lastFailure: null
        }
      }
    }
  };
}

function recorderActivityWindow(overrides: Record<string, unknown> = {}) {
  return {
    state: "loaded" as const,
    query: {
      vrcode: "VR_A",
      bucketSeconds: 60 as const,
      period: "lastHour" as const
    },
    page: {
      index: 0,
      count: 1,
      windowSeconds: 3600,
      windowStartedAt: "2026-05-31T00:00:00Z",
      windowEndedAt: "2026-05-31T01:00:00Z",
      firstBucketStartedAt: "2026-05-31T00:59:00Z",
      latestBucketStartedAt: "2026-05-31T00:59:00Z"
    },
    buckets: [
      {
        bucketStartedAt: "2026-05-31T00:59:00Z",
        bucketSeconds: 60,
        messageCount: 3,
        byteCount: 2048,
        roomCount: 1
      }
    ],
    latestSampleAt: "2026-05-31T00:59:00Z",
    readError: null,
    ...overrides
  };
}

function recordersWithLongActivity() {
  const base = recorders();
  return {
    ...base,
    recorders: [
      {
        ...base.recorders[0],
        activityTimeline: [
          {
            observedAt: "2026-05-31T13:00:00Z",
            windowSeconds: 300,
            messageCount: 1,
            byteCount: 100,
            roomCount: 1,
            messagesPerSecond: 1 / 300,
            bytesPerSecond: 100 / 300,
            buckets: Array.from({ length: 156 }, (_, index) => ({
              bucketStartedAt: new Date(
                Date.UTC(2026, 4, 31, 0, 0, 0) + index * 5 * 60 * 1000
              ).toISOString(),
              bucketSeconds: 300,
              messageCount: index + 1,
              byteCount: (index + 1) * 100,
              roomCount: 1
            }))
          }
        ]
      }
    ],
    activityHistory: {
      source: "readModelProjection",
      bucketCount: 156,
      earliestBucketStartedAt: "2026-05-31T00:00:00.000Z",
      latestBucketStartedAt: "2026-05-31T12:55:00.000Z",
      readError: null
    }
  };
}

function beds() {
  return [
    {
      bedID: "bed-1",
      name: "OR-1",
      vrcode: "VR_A",
      linkedRecorderStatus: "online",
      linkedRecorderIP: "192.168.64.20",
      linkedRecorderLastSeenAt: "2026-05-31T01:00:00Z",
      status: "online",
      patientConnected: true,
      firstSeenAt: "2026-05-31T00:00:00Z",
      lastSeenAt: "2026-05-31T01:00:00Z",
      observationCount: 2,
      duplicateObservationCount: 0,
      currentAnomalyCount: 1,
      latestAnomalyKind: "offline",
      latestAnomalySeverity: "warning",
      latestAnomalyMessage: "Bed link is offline.",
      latestAnomalyObservedAt: "2026-05-31T01:00:00Z",
      visibility: "visible"
    }
  ];
}

function bedHistory() {
  return {
    state: "loaded",
    updatedAt: "2026-05-31T01:00:00Z",
    beds: beds(),
    summary: {
      knownBeds: 1,
      onlineBeds: 1,
      staleBeds: 0,
      bedAssignments: 1,
      bedAnomalies: 1
    },
    readError: null
  };
}

function relationships() {
  return {
    state: "loaded",
    assignments: [
      {
        assignmentID: "assignment-1",
        bedID: "bed-1",
        bedName: "OR-1",
        vrcode: "VR_A",
        startedAt: "2026-05-31T00:00:00Z",
        endedAt: null,
        lastSeenAt: "2026-05-31T01:00:00Z",
        lastObservedAt: "2026-05-31T01:00:00Z",
        status: "online",
        patientConnected: true,
        observationCount: 2
      }
    ],
    events: [
      {
        eventID: "relationship-event-1",
        observedAt: "2026-05-31T01:00:00Z",
        eventType: "unlinkedBed",
        severity: "warning",
        bedID: "bed-1",
        bedName: "OR-1",
        vrcode: "VR_A",
        previousVrcode: null,
        previousBedID: null,
        message: "Bed has no linked VRecorder."
      }
    ],
    readError: null
  };
}

function events() {
  return {
    events: [
      {
        schemaVersion: 1,
        id: "runtime-operation-event-1",
        timestamp: "2026-05-31T01:00:00Z",
        eventType: "operation-completed",
        operationId: "operation-1",
        operationService: "runtime-settings",
        operationCommand: "apply-settings",
        operationState: "completed",
        source: "runtime-controller",
        message: "runtime updated",
        failure: null
      },
      {
        schemaVersion: 1,
        id: "runtime-operation-event-2",
        timestamp: "2026-05-31T01:05:00Z",
        eventType: "operation-failed",
        operationId: "operation-2",
        operationService: "runtime-provider",
        operationCommand: "reconcile",
        operationState: "failed",
        source: "runtime-controller",
        message: "runtime reconcile failed",
        failure: { kind: "reconcileFailed", message: "provider unavailable" }
      }
    ],
    nextCursor: null,
    matchingCount: 2
  };
}

function labSessionResponse(
  state: "accepted" | "running" | "stopping" | "stopped" | "finished"
) {
  return {
    state: "loaded" as const,
    operationId: "op-1",
    labOperationId: "lab-op-1",
    readError: null,
    session: {
      sessionId: "lab-1",
      state,
      scenarioId: "baseline",
      name: "Case review",
      recorderCount: 2,
      targetURL: "http://edge/",
      createdAt: "2026-05-31T00:00:00Z",
      updatedAt: "2026-05-31T00:00:00Z"
    }
  };
}

function labRecorder(
  recorderId: string,
  state: "running" | "stopped"
) {
  return {
    recorderId,
    sessionId: "lab-1",
    bedId: `${recorderId}-bed`,
    vrcode: recorderId,
    state,
    createdAt: "2026-05-31T00:00:00Z",
    updatedAt: "2026-05-31T00:00:00Z",
    messagesSent: 0,
    lastSendState: "notAttempted" as const,
    lastSendAt: null,
    lastSendError: null
  };
}
