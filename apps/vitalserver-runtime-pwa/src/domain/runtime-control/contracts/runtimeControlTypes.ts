import type { components, paths } from "./generated/runtime-control";

type CompatValue<T extends string | null> = T | (string & {});

type RuntimeStateWithUnknown =
  CompatValue<components["schemas"]["RuntimeState"]>;

type RuntimeVMStateWithUnknown =
  CompatValue<components["schemas"]["RuntimeVMState"]>;

type RuntimeEventTypeWithUnknown =
  CompatValue<components["schemas"]["RuntimeEventType"]>;

type RuntimeStatusResponse =
  paths["/runtime/status"]["get"]["responses"]["200"]["content"]["application/json"];

type RuntimeOverviewResponse =
  paths["/runtime/overview"]["get"]["responses"]["200"]["content"]["application/json"];

type RuntimeEventHistoryResponse =
  paths["/runtime/events"]["get"]["responses"]["200"]["content"]["application/json"];

type RuntimeEventDocumentResponse = components["schemas"]["RuntimeEventDocument"];

type RuntimeStatusWithCompat = Omit<
  RuntimeStatusResponse,
  "runtimeState" | "vmState"
> & {
  runtimeState?: RuntimeStateWithUnknown;
  vmState?: RuntimeVMStateWithUnknown;
};

type RuntimeEventDocumentWithCompat = Omit<
  RuntimeEventDocumentResponse,
  "eventType" | "status" | "vmState"
> & {
  eventType: RuntimeEventTypeWithUnknown;
  status?: RuntimeStateWithUnknown;
  vmState?: RuntimeVMStateWithUnknown;
};

type RuntimeEventHistoryWithCompat = Omit<
  RuntimeEventHistoryResponse,
  "events"
> & {
  events: RuntimeEventDocumentWithCompat[];
};

type RuntimeOverviewWithCompat = Omit<
  RuntimeOverviewResponse,
  "status"
> & {
  status: RuntimeStatusWithCompat;
};

export type RuntimeControlOverview =
  RuntimeOverviewWithCompat;

export type RuntimeControlCapabilities =
  paths["/runtime/capabilities"]["get"]["responses"]["200"]["content"]["application/json"];

export type RuntimeStatus =
  RuntimeStatusWithCompat;

export type RuntimeSettings =
  paths["/runtime/settings"]["get"]["responses"]["200"]["content"]["application/json"];

export type RuntimeApplySettingsRequest =
  paths["/runtime/settings"]["put"]["requestBody"]["content"]["application/json"];

export type RuntimeUninstallRequest =
  paths["/runtime/uninstall"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeCommandResponse =
  components["schemas"]["RuntimeControlCommandResponse"];

export type RuntimeUpdateBundleRequest =
  paths["/host/update-bundles/summary"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeUpdateBundleSummaryResponse =
  paths["/host/update-bundles/summary"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeBackup =
  paths["/host/backups"]["get"]["responses"]["200"]["content"]["application/json"][number];

export type RuntimeBackupRequest =
  paths["/host/backups/rollback"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeEventHistory =
  RuntimeEventHistoryWithCompat;

export type RuntimeEventDocument = NonNullable<
  RuntimeEventHistory["events"]
>[number];

export type VitalDBObservationDocument =
  components["schemas"]["VitalDBObservationDocument"];

export type VitalDBAnomalyObservation =
  components["schemas"]["VitalDBAnomalyObservation"];

export type RuntimeLogSource = components["schemas"]["RuntimeLogSource"];

export type RuntimeLogTextRequest =
  paths["/host/logs/read"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLogTextResponse =
  paths["/host/logs/read"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeExportLogsRequest =
  paths["/host/logs/export"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLogExportResult =
  paths["/host/logs/export"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeTestKitStatus =
  paths["/dev/testkit/status"]["get"]["responses"]["200"]["content"]["application/json"];

export type RuntimeTestKitBed =
  paths["/dev/testkit/beds/create"]["post"]["responses"]["200"]["content"]["application/json"][number];

export type RuntimeTestKitSession =
  paths["/dev/testkit/virtual-recorders/start"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeTestKitCreateBedsRequest =
  paths["/dev/testkit/beds/create"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeTestKitDeleteBedsRequest =
  paths["/dev/testkit/beds/delete"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeTestKitVirtualRecorderStartRequest =
  paths["/dev/testkit/virtual-recorders/start"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeTestKitSessionSelectionRequest =
  NonNullable<
    paths["/dev/testkit/virtual-recorders/stop"]["post"]["requestBody"]
  >["content"]["application/json"];

export type RuntimeTestKitRestartRequest =
  paths["/dev/testkit/virtual-recorders/restart"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeTestKitRecorderDeletionRequest =
  paths["/dev/testkit/virtual-recorders/delete-orphan"]["post"]["requestBody"]["content"]["application/json"];

export type VitalDBRecorders =
  paths["/vitaldb/recorders"]["get"]["responses"]["200"]["content"]["application/json"];

export type VitalDBRecorderRecord = NonNullable<
  VitalDBRecorders["recorders"]
>[number];

export type VitalDBBeds =
  paths["/vitaldb/beds"]["get"]["responses"]["200"]["content"]["application/json"];

export type VitalDBBedRecord = VitalDBBeds[number];
