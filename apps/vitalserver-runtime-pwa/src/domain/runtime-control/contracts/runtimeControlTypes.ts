import type { components, paths } from "./generated/runtime-control";
import {
  runtimeLabBedListSchema,
  runtimeLabVitalFileListSchema,
  runtimeLabRecorderListSchema,
  runtimeEventHistorySchema,
  runtimeOperationStateSchema,
  runtimeOverviewSchema,
  runtimeGuestControlStackStatusSchema,
  runtimeStatusSchema,
  vitalDBBedsSchema,
  vitalDBRecordersSchema,
  vitalDBRelationshipsSchema
} from "./schemas/runtimeControlSchemas";
import type { z } from "zod";

export type RuntimeControlOverview = z.infer<typeof runtimeOverviewSchema>;

export type RuntimeControlCapabilities =
  paths["/runtime/capabilities"]["get"]["responses"]["200"]["content"]["application/json"];

export type RuntimeLabScenarioList =
  paths["/lab/scenarios"]["get"]["responses"]["200"]["content"]["application/json"];

export type RuntimeLabScenario = RuntimeLabScenarioList["scenarios"][number];

export type RuntimeLabBedList = z.infer<typeof runtimeLabBedListSchema>;

export type RuntimeLabBed = RuntimeLabBedList["beds"][number];

export type RuntimeLabBedCreateRequest =
  paths["/lab/beds/create"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabBedDeleteRequest =
  paths["/lab/beds/delete"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabRecorderList = z.infer<typeof runtimeLabRecorderListSchema>;

export type RuntimeLabRecorder = RuntimeLabRecorderList["recorders"][number];

export type RuntimeLabRecorderCreateRequest =
  paths["/lab/recorders/create"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabRecorderDeleteRequest =
  paths["/lab/recorders/delete"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabSessionResponse =
  paths["/lab/sessions"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeLabSession = NonNullable<RuntimeLabSessionResponse["session"]>;

export type RuntimeLabSessionCreateRequest =
  paths["/lab/sessions"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabVitalFileReplayRequest =
  paths["/lab/vital-files/replay"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabVitalFileList = z.infer<typeof runtimeLabVitalFileListSchema>;

export type RuntimeLabVitalFile = RuntimeLabVitalFileList["vitalFiles"][number];

export type RuntimeLabVitalFileUploadRequest =
  paths["/lab/vital-files/upload"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabVitalFileUploadResponse =
  paths["/lab/vital-files/upload"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeGuestServiceControlRequest =
  components["schemas"]["RuntimeGuestServiceRestartRequest"];

export type RuntimeGuestControlServiceOperation =
  components["schemas"]["RuntimeGuestControlServiceOperation"];

export type RuntimeGuestControlStackStatus =
  z.infer<typeof runtimeGuestControlStackStatusSchema>;

export type RuntimeGuestControlServiceStatus =
  components["schemas"]["RuntimeGuestControlServiceStatus"];

export type RuntimeStatus = z.infer<typeof runtimeStatusSchema>;

export type RuntimeOperationState = z.infer<typeof runtimeOperationStateSchema>;

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

export type RuntimeEventHistory = z.infer<typeof runtimeEventHistorySchema>;

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

export type VitalDBRecorders = z.infer<typeof vitalDBRecordersSchema>;

export type VitalDBRecorderRecord = NonNullable<
  VitalDBRecorders["recorders"]
>[number];

export type VitalDBRecorderVisibilityRequest = {
  vrcodes: string[];
};

export type VitalDBBeds = z.infer<typeof vitalDBBedsSchema>;

export type VitalDBBedRecord = VitalDBBeds["beds"][number];

export type VitalDBBedVisibilityRequest = {
  bedIDs: string[];
};

export type VitalDBRelationships = z.infer<typeof vitalDBRelationshipsSchema>;

export type VitalDBRelationshipAssignment = NonNullable<
  VitalDBRelationships["assignments"]
>[number];

export type VitalDBRelationshipEvent = NonNullable<
  VitalDBRelationships["events"]
>[number];
