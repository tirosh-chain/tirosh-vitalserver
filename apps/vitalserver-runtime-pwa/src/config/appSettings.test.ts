import { describe, expect, it } from "vitest";

import { DEFAULT_APP_SETTINGS, loadAppSettings } from "./appSettings";

describe("app settings", () => {
  it("uses product defaults when env values are absent", () => {
    expect(loadAppSettings({})).toEqual(DEFAULT_APP_SETTINGS);
  });

  it("does not ship a Platform Agent API token in browser defaults", () => {
    expect(DEFAULT_APP_SETTINGS.runtimeControl.token).toBe("");
  });

  it("loads browser-safe Vite env values", () => {
    const settings = loadAppSettings({
      VITE_RUNTIME_CONTROL_API_BASE_URL: "http://127.0.0.1:18444/",
      VITE_RUNTIME_CONTROL_TOKEN: "token-a",
      VITE_RUNTIME_CONTROL_DEFAULT_PORT: "18444",
      VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT: "8080",
      VITE_QUERY_REFETCH_ON_WINDOW_FOCUS: "true",
      VITE_QUERY_RETRY: "2",
      VITE_QUERY_STALE_TIME_MS: "2500",
      VITE_PWA_DEV_SERVER_PORT: "5175",
      VITE_PWA_PREVIEW_PORT: "4175"
    });

    expect(settings.runtimeControl).toMatchObject({
      apiBaseURL: "http://127.0.0.1:18444",
      devProxyTarget: "http://127.0.0.1:18444",
      token: "token-a",
      defaultPort: 18_444,
      defaultProxyPort: 8_080
    });
    expect(settings.queries).toEqual({
      refetchOnWindowFocus: true,
      retry: 2,
      staleTimeMs: 2_500
    });
    expect(settings.pwa).toEqual({
      devServerPort: 5_175,
      previewPort: 4_175
    });
  });

  it("keeps unprefixed env compatibility for Vite config and scripts", () => {
    const settings = loadAppSettings({
      RUNTIME_CONTROL_DEV_PROXY_TARGET: "http://127.0.0.1:19000/",
      RUNTIME_CONTROL_TOKEN: "token-b"
    });

    expect(settings.runtimeControl.devProxyTarget).toBe("http://127.0.0.1:19000");
    expect(settings.runtimeControl.token).toBe("token-b");
  });

  it("falls back when port values are invalid", () => {
    const settings = loadAppSettings({
      VITE_RUNTIME_CONTROL_DEFAULT_PORT: "70000",
      VITE_RUNTIME_CONTROL_DEFAULT_PROXY_PORT: "-1",
      VITE_PWA_DEV_SERVER_PORT: "0"
    });

    expect(settings.runtimeControl.defaultPort).toBe(
      DEFAULT_APP_SETTINGS.runtimeControl.defaultPort
    );
    expect(settings.runtimeControl.defaultProxyPort).toBe(
      DEFAULT_APP_SETTINGS.runtimeControl.defaultProxyPort
    );
    expect(settings.pwa.devServerPort).toBe(DEFAULT_APP_SETTINGS.pwa.devServerPort);
  });
});
