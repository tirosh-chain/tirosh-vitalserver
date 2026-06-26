import { fireEvent, render, screen, within } from "@testing-library/react";
import type { PropsWithChildren, ReactElement } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";
import { AppSettingsProvider } from "@/config/AppSettingsContext";

const hooks = vi.hoisted(() => ({
  useApplyRuntimeSettings: vi.fn(),
  useApplyUpdateBundle: vi.fn(),
  useCreateRedisBackup: vi.fn(),
  useCreateRuntimeDataBackup: vi.fn(),
  useCreateTestKitBeds: vi.fn(),
  useDeleteHostBackup: vi.fn(),
  useDeleteRuntimeDataBackup: vi.fn(),
  useDeleteUpdateBackup: vi.fn(),
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
  useRestoreRuntimeDataBackup: vi.fn(),
  useRuntimeCapabilities: vi.fn(),
  useRuntimeDataBackups: vi.fn(),
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
  useVitalDBRelationships: vi.fn(),
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

afterEach(() => {
  vi.useRealTimers();
});

describe("runtime console pages", () => {
  it("renders status metrics from the overview document", () => {
    renderPage(<StatusPage />);

    expect(screen.getByText("Overall health")).toBeInTheDocument();
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
    expect(screen.getByText("100.0 MiB / 512.0 MiB")).toBeInTheDocument();
    expect(screen.getByText(/2.0 KiB \/ 4.0 KiB/)).toBeInTheDocument();
  });

  it("renders same-host service URLs as browser-reachable links", () => {
    const baseOverview = overview();
    hooks.useRuntimeOverview.mockReturnValue(
      query({
        ...baseOverview,
        settings: {
          ...baseOverview.settings,
          vitalServerURL: "",
          remoteConsoleURL: "",
          publicHost: "",
          publicPort: 18080,
          runtimeControlPort: 18321
        }
      })
    );

    renderPage(<StatusPage />);

    const hostname = globalThis.location.hostname;
    expect(
      screen.getByRole("link", { name: `http://${hostname}:18080/` })
    ).toHaveAttribute("href", `http://${hostname}:18080/`);
    expect(
      screen.getByRole("link", { name: `http://${hostname}:18321/` })
    ).toHaveAttribute("href", `http://${hostname}:18321/`);
  });

  it("does not infer missing status endpoint or resource fields", () => {
    const baseOverview = overview();
    hooks.useRuntimeOverview.mockReturnValue(
      query({
        ...baseOverview,
        settings: {
          ...baseOverview.settings,
          vitalServerURL: "",
          remoteConsoleURL: "",
          publicHost: "",
          publicPort: undefined,
          runtimeControlPort: undefined
        },
        status: {
          ...baseOverview.status,
          proxyPort: undefined,
          cpuUsagePercent: undefined,
          dataDirectoryStats: {
            sizeBytes: 4096
          },
          memory: {
            usedBytes: 2048
          }
        }
      })
    );

    renderPage(<StatusPage />);

    expect(screen.getAllByText("Not reported").length).toBeGreaterThanOrEqual(3);
    expect(screen.getByText("File count not reported · 4.0 KiB")).toBeInTheDocument();
    expect(screen.getByText("Incomplete resource usage")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /18080/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /18321/ })).not.toBeInTheDocument();
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
    fireEvent.change(screen.getByLabelText("Max replay throughput"), {
      target: { value: "25" }
    });
    fireEvent.change(screen.getByLabelText(/VitalServer limit/), {
      target: { value: "40" }
    });
    fireEvent.change(screen.getByLabelText(/Recorder ingress limit/), {
      target: { value: "8" }
    });
    fireEvent.change(screen.getByLabelText(/Redis limit/), {
      target: { value: "12" }
    });
    fireEvent.click(screen.getByLabelText("Start on boot"));
    fireEvent.click(screen.getByLabelText("Auto recovery"));
    fireEvent.click(screen.getByLabelText("Prevent system sleep"));
    fireEvent.click(
      screen.getByLabelText("Activate required runtime changes after save")
    );
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    expect(apply.mutate).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({
          cpuCount: 3,
          publicHost: "edge.local",
          publicPort: 443,
          recorderIngressSendDataReplayMaxMiBPerSecond: 25,
          containerMemoryLimitsEnabled: true,
          vitalServerContainerMemoryLimitMiB: 1638,
          recorderIngressContainerMemoryLimitMiB: 328,
          redisContainerMemoryLimitMiB: 492,
          startOnBoot: false,
          autoRecoveryEnabled: false,
          preventSystemSleep: false,
          restartAfterSave: false
        })
      }),
      expect.any(Object)
    );
  });

  it("normalizes enabled container memory limits to the combined cap", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimeSettings.mockReturnValue(apply);
    hooks.useRuntimeSettings.mockReturnValue(query(settings({
      memoryGiB: 4,
      containerMemoryLimitsEnabled: true,
      vitalServerContainerMemoryLimitMiB: 4096,
      recorderIngressContainerMemoryLimitMiB: 512,
      redisContainerMemoryLimitMiB: 1024
    })));

    renderPage(<SettingsPage />);

    expect(screen.getByText("Container limit total: 70% / 70% of VM memory")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    expect(apply.mutate).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({
          containerMemoryLimitsEnabled: true,
          vitalServerContainerMemoryLimitMiB: 1311,
          recorderIngressContainerMemoryLimitMiB: 512,
          redisContainerMemoryLimitMiB: 1024
        })
      }),
      expect.any(Object)
    );
  });

  it("enables activation automatically for container memory limit changes", () => {
    const apply = pendingMutation();
    hooks.useApplyRuntimeSettings.mockReturnValue(apply);
    hooks.useRuntimeSettings.mockReturnValue(query(settings({
      restartAfterSave: false,
      containerMemoryLimitsEnabled: true,
      vitalServerContainerMemoryLimitMiB: 2048,
      recorderIngressContainerMemoryLimitMiB: 256,
      redisContainerMemoryLimitMiB: 512
    })));

    renderPage(<SettingsPage />);

    expect(
      screen.getByLabelText("Activate required runtime changes after save")
    ).not.toBeChecked();

    fireEvent.change(screen.getByLabelText(/VitalServer limit/), {
      target: { value: "40" }
    });

    expect(
      screen.getByLabelText("Activate required runtime changes after save")
    ).toBeChecked();

    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    expect(apply.mutate).toHaveBeenCalledWith(
      expect.objectContaining({
        settings: expect.objectContaining({
          restartAfterSave: true,
          vitalServerContainerMemoryLimitMiB: 1638
        })
      }),
      expect.any(Object)
    );
  });

  it("does not render an empty settings draft before settings load", () => {
    hooks.useRuntimeSettings.mockReturnValue(query(undefined));

    renderPage(<SettingsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Settings response is incomplete"
    );
    expect(screen.queryByLabelText("CPU cores")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Start on boot")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Apply" })).toBeDisabled();
  });

  it("uses provider-owned settings values without form fallbacks", () => {
    renderPage(<SettingsPage />);

    expect(
      screen.getByText(/Applied: Automatic backups on · 03:15 · .* · keep 7 archives/)
    ).toBeInTheDocument();
    expect(screen.getByText("Applied: keep 14 days · max 1 GiB")).toBeInTheDocument();
    expect(screen.getByLabelText("VM disk GiB")).toHaveAttribute("min", "20");
    expect(
      screen.getByText("VM disk can only be increased. Minimum for this install is 20 GiB.")
    ).toBeInTheDocument();
    expect(screen.getByText("Change activation")).toBeInTheDocument();
    expect(
      screen.getByText("No runtime activation required for these changes.")
    ).toBeInTheDocument();

    fireEvent.click(screen.getByLabelText("Custom advertised URL"));
    const hostname = globalThis.location.hostname;
    expect(
      screen.getByText(`Default advertised URL: http://${hostname}:18080/`)
    ).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("VitalServer listen port"), {
      target: { value: "" }
    });
    expect(
      screen.getByText("Default advertised URL: Proxy port is not available.")
    ).toBeInTheDocument();
  });

  it("shows VM restart activation when vital files directory changes", () => {
    renderPage(<SettingsPage />);

    fireEvent.change(screen.getByLabelText("Vital files directory"), {
      target: { value: "/Users/shared/new-vital" }
    });
    fireEvent.click(
      screen.getByLabelText("Activate required runtime changes after save")
    );

    expect(
      screen.getByText(
        "Saved changes will not become active until the VM runtime restarts. Required by: Vital files directory."
      )
    ).toBeInTheDocument();
    expect(
      screen.getByText("Requires VM restart. Required by: Vital files directory.")
    ).toBeInTheDocument();
  });

  it("shows unapplied settings state for backup and log edits", () => {
    renderPage(<SettingsPage />);

    fireEvent.change(screen.getByLabelText("Backup times"), {
      target: { value: "03:15, 15:15" }
    });
    fireEvent.change(screen.getByLabelText("Log archive retention"), {
      target: { value: "10" }
    });

    expect(
      screen.getByText(/Not applied yet\. Applied: Automatic backups on · 03:15 · .* · keep 7 archives/)
    ).toBeInTheDocument();
    expect(
      screen.getByText("Not applied yet. Applied: keep 14 days · max 1 GiB")
    ).toBeInTheDocument();
  });

  it("does not erase custom advertised URL draft values when toggled off", () => {
    renderPage(<SettingsPage />);

    expect(screen.getByLabelText("Custom advertised host")).toHaveValue(
      "host.local"
    );

    fireEvent.click(screen.getByLabelText("Custom advertised URL"));
    expect(screen.queryByLabelText("Custom advertised host")).not.toBeInTheDocument();

    fireEvent.click(screen.getByLabelText("Custom advertised URL"));
    expect(screen.getByLabelText("Custom advertised host")).toHaveValue(
      "host.local"
    );
  });

  it("shows explicit start-on-boot disabled reasons", () => {
    hooks.useRuntimeCapabilities.mockReturnValue(
      query({ ...capabilities(), canControlRuntimeServices: false })
    );

    renderPage(<SettingsPage />);

    expect(screen.getByLabelText("Start on boot")).toBeDisabled();
    expect(
      screen.getByText("Runtime service control capability is unavailable.")
    ).toBeInTheDocument();
  });

  it("does not guess Remote Console readiness with a timed redirect after settings apply", () => {
    const apply = mutation(commandResult);
    hooks.useApplyRuntimeSettings.mockReturnValue(apply);

    renderPage(<SettingsPage />);

    const setTimeoutSpy = vi.spyOn(globalThis, "setTimeout");
    fireEvent.change(screen.getByLabelText("Remote Console port"), {
      target: { value: "18322" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Apply" }));

    expect(setTimeoutSpy).not.toHaveBeenCalled();
    expect(
      screen.getByText(/Remote Console port changed to 18322/)
    ).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Remote Console" })).not.toBeInTheDocument();
  });

  it("renders recorder lists, filters history, and selects recorder details", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-31T01:00:30Z"));

    renderPage(<RecordersPage />);

    expect(screen.getByText("Known recorders")).toBeInTheDocument();
    expect(screen.getAllByText("VR_A").length).toBeGreaterThan(0);
    expect(screen.getAllByText("IP verified").length).toBeGreaterThan(0);
    expect(screen.getByText("Network access")).toBeInTheDocument();
    expect(screen.getByText("Active IP")).toBeInTheDocument();
    expect(screen.queryByText("Redis key")).not.toBeInTheDocument();
    expect(screen.queryByText("x-forwarded-for")).not.toBeInTheDocument();
    expect(screen.getByRole("img", { name: /Packet activity/ })).toBeInTheDocument();
    expect(screen.getByText("0 B/s")).toBeInTheDocument();
    expect(screen.queryByText("Room entries")).not.toBeInTheDocument();
    expect(screen.getAllByText("Recorder anomalies").length).toBeGreaterThan(0);
    expect(screen.getByText("Data updated")).toBeInTheDocument();
    expect(screen.getAllByText(/Stale Recorder · warning/).length).toBeGreaterThan(0);
    expect(screen.getByText("Relationship history")).toBeInTheDocument();
    expect(screen.getAllByText("Assignments").length).toBeGreaterThan(0);
    expect(screen.getByText("Events")).toBeInTheDocument();
    expect(screen.getByText("Bed has no linked VRecorder.")).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("Search VRecorders"), {
      target: { value: "missing" }
    });
    expect(screen.getByText("No VRecorders found.")).toBeInTheDocument();
  });

  it("browses all recorder activity in twelve hour windows with one minute buckets", () => {
    hooks.useVitalDBRecorders.mockReturnValue(query(recordersWithLongActivity()));

    renderPage(<RecordersPage />);

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
    const slideSlider = screen.getByLabelText("Window slide") as HTMLInputElement;
    expect(slideSlider.value).toBe("4");
    expect(slideSlider.max).toBe("12");
    expect(slideSlider).toHaveAttribute(
      "title",
      "Window slides by 4h each move"
    );
    expect(screen.getByText(/slide 4h/)).toBeInTheDocument();

    fireEvent.change(windowSlider, { target: { value: "0" } });
    expect(windowSlider.value).toBe("0");

    fireEvent.change(slideSlider, { target: { value: "1" } });
    expect(slideSlider.value).toBe("1");
    expect(screen.getByText(/slide 1h/)).toBeInTheDocument();
  });

  it("shows missing recorder activity history as not reported", () => {
    hooks.useVitalDBRecorders.mockReturnValue(
      query({
        ...recorders(),
        recorders: [
          {
            ...recorders().recorders[0],
            status: "notObserved",
            activityTimeline: undefined
          }
        ]
      })
    );

    renderPage(<RecordersPage />);

    expect(screen.getAllByText("Not observed").length).toBeGreaterThan(0);
    expect(
      screen.getByText("Recorder activity history is not reported.")
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

    renderPage(<RecordersPage />);

    expect(
      screen.getByText("Recorder activity history is incomplete")
    ).toBeInTheDocument();
    expect(screen.getByText(/activity projection denied/)).toBeInTheDocument();
    expect(screen.queryByRole("img", { name: /Packet activity/ })).not.toBeInTheDocument();
  });

  it("renders beds, filters rows, and shows selected bed details", () => {
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
    expect(screen.getByText("No beds found.")).toBeInTheDocument();
  });

  it("does not render missing bed query data as an empty bed list", () => {
    hooks.useVitalDBRecorders.mockReturnValue(query(undefined));

    renderPage(<BedsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Bed history response is incomplete"
    );
    expect(screen.queryByText("No beds found.")).not.toBeInTheDocument();
  });

  it("renders observability events and reacts to filters", () => {
    renderPage(<ObservabilityPage />);

    expect(screen.getByText("Observation pipeline")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Recorder anomalies" })).toBeInTheDocument();
    expect(screen.getByText("duplicate-ip")).toBeInTheDocument();
    expect(screen.getByText("10.0.0.10")).toBeInTheDocument();
    expect(screen.getByText("runtime updated")).toBeInTheDocument();
    expect(screen.getByText("runtime recovered")).toBeInTheDocument();
    expect(
      screen.getByText("runtime recovered").compareDocumentPosition(
        screen.getByText("runtime updated")
      ) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();

    fireEvent.change(screen.getByLabelText("Period"), { target: { value: "7d" } });
    fireEvent.change(screen.getByLabelText("Filter"), {
      target: { value: "recovery-deferred" }
    });
    fireEvent.change(screen.getByLabelText("Limit"), { target: { value: "100" } });

    expect(hooks.useRuntimeEvents).toHaveBeenCalled();
  });

  it("keeps observability read failures distinct from empty data", () => {
    const baseOverview = overview();
    hooks.useRuntimeOverview.mockReturnValue(
      query({
        ...baseOverview,
        status: {
          ...baseOverview.status,
          guestLogSyncServiceLoaded: undefined
        },
        vitalDBObservationSnapshot: {
          state: "failed",
          observation: null,
          readError: "sqlite denied"
        }
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
    hooks.useRuntimeOverview.mockReturnValue(
      query({
        ...baseOverview,
        vitalDBObservation,
        vitalDBObservationSnapshot: {
          state: "loaded",
          observation: vitalDBObservation,
          readError: null
        }
      })
    );

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
    hooks.useRuntimeOverview.mockReturnValue(
      query({
        ...baseOverview,
        vitalDBObservation,
        vitalDBObservationSnapshot: {
          state: "loaded",
          observation: vitalDBObservation,
          readError: null
        }
      })
    );

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
    hooks.useRuntimeOverview.mockReturnValue(
      query({
        ...baseOverview,
        vitalDBObservation,
        vitalDBObservationSnapshot: {
          state: "loaded",
          observation: vitalDBObservation,
          readError: "projection=read failed"
        }
      })
    );

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
            id: "event-missing-message",
            timestamp: "2026-05-31T01:00:00Z",
            eventType: "status-changed",
            status: "healthy",
            failureReasons: []
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
    hooks.useRuntimeCapabilities.mockReturnValue(
      failedQuery(new Error("capabilities denied"))
    );

    renderPage(<LogsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Failed to read export capability"
    );
    expect(screen.getByRole("alert")).toHaveTextContent("capabilities denied");
    expect(screen.getByRole("button", { name: "Export Logs" })).toBeDisabled();
  });

  it("shows unsupported log export as explicit unsupported capability", () => {
    hooks.useRuntimeCapabilities.mockReturnValue(
      query({ ...capabilities(), canExportLogs: false })
    );

    renderPage(<LogsPage />);

    expect(
      screen.getByText("Log export is not supported by this Runtime Control API.")
    ).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Export Logs" })).toBeDisabled();
  });

  it("does not render missing log export capability as unsupported export", () => {
    hooks.useRuntimeCapabilities.mockReturnValue(query(undefined));

    renderPage(<LogsPage />);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Export capability response is incomplete"
    );
    expect(
      screen.queryByText("Log export is not supported by this Runtime Control API.")
    ).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Export Logs" })).toBeDisabled();
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
    const applySettings = pendingMutation();
    const rollback = pendingMutation();
    const createRedisBackup = pendingMutation();
    const createRuntimeDataBackup = pendingMutation();
    const restoreRuntimeDataBackup = pendingMutation();
    const start = pendingMutation();
    const stop = pendingMutation();
    const repairRuntime = pendingMutation();
    const repairDatastore = pendingMutation();
    const repairVMDisk = pendingMutation();
    const repairProxy = pendingMutation();
    hooks.useApplyRuntimeSettings.mockReturnValue(applySettings);
    hooks.useRollbackBackup.mockReturnValue(rollback);
    hooks.useCreateRedisBackup.mockReturnValue(createRedisBackup);
    hooks.useCreateRuntimeDataBackup.mockReturnValue(createRuntimeDataBackup);
    hooks.useRestoreRuntimeDataBackup.mockReturnValue(restoreRuntimeDataBackup);
    hooks.useStartRuntimeServices.mockReturnValue(start);
    hooks.useStopRuntimeServices.mockReturnValue(stop);
    hooks.useRepairRuntime.mockReturnValue(repairRuntime);
    hooks.useRepairDatastore.mockReturnValue(repairDatastore);
    hooks.useRepairVMDisk.mockReturnValue(repairVMDisk);
    hooks.useRepairProxy.mockReturnValue(repairProxy);

    renderPage(<AdvancedPage />);

    expect(screen.getByText("VM health")).toBeInTheDocument();
    expect(screen.getByText("Advanced network")).toBeInTheDocument();
    expect(screen.getByText("Admin operations")).toBeInTheDocument();
    expect(screen.getByText("Sleep prevention service")).toBeInTheDocument();
    expect(screen.getByText("VitalDB Observer")).toBeInTheDocument();
    expect(screen.getByText("Redis UI")).toBeInTheDocument();
    expect(screen.getByText("Swagger UI")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("VitalServer URL"), {
      target: { value: "http://127.0.0.1:18080/" }
    });
    fireEvent.click(screen.getAllByRole("button", { name: "Apply Settings" })[0]);
    fireEvent.click(screen.getByLabelText("Reset admin password"));
    fireEvent.change(screen.getByLabelText("New admin password"), {
      target: { value: "new-admin-password" }
    });
    fireEvent.click(screen.getAllByRole("button", { name: "Apply Settings" })[1]);
    fireEvent.click(screen.getByRole("button", { name: "Start Runtime Services" }));
    fireEvent.click(screen.getByRole("button", { name: "Stop Runtime Services" }));
    fireEvent.click(screen.getByRole("row", { name: /backup-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Rollback" }));
    fireEvent.click(screen.getByRole("button", { name: "Create Redis-only Backup" }));
    fireEvent.click(screen.getByRole("button", { name: "Create Backup" }));
    fireEvent.click(screen.getByRole("row", { name: /runtime-data-a/ }));
    fireEvent.click(screen.getByRole("button", { name: "Restore Backup" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair Runtime" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair Data Store" }));
    fireEvent.click(screen.getByRole("button", { name: "Repair VM Disk" }));
    fireEvent.change(screen.getByLabelText("Proxy port"), {
      target: { value: "18444" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Repair Proxy" }));

    expect(applySettings.mutate).toHaveBeenNthCalledWith(1, {
      settings: expect.objectContaining({
        vitalServerURL: "http://127.0.0.1:18080/",
        remoteConsoleURL: "http://console.example.test/"
      })
    });
    expect(applySettings.mutate).toHaveBeenNthCalledWith(2, {
      settings: expect.objectContaining({
        changeAdminPassword: true,
        adminPassword: "new-admin-password"
      })
    });
    expect(start.mutate).toHaveBeenCalled();
    expect(stop.mutate).toHaveBeenCalled();
    expect(rollback.mutate).toHaveBeenCalledWith("/tmp/backup-a");
    expect(createRedisBackup.mutate).toHaveBeenCalledWith("");
    expect(createRuntimeDataBackup.mutate).toHaveBeenCalledWith("");
    expect(restoreRuntimeDataBackup.mutate).toHaveBeenCalledWith("/tmp/runtime-data-a");
    expect(repairRuntime.mutate).toHaveBeenCalled();
    expect(repairDatastore.mutate).toHaveBeenCalled();
    expect(repairVMDisk.mutate).toHaveBeenCalled();
    expect(repairProxy.mutate).toHaveBeenCalledWith(18444);
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
    expect(screen.getByText("Standard uninstall is temporarily unavailable.")).toBeInTheDocument();
    expect(uninstall.mutate).toHaveBeenCalledOnce();
    expect(uninstall.mutate).toHaveBeenCalledWith(true);
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
      prefix: "testbed"
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

  it("does not turn missing TestKit status into empty beds or sessions", () => {
    hooks.useTestKitStatus.mockReturnValue(query(undefined));

    renderPage(<TestKitPage />);

    expect(screen.getAllByText("Not reported").length).toBeGreaterThanOrEqual(5);
    expect(screen.getByText("TestKit bed state is not reported.")).toBeInTheDocument();
    expect(screen.getByText("TestKit session state is not reported.")).toBeInTheDocument();
    expect(
      screen.queryByText("Create beds before starting VRecorders.")
    ).not.toBeInTheDocument();
    expect(
      screen.queryByText("No virtual recorder sessions.")
    ).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Start" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Create" })).toBeDisabled();
  });

  it("shows page-level query errors", () => {
    hooks.useRuntimeOverview.mockReturnValue(failedQuery(new Error("overview denied")));
    hooks.useVitalDBRecorders.mockReturnValue(failedQuery(new Error("beds denied")));

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
  hooks.useVitalDBRelationships.mockReturnValue(query(relationships()));
  hooks.useRuntimeEvents.mockReturnValue(query(events()));
  hooks.useHostLogs.mockReturnValue(query({ text: "line one\nline two" }));
  hooks.useHostBackups.mockReturnValue(query([{ path: "/tmp/backup-a", sizeBytes: 2048 }]));
  hooks.useRedisBackups.mockReturnValue(query([{ path: "/tmp/redis-a", sizeBytes: 1024 }]));
  hooks.useRuntimeDataBackups.mockReturnValue(query([{ path: "/tmp/runtime-data-a", sizeBytes: 4096 }]));
  hooks.useTestKitStatus.mockReturnValue(query(testKitStatus()));

  for (const mock of [
    hooks.useApplyRuntimeSettings,
    hooks.useApplyUpdateBundle,
    hooks.useCreateRedisBackup,
    hooks.useCreateRuntimeDataBackup,
    hooks.useCreateTestKitBeds,
    hooks.useDeleteHostBackup,
    hooks.useDeleteRuntimeDataBackup,
    hooks.useDeleteUpdateBackup,
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
    hooks.useRestoreRuntimeDataBackup,
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
    canUseTestTools: true,
    canApplySettings: true,
    canApplyRuntimeSettings: true,
    canControlRecovery: true,
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
      sleepPreventionServiceLoaded: true,
      redisUIHTTP: "HTTP 200",
      swaggerUIHTTP: "HTTP 200",
      cpuUsagePercent: 12,
      dataDirectoryStats: { fileCount: 2, sizeBytes: 4096 },
      memory: { usedBytes: 2048, totalBytes: 4096 },
      systemDisk: { availableBytes: 8192, totalBytes: 16384 },
      dataStorage: { usedBytes: 1024, totalBytes: 2048 },
      containerObservation: {
        recorderIngressHTTP: "HTTP 200",
        recorderIngressStatus: {
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
        },
        recorderIngressStatusReadState: "loaded",
        recorderIngressStatusReadError: null,
        runtimeStateUpdatedAt: null,
        runtimeStateFileUpdatedAt: null,
        runtimeStateFileMetadataReadState: "notRead",
        runtimeStateFileMetadataError: null,
        containerLogsPresent: true,
        containerLogsBytes: null,
        containerLogsUpdatedAt: null,
        containerLogsMetadataError: null,
        composeServicesReadState: "loaded",
        composeServices: [
          {
            service: "app",
            name: "vitalserver-app-1",
            state: "running",
            health: "healthy",
            memoryUsedBytes: 104857600,
            memoryLimitBytes: 536870912,
            exitCode: null,
            startedAt: "2026-05-31T00:00:00Z",
            uptimeSeconds: 3600
          },
          {
            service: "recorder-ingress",
            name: "recorder-ingress-1",
            state: "running",
            health: "healthy",
            memoryUsedBytes: 20971520,
            memoryLimitBytes: 134217728,
            exitCode: null,
            startedAt: "2026-05-31T00:00:00Z",
            uptimeSeconds: 3600
          },
          {
            service: "redis",
            name: "redis-1",
            state: "running",
            health: "healthy",
            memoryUsedBytes: 31457280,
            memoryLimitBytes: null,
            exitCode: null,
            startedAt: "2026-05-31T00:00:00Z",
            uptimeSeconds: 3600
          },
          {
            service: "vitaldb-observer",
            name: "vitaldb-observer-1",
            state: "running",
            health: "healthy",
            exitCode: null,
            startedAt: "2026-05-31T00:00:00Z",
            uptimeSeconds: 3600
          }
        ],
        composeServicesReadError: null
      },
      failureReasons: []
    },
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
        duplicateObservationCount: 0,
        currentAnomalyCount: 1,
        latestAnomalyKind: "stale-recorder",
        latestAnomalySeverity: "warning",
        latestAnomalyMessage: "Recorder activity is stale.",
        latestAnomalyObservedAt: "2026-05-31T01:00:00Z",
        presentInLatestObservation: true,
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
    }
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
      source: "sqliteProjection",
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
      latestAnomalyObservedAt: "2026-05-31T01:00:00Z"
    }
  ];
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
        id: "event-1",
        timestamp: "2026-05-31T01:00:00Z",
        eventType: "status-changed",
        status: "healthy",
        operation: "apply",
        source: "runtime",
        message: "runtime updated",
        failureReasons: []
      },
      {
        id: "event-2",
        timestamp: "2026-05-31T01:05:00Z",
        eventType: "recovery-deferred",
        status: "degraded",
        operation: "watchdog",
        source: "runtime",
        message: "runtime recovered",
        failureReasons: []
      }
    ],
    nextCursor: null,
    matchingCount: 2
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
