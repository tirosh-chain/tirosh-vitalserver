import type { ComponentType } from "react";

import { AdvancedPage } from "../features/advanced/AdvancedPage";
import { BedsPage } from "../features/beds/BedsPage";
import { DangerZonePage } from "../features/danger-zone/DangerZonePage";
import { LogsPage } from "../features/logs/LogsPage";
import { ObservabilityPage } from "../features/observability/ObservabilityPage";
import { RecordersPage } from "../features/recorders/RecordersPage";
import { SettingsPage } from "../features/settings/SettingsPage";
import { StatusPage } from "../features/status/StatusPage";
import { TestKitPage } from "../features/testkit/TestKitPage";
import { UpdatePage } from "../features/update/UpdatePage";

export type RuntimeControlRoute = {
  path: string;
  label: string;
  Page: ComponentType;
};

export const runtimeControlRoutes: RuntimeControlRoute[] = [
  { path: "/", label: "Status", Page: StatusPage },
  { path: "/settings", label: "Settings", Page: SettingsPage },
  { path: "/update", label: "Update", Page: UpdatePage },
  { path: "/observability", label: "Observability", Page: ObservabilityPage },
  { path: "/recorders", label: "Recorders", Page: RecordersPage },
  { path: "/beds", label: "Beds", Page: BedsPage },
  { path: "/logs", label: "Logs", Page: LogsPage },
  { path: "/advanced", label: "Advanced", Page: AdvancedPage },
  { path: "/danger-zone", label: "Danger Zone", Page: DangerZonePage },
  { path: "/test", label: "Test", Page: TestKitPage }
];
