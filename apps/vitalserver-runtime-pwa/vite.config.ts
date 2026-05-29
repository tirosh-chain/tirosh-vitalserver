import { fileURLToPath, URL } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

import { loadAppSettings } from "./src/shared/config/appSettings";

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
        "/dev/testkit": settings.runtimeControl.devProxyTarget
      }
    },
    preview: {
      port: settings.pwa.previewPort
    }
  };
});
