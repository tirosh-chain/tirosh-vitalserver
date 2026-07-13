import type { components, paths } from "./generated/runtime-control";
import {
  runtimeLabBedListSchema,
  runtimeLabVitalFileListSchema,
  runtimeLabRecorderListSchema,
  runtimeLabRecorderResponseSchema,
  runtimeLabSessionListSchema,
  runtimeEventHistorySchema,
  platformOperationStateSchema,
  platformWorkflowOperationSchema,
  platformWorkflowResourceSchema,
  runtimeProviderCommandResponseSchema,
  runtimeGuestControlStackStatusSchema,
  runtimeRedisRelayStatusReadResultSchema,
  runtimeRedisRelaySettingsReadSchema,
  runtimeProductSettingsReadSchema,
  runtimeProductSettingsSchema,
  runtimeSettingsSchema,
  runtimeVitalDBObservationSnapshotSchema,
  platformStateSchema,
  vitalDBBedsSchema,
  vitalDBRecordersSchema,
  vitalDBRelationshipsSchema
} from "./schemas/runtimeControlSchemas";
import type { z } from "zod";

export type RuntimeCapabilities =
  paths["/runtime/capabilities"]["get"]["responses"]["200"]["content"]["application/json"];

export type PlatformCapabilities =
  paths["/platform/capabilities"]["get"]["responses"]["200"]["content"]["application/json"];

/** Client presentation capabilities composed from two independently read owners. */
export type ControlCapabilities = PlatformCapabilities & {
  canControlGuestServices: boolean;
  canUseLab: boolean;
  canListLabSessions?: boolean;
  canControlLabRecorders?: boolean;
  canRepairRuntimeDatastore: boolean;
  canApplyRuntimeProductSettings?: boolean;
  canApplyRuntimeAdminPassword?: boolean;
  canApplyRuntimeRedisRelaySettings?: boolean;
};

export type RuntimeLabScenarioList =
  paths["/runtime/lab/scenarios"]["get"]["responses"]["200"]["content"]["application/json"];

export type RuntimeLabScenario = RuntimeLabScenarioList["scenarios"][number];

export type RuntimeLabBedList = z.infer<typeof runtimeLabBedListSchema>;

export type RuntimeLabBed = RuntimeLabBedList["beds"][number];

export type RuntimeLabBedCreateRequest =
  paths["/runtime/lab/beds/create"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabBedDeleteRequest =
  paths["/runtime/lab/beds/delete"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabRecorderList = z.infer<typeof runtimeLabRecorderListSchema>;

export type RuntimeLabRecorder = RuntimeLabRecorderList["recorders"][number];

export type RuntimeLabRecorderResponse =
  z.infer<typeof runtimeLabRecorderResponseSchema>;

export type RuntimeLabRecorderCreateRequest =
  paths["/runtime/lab/recorders/create"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabRecorderDeleteRequest =
  paths["/runtime/lab/recorders/delete"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabSessionResponse =
  paths["/runtime/lab/sessions"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeLabSession = NonNullable<RuntimeLabSessionResponse["session"]>;

export type RuntimeLabSessionList = z.infer<typeof runtimeLabSessionListSchema>;

export type RuntimeLabSessionCreateRequest =
  paths["/runtime/lab/sessions"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabVitalFileReplayRequest =
  paths["/runtime/lab/vital-files/replay"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabVitalFileList = z.infer<typeof runtimeLabVitalFileListSchema>;

export type RuntimeLabVitalFile = RuntimeLabVitalFileList["vitalFiles"][number];

export type RuntimeLabVitalFileUploadRequest =
  paths["/runtime/lab/vital-files/upload"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLabVitalFileUploadResponse =
  paths["/runtime/lab/vital-files/upload"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeGuestServiceControlRequest =
  components["schemas"]["RuntimeGuestServiceRestartRequest"];

export type RuntimeGuestControlServiceOperation =
  components["schemas"]["RuntimeGuestControlServiceOperation"];

export type RuntimeGuestControlStackStatus =
  z.infer<typeof runtimeGuestControlStackStatusSchema>;

export type RuntimeGuestControlServiceStatus =
  components["schemas"]["RuntimeGuestControlServiceStatus"];

export type RuntimeGuestServiceResource =
  components["schemas"]["RuntimeGuestServiceResource"];

export type PlatformState = z.infer<typeof platformStateSchema>;

export type RuntimeRedisRelayStatusReadResult =
  z.infer<typeof runtimeRedisRelayStatusReadResultSchema>;

export type RuntimeRedisRelaySettingsRead =
  z.infer<typeof runtimeRedisRelaySettingsReadSchema>;

export type RuntimeRedisRelaySettingsApplyRequest =
  paths["/runtime/redis-relay/settings"]["put"]["requestBody"]["content"]["application/json"];

export type PlatformOperationState = z.infer<typeof platformOperationStateSchema>;

export type PlatformWorkflowOperation = z.infer<typeof platformWorkflowOperationSchema>;

export type PlatformWorkflowResource = z.infer<typeof platformWorkflowResourceSchema>;

export type RuntimeSettings =
  z.infer<typeof runtimeSettingsSchema>;

export type RuntimeProductSettings = z.infer<typeof runtimeProductSettingsSchema>;

export type RuntimeProductSettingsRead =
  z.infer<typeof runtimeProductSettingsReadSchema>;

export type RuntimeApplyProductSettingsRequest =
  paths["/runtime/settings"]["put"]["requestBody"]["content"]["application/json"];

export type RuntimeAdminPasswordRequest =
  paths["/runtime/admin-password"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeUninstallRequest =
  paths["/platform/uninstall"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeCommandResponse =
  components["schemas"]["RuntimeControlCommandResponse"];

/** Explicit result of a Platform-owned Runtime Provider start, stop, or restart effect. */
export type RuntimeProviderCommandResponse =
  z.infer<typeof runtimeProviderCommandResponseSchema>;

export type RuntimeUpdateBundleRequest =
  paths["/platform/update-bundles/summary"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeUpdateBundleSummaryResponse =
  paths["/platform/update-bundles/summary"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeBackup =
  paths["/platform/backups"]["get"]["responses"]["200"]["content"]["application/json"][number];

export type RuntimeBackupRequest =
  paths["/platform/backups/rollback"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeEventHistory = z.infer<typeof runtimeEventHistorySchema>;

export type RuntimeEventDocument = NonNullable<
  RuntimeEventHistory["events"]
>[number];

export type VitalDBObservationDocument =
  components["schemas"]["VitalDBObservationDocument"];

export type RuntimeVitalDBObservationSnapshot =
  z.infer<typeof runtimeVitalDBObservationSnapshotSchema>;

export type VitalDBAnomalyObservation =
  components["schemas"]["VitalDBAnomalyObservation"];

export type RuntimeLogSource = components["schemas"]["RuntimeLogSource"];

export type RuntimeLogTextRequest =
  paths["/platform/logs/read"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLogTextResponse =
  paths["/platform/logs/read"]["post"]["responses"]["200"]["content"]["application/json"];

export type RuntimeExportLogsRequest =
  paths["/platform/logs/export"]["post"]["requestBody"]["content"]["application/json"];

export type RuntimeLogExportResult =
  paths["/platform/logs/export"]["post"]["responses"]["200"]["content"]["application/json"];

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
