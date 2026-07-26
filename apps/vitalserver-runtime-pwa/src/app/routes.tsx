import type { ComponentType } from "react";

import { AdvancedPage } from "@/pages/advanced/AdvancedPage";
import { BedsPage } from "@/pages/beds/BedsPage";
import { DangerZonePage } from "@/pages/danger-zone/DangerZonePage";
import { LabPage } from "@/pages/lab/LabPage";
import { LogsPage } from "@/pages/logs/LogsPage";
import { InfoPage } from "@/pages/info/InfoPage";
import { ObservabilityPage } from "@/pages/observability/ObservabilityPage";
import { RecordersPage } from "@/pages/recorders/RecordersPage";
import { SettingsPage } from "@/pages/settings/SettingsPage";
import { StatusPage } from "@/pages/status/StatusPage";
import { UpdatePage } from "@/pages/update/UpdatePage";

export type ConsoleRoute = {
  path: string;
  label: string;
  Page: ComponentType;
  group: "primary" | "utility" | "overflow";
};

export const consoleRoutes: ConsoleRoute[] = [
  { path: "/", label: "Status", Page: StatusPage, group: "primary" },
  {
    path: "/recorders",
    label: "Recorders",
    Page: RecordersPage,
    group: "primary"
  },
  { path: "/beds", label: "Beds", Page: BedsPage, group: "primary" },
  {
    path: "/lab",
    label: "Lab",
    Page: LabPage,
    group: "primary"
  },
  { path: "/settings", label: "Settings", Page: SettingsPage, group: "primary" },
  { path: "/update", label: "Update", Page: UpdatePage, group: "primary" },
  { path: "/advanced", label: "Advanced", Page: AdvancedPage, group: "utility" },
  {
    path: "/observability",
    label: "Observability",
    Page: ObservabilityPage,
    group: "overflow"
  },
  { path: "/logs", label: "Logs", Page: LogsPage, group: "overflow" },
  { path: "/info", label: "Info", Page: InfoPage, group: "overflow" },
  {
    path: "/danger-zone",
    label: "Danger Zone",
    Page: DangerZonePage,
    group: "overflow"
  }
];
