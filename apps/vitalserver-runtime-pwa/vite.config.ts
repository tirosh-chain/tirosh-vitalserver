/// <reference types="vitest/config" />

import { fileURLToPath, URL } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

import { loadAppSettings } from "./src/config/appSettings";

export default defineConfig(({ mode }) => {
  const settings = loadAppSettings(loadEnv(mode, process.cwd(), ""));
  if (mode === "production" && settings.runtimeControl.token) {
    throw new Error(
      "Refusing to embed a Runtime Control API token in the production PWA."
    );
  }
  const localAgentOrigin = new URL(settings.runtimeControl.devProxyTarget).origin;
  const localAgentProxy = {
    target: settings.runtimeControl.devProxyTarget,
    changeOrigin: true,
    configure(proxy: { on(event: string, listener: (...args: unknown[]) => void): void }) {
      proxy.on("proxyReq", (...args: unknown[]) => {
        const request = args[0] as { setHeader(name: string, value: string): void };
        request.setHeader("Origin", localAgentOrigin);
      });
    }
  };

  return {
    plugins: [react()],
    resolve: {
      alias: {
        "@": fileURLToPath(new URL("./src", import.meta.url))
      }
    },
    server: {
      port: settings.pwa.devServerPort,
      proxy: {
        "/platform": localAgentProxy,
        "/runtime": localAgentProxy,
        "/vitaldb": localAgentProxy,
        "/host": localAgentProxy,
        "/lab": localAgentProxy
      }
    },
    preview: {
      port: settings.pwa.previewPort
    },
    test: {
      environment: "jsdom",
      setupFiles: ["./src/testing/setup.ts"],
      coverage: {
        provider: "v8",
        reporter: ["text", "html", "lcov"],
        reportsDirectory: "coverage",
        include: ["src/**/*.{ts,tsx}"],
        exclude: [
          "src/domain/runtime-control/contracts/generated/**",
          "src/main.tsx"
        ],
        thresholds: {
          statements: 85,
          branches: 70,
          functions: 85,
          lines: 85
        }
      }
    }
  };
});
