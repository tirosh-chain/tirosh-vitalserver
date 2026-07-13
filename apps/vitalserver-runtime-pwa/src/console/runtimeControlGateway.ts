import type {
  RuntimeApplyProductSettingsRequest,
  RuntimeApplyPlatformSettingsRequest,
  RuntimeAdminPasswordRequest,
  RuntimeBackup,
  RuntimeBackupRequest,
  RuntimeCommandResponse,
  ControlCapabilities,
  PlatformCapabilities,
  RuntimeCapabilities,
  RuntimeEventHistory,
  RuntimeExportLogsRequest,
  RuntimeGuestControlStackStatus,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabBedList,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabRecorderList,
  RuntimeLabRecorderResponse,
  RuntimeLabScenarioList,
  RuntimeLabSessionCreateRequest,
  RuntimeLabSessionResponse,
  RuntimeLabSessionList,
  RuntimeLabVitalFileList,
  RuntimeLabVitalFileUploadRequest,
  RuntimeLabVitalFileUploadResponse,
  RuntimeLabVitalFileReplayRequest,
  RuntimeGuestControlServiceOperation,
  RuntimeGuestServiceResource,
  RuntimeGuestServiceControlRequest,
  RuntimeLogExportResult,
  RuntimeLogTextRequest,
  RuntimeLogTextResponse,
  PlatformOperationState,
  PlatformWorkflowOperation,
  PlatformWorkflowResource,
  RuntimeRedisRelayStatusReadResult,
  RuntimeRedisRelaySettingsRead,
  RuntimeRedisRelaySettingsApplyRequest,
  RuntimeVitalDBObservationSnapshot,
  RuntimeVitalRecorderActivityWindow,
  RuntimeVitalRecorderActivityWindowQuery,
  RuntimeReleaseInfo,
  RuntimeInstallInfo,
  RuntimeProductSettingsRead,
  RuntimePlatformSettingsRead,
  RuntimeProviderCommandResponse,
  PlatformState,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest,
  RuntimeUpdateBundleSummaryResponse,
  VitalDBBedVisibilityRequest,
  VitalDBBeds,
  VitalDBRecorderVisibilityRequest,
  VitalDBRecorders,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import type { RuntimeEventTypeValue } from "@/domain/runtime-control/contracts/runtimeEventTypes";

export type RuntimeEventQuery = {
  limit?: number;
  type?: RuntimeEventTypeValue;
  since?: string;
  cursor?: string;
};

export type RuntimeControlGateway = {
  getPlatformCapabilities(): Promise<PlatformCapabilities>;
  getRuntimeCapabilities(): Promise<RuntimeCapabilities>;
  getCapabilities(): Promise<ControlCapabilities>;
  getPlatformState(): Promise<PlatformState>;
  getRedisRelayStatus(): Promise<RuntimeRedisRelayStatusReadResult>;
  getRuntimeRedisRelaySettings(): Promise<RuntimeRedisRelaySettingsRead>;
  applyRuntimeRedisRelaySettings(
    request: RuntimeRedisRelaySettingsApplyRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  getLatestVitalDBObservation(): Promise<RuntimeVitalDBObservationSnapshot>;
  getOperationState(): Promise<PlatformOperationState>;
  getPlatformWorkflow(): Promise<PlatformWorkflowResource>;
  getRuntimeProductSettings(): Promise<RuntimeProductSettingsRead>;
  getRuntimePlatformSettings(): Promise<RuntimePlatformSettingsRead>;
  applyRuntimePlatformSettings(
    request: RuntimeApplyPlatformSettingsRequest
  ): Promise<RuntimeCommandResponse>;
  applyRuntimeProductSettings(
    request: RuntimeApplyProductSettingsRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  applyRuntimeAdminPassword(
    request: RuntimeAdminPasswordRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  getLabScenarios(): Promise<RuntimeLabScenarioList>;
  getLabBeds(): Promise<RuntimeLabBedList>;
  getLabRecorders(): Promise<RuntimeLabRecorderList>;
  createLabBeds(request: RuntimeLabBedCreateRequest): Promise<RuntimeLabBedList>;
  deleteLabBeds(request: RuntimeLabBedDeleteRequest): Promise<RuntimeLabBedList>;
  resetLabBeds(): Promise<RuntimeLabBedList>;
  createLabRecorders(
    request: RuntimeLabRecorderCreateRequest
  ): Promise<RuntimeLabRecorderList>;
  deleteLabRecorders(
    request: RuntimeLabRecorderDeleteRequest
  ): Promise<RuntimeLabRecorderList>;
  resetLabRecorders(): Promise<RuntimeLabRecorderList>;
  getLabSessions(): Promise<RuntimeLabSessionList>;
  createLabSession(
    request: RuntimeLabSessionCreateRequest
  ): Promise<RuntimeLabSessionResponse>;
  getLabSession(sessionId: string): Promise<RuntimeLabSessionResponse>;
  startLabSession(sessionId: string): Promise<RuntimeLabSessionResponse>;
  stopLabSession(sessionId: string): Promise<RuntimeLabSessionResponse>;
  startLabRecorder(
    sessionId: string,
    recorderId: string
  ): Promise<RuntimeLabRecorderResponse>;
  stopLabRecorder(
    sessionId: string,
    recorderId: string
  ): Promise<RuntimeLabRecorderResponse>;
  getLabVitalFiles(): Promise<RuntimeLabVitalFileList>;
  uploadLabVitalFile(
    request: RuntimeLabVitalFileUploadRequest
  ): Promise<RuntimeLabVitalFileUploadResponse>;
  replayLabVitalFile(
    request: RuntimeLabVitalFileReplayRequest
  ): Promise<RuntimeLabSessionResponse>;
  getRuntimeStack(): Promise<RuntimeGuestControlStackStatus>;
  getGuestServiceResource(service: string): Promise<RuntimeGuestServiceResource>;
  startGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  stopGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  restartGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  uninstallRuntime(request: RuntimeUninstallRequest): Promise<PlatformWorkflowOperation>;
  getRuntimeEvents(query?: RuntimeEventQuery): Promise<RuntimeEventHistory>;
  getRecorders(): Promise<VitalDBRecorders>;
  getRecorderActivity(
    query: RuntimeVitalRecorderActivityWindowQuery
  ): Promise<RuntimeVitalRecorderActivityWindow>;
  getReleaseInfo(): Promise<RuntimeReleaseInfo>;
  getInstallInfo(): Promise<RuntimeInstallInfo>;
  hideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders>;
  unhideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders>;
  deleteRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders>;
  getBeds(): Promise<VitalDBBeds>;
  hideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBBeds>;
  unhideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBBeds>;
  deleteBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBBeds>;
  getRelationships(): Promise<VitalDBRelationships>;
  readLogs(request: RuntimeLogTextRequest): Promise<RuntimeLogTextResponse>;
  exportLogs(request: RuntimeExportLogsRequest): Promise<RuntimeLogExportResult>;
  createPlatformSupportExport(): Promise<PlatformWorkflowOperation>;
  summarizeUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeUpdateBundleSummaryResponse>;
  verifyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<PlatformWorkflowOperation>;
  applyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<PlatformWorkflowOperation>;
  rollbackRelease(): Promise<PlatformWorkflowOperation>;
  listHostBackups(): Promise<RuntimeBackup[]>;
  listRedisBackups(): Promise<RuntimeBackup[]>;
  listRuntimeDataBackups(): Promise<RuntimeBackup[]>;
  rollbackBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  deleteHostBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  deleteUpdateBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  deleteRuntimeDataBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse>;
  restoreRedisBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  restoreRuntimeDataBackup(
    request: RuntimeBackupRequest
  ): Promise<RuntimeCommandResponse>;
  createRedisBackup(): Promise<RuntimeCommandResponse>;
  createRuntimeDataBackup(): Promise<RuntimeCommandResponse>;
  restartRuntimeProvider(): Promise<RuntimeProviderCommandResponse>;
  repairDatastore(): Promise<RuntimeGuestControlServiceOperation>;
};
