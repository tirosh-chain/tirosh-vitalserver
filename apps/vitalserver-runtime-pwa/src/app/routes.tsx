import type { ComponentType } from "react";

import { AdvancedPage } from "@/pages/advanced/AdvancedPage";
import { BedsPage } from "@/pages/beds/BedsPage";
import { DangerZonePage } from "@/pages/danger-zone/DangerZonePage";
import { LogsPage } from "@/pages/logs/LogsPage";
import { ObservabilityPage } from "@/pages/observability/ObservabilityPage";
import { RecordersPage } from "@/pages/recorders/RecordersPage";
import { SettingsPage } from "@/pages/settings/SettingsPage";
import { StatusPage } from "@/pages/status/StatusPage";
import { TestKitPage } from "@/pages/testkit/TestKitPage";
import { UpdatePage } from "@/pages/update/UpdatePage";

export type RuntimeControlRoute = {
  path: string;
  label: string;
  Page: ComponentType;
  group: "primary" | "utility" | "overflow";
  requiresTestTools?: boolean;
};

export const runtimeControlRoutes: RuntimeControlRoute[] = [
  { path: "/", label: "Status", Page: StatusPage, group: "primary" },
  {
    path: "/recorders",
    label: "Recorders",
    Page: RecordersPage,
    group: "primary"
  },
  { path: "/beds", label: "Beds", Page: BedsPage, group: "primary" },
  {
    path: "/observability",
    label: "Observability",
    Page: ObservabilityPage,
    group: "primary"
  },
  { path: "/logs", label: "Logs", Page: LogsPage, group: "primary" },
  { path: "/settings", label: "Settings", Page: SettingsPage, group: "primary" },
  { path: "/update", label: "Update", Page: UpdatePage, group: "primary" },
  { path: "/advanced", label: "Advanced", Page: AdvancedPage, group: "utility" },
  {
    path: "/danger-zone",
    label: "Danger Zone",
    Page: DangerZonePage,
    group: "overflow"
  },
  {
    path: "/test",
    label: "Test",
    Page: TestKitPage,
    group: "overflow",
    requiresTestTools: true
  }
];
