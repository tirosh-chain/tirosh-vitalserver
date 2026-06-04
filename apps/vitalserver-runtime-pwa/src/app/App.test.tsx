import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";
import { App } from "./App";
import { AppProviders } from "./providers";

describe("App", () => {
  it("renders the console shell, routes, and overflow menu", async () => {
    renderApp(createGateway({ canUseTestTools: true }));

    expect(screen.getByRole("heading", { name: "VitalServer Helper" })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("Overall health")).toBeInTheDocument());

    fireEvent.click(screen.getByText("More"));
    expect(screen.getByRole("link", { name: "Test" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Danger Zone" })).toBeInTheDocument();
    expect(screen.getByText("More").closest("details")).toHaveAttribute("open");
  });

  it("hides TestKit routes when the helper capability is unavailable", async () => {
    renderApp(createGateway({ canUseTestTools: false }));

    await waitFor(() => expect(screen.getByText("Overall health")).toBeInTheDocument());
    fireEvent.click(screen.getByText("More"));

    expect(screen.queryByRole("link", { name: "Test" })).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Danger Zone" })).toBeInTheDocument();
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

function createGateway(capabilities: { canUseTestTools: boolean }) {
  return {
    getCapabilities: vi.fn().mockResolvedValue(capabilities),
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
        redisBackupRetentionCount: 30,
        restartAfterSave: true
      },
      status: {
        runtimeState: "healthy",
        hostProxyHTTP: "HTTP 200",
        runtimeControlHTTP: "HTTP 200",
        dataDirectoryStats: { fileCount: 1, sizeBytes: 1024 },
        memory: { usedBytes: 1024, totalBytes: 2048 },
        systemDisk: { availableBytes: 1024, totalBytes: 2048 },
        dataStorage: { usedBytes: 1024, totalBytes: 2048 }
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
