import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";

import { App } from "@/app/App";
import { AppProviders } from "@/app/providers";
import {
  loadBrowserAppSettings,
  type AppSettings
} from "@/config/appSettings";
import { RuntimeControlClient } from "@/infrastructure/runtime-control-api/runtimeControlClient";

export function bootstrapApp(settings: AppSettings = loadBrowserAppSettings()) {
  const runtimeControlGateway = new RuntimeControlClient({
    baseURL: settings.runtimeControl.apiBaseURL,
    token: settings.runtimeControl.token
  });

  const root = document.getElementById("root");

  if (!root) {
    throw new Error("Missing root element");
  }

  createRoot(root).render(
    <StrictMode>
      <BrowserRouter>
        <AppProviders
          runtimeControlGateway={runtimeControlGateway}
          settings={settings}
        >
          <App />
        </AppProviders>
      </BrowserRouter>
    </StrictMode>
  );
}
