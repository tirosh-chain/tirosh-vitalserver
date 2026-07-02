/// <reference types="vitest/config" />

import { fileURLToPath, URL } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

import { loadAppSettings } from "./src/config/appSettings";

export default defineConfig(({ mode }) => {
  const settings = loadAppSettings(loadEnv(mode, process.cwd(), ""));

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
        "/runtime": settings.runtimeControl.devProxyTarget,
        "/vitaldb": settings.runtimeControl.devProxyTarget,
        "/host": settings.runtimeControl.devProxyTarget,
        "/lab": settings.runtimeControl.devProxyTarget
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
