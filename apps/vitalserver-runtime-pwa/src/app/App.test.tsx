import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";
import { App } from "./App";
import { AppProviders } from "./providers";

describe("App", () => {
  it("renders the console shell, routes, and overflow menu", async () => {
    renderApp(createGateway());

    expect(screen.getByRole("heading", { name: "VitalServer Helper" })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("Platform health")).toBeInTheDocument());

    fireEvent.click(screen.getByText("More"));
    expect(screen.getByRole("link", { name: "Danger Zone" })).toBeInTheDocument();
    expect(screen.getByText("More").closest("details")).toHaveAttribute("open");
  });
});

function renderApp(gateway: ReturnType<typeof createGateway>) {
  return render(
    <MemoryRouter initialEntries={["/"]}>
      <AppProviders
        runtimeControlGateway={gateway as never}
        settings={{
          ...DEFAULT_APP_SETTINGS,
          queries: {
            ...DEFAULT_APP_SETTINGS.queries,
            retry: 0
          }
        }}
      >
        <App />
      </AppProviders>
    </MemoryRouter>
  );
}

function createGateway() {
  return {
    getCapabilities: vi.fn().mockResolvedValue({ canUseLab: true }),
    getPlatformState: vi.fn().mockResolvedValue({
      runtimeInstallationState: "executable",
      services: [],
      platformHealth: "healthy",
      publicProxyHTTP: "HTTP 200",
      platformAPIHTTP: "HTTP 200",
      dataDirectoryStats: { fileCount: 1, sizeBytes: 1024 },
      dataStorage: { usedBytes: 1024, totalBytes: 2048 }
    }),
    getRuntimePlatformSettings: vi.fn().mockResolvedValue({
      state: "unavailable",
      settings: null,
      readIssues: [],
      readError: "Platform settings are unavailable in this shell test."
    }),
    getRuntimeProductSettings: vi.fn().mockResolvedValue({
      state: "unavailable",
      settings: null,
      readError: "Runtime product settings are unavailable in this shell test."
    }),
    getRuntimeStack: vi.fn().mockResolvedValue({
      state: "unavailable",
      observedAt: null,
      services: [],
      probeErrors: ["Runtime stack is unavailable in this shell test."]
    }),
    getVitalDBRecorders: vi.fn().mockResolvedValue({
      state: "unavailable",
      recorders: [],
      readError: "Vital Recorder state is unavailable in this shell test."
    }),
    getOverview: vi.fn().mockResolvedValue({
      settings: {
        readIssues: [],
        cpuCount: 2,
        memoryGiB: 4,
        diskGiB: 32,
        minimumDiskGiB: 4,
        networkMode: "shared",
        bridgedInterface: "",
        proxyPort: 18080,
        runtimeControlPort: 18321,
        vitalFilesDirectory: "/Users/shared/vital",
        publicHost: "",
        publicPort: 18080,
        adminPassword: "",
        changeAdminPassword: false,
        startOnBoot: true,
        startOnBootConfigurable: true,
        autoRecoveryEnabled: true,
        preventSystemSleep: true,
        automaticBackupEnabled: true,
    backupScheduleTimes: ["03:15"],
        backupRetentionCount: 30,
        restartAfterSave: true
      },
      vitalRecorder: {
        activeConnections: 0,
        knownRecorders: 0,
        onlineRecorders: 0,
        staleRecorders: 0,
        knownBeds: 0,
        recorderAnomalies: 0
      }
    })
  };
}
