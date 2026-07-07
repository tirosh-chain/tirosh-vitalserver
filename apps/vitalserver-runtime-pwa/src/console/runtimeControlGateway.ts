import type {
  RuntimeApplySettingsRequest,
  RuntimeBackup,
  RuntimeBackupRequest,
  RuntimeCommandResponse,
  RuntimeControlCapabilities,
  RuntimeControlOverview,
  RuntimeEventHistory,
  RuntimeExportLogsRequest,
  RuntimeGuestControlStackStatus,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabBedList,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabRecorderList,
  RuntimeLabScenarioList,
  RuntimeLabSessionCreateRequest,
  RuntimeLabSessionResponse,
  RuntimeLabVitalFileReplayRequest,
  RuntimeGuestControlServiceOperation,
  RuntimeGuestServiceControlRequest,
  RuntimeLogExportResult,
  RuntimeLogTextRequest,
  RuntimeLogTextResponse,
  RuntimeOperationState,
  RuntimeSettings,
  RuntimeStatus,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest,
  RuntimeUpdateBundleSummaryResponse,
  VitalDBBedVisibilityRequest,
  VitalDBBeds,
  VitalDBRecorderVisibilityRequest,
  VitalDBRecorders,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RuntimeEventQuery = {
  limit?: number;
  type?: string;
  since?: string;
  cursor?: string;
};

export type RuntimeControlGateway = {
  getCapabilities(): Promise<RuntimeControlCapabilities>;
  getOverview(): Promise<RuntimeControlOverview>;
  getStatus(): Promise<RuntimeStatus>;
  getOperationState(): Promise<RuntimeOperationState>;
  getSettings(): Promise<RuntimeSettings>;
  applySettings(request: RuntimeApplySettingsRequest): Promise<RuntimeCommandResponse>;
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
  createLabSession(
    request: RuntimeLabSessionCreateRequest
  ): Promise<RuntimeLabSessionResponse>;
  getLabSession(sessionId: string): Promise<RuntimeLabSessionResponse>;
  startLabSession(sessionId: string): Promise<RuntimeLabSessionResponse>;
  stopLabSession(sessionId: string): Promise<RuntimeLabSessionResponse>;
  replayLabVitalFile(
    request: RuntimeLabVitalFileReplayRequest
  ): Promise<RuntimeLabSessionResponse>;
  getGuestStackStatus(): Promise<RuntimeGuestControlStackStatus>;
  startGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  stopGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  restartGuestService(
    request: RuntimeGuestServiceControlRequest
  ): Promise<RuntimeGuestControlServiceOperation>;
  uninstallRuntime(request: RuntimeUninstallRequest): Promise<RuntimeCommandResponse>;
  getRuntimeEvents(query?: RuntimeEventQuery): Promise<RuntimeEventHistory>;
  getRecorders(): Promise<VitalDBRecorders>;
  hideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders>;
  unhideRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders>;
  deleteRecorders(request: VitalDBRecorderVisibilityRequest): Promise<VitalDBRecorders>;
  getBeds(): Promise<VitalDBBeds>;
  hideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBRecorders>;
  unhideBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBRecorders>;
  deleteBeds(request: VitalDBBedVisibilityRequest): Promise<VitalDBRecorders>;
  getRelationships(): Promise<VitalDBRelationships>;
  readLogs(request: RuntimeLogTextRequest): Promise<RuntimeLogTextResponse>;
  exportLogs(request: RuntimeExportLogsRequest): Promise<RuntimeLogExportResult>;
  summarizeUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeUpdateBundleSummaryResponse>;
  verifyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeCommandResponse>;
  applyUpdateBundle(
    request: RuntimeUpdateBundleRequest
  ): Promise<RuntimeCommandResponse>;
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
  repairRuntime(): Promise<RuntimeCommandResponse>;
  repairProxy(proxyPort: number): Promise<RuntimeCommandResponse>;
  repairDatastore(): Promise<RuntimeCommandResponse>;
  repairVMDisk(): Promise<RuntimeCommandResponse>;
};
