import type {
  RuntimeApplySettingsRequest,
  RuntimeBackup,
  RuntimeBackupRequest,
  RuntimeCommandResponse,
  RuntimeControlCapabilities,
  RuntimeControlOverview,
  RuntimeEventHistory,
  RuntimeExportLogsRequest,
  RuntimeLogExportResult,
  RuntimeLogTextRequest,
  RuntimeLogTextResponse,
  RuntimeSettings,
  RuntimeStatus,
  RuntimeTestKitCreateBedsRequest,
  RuntimeTestKitDeleteBedsRequest,
  RuntimeTestKitRecorderDeletionRequest,
  RuntimeTestKitRestartRequest,
  RuntimeTestKitSession,
  RuntimeTestKitSessionSelectionRequest,
  RuntimeTestKitStatus,
  RuntimeTestKitVirtualRecorderStartRequest,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest,
  RuntimeUpdateBundleSummaryResponse,
  VitalDBBeds,
  VitalDBRecorders
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
  getSettings(): Promise<RuntimeSettings>;
  applySettings(request: RuntimeApplySettingsRequest): Promise<RuntimeCommandResponse>;
  startRuntimeServices(): Promise<RuntimeCommandResponse>;
  stopRuntimeServices(): Promise<RuntimeCommandResponse>;
  uninstallRuntime(request: RuntimeUninstallRequest): Promise<RuntimeCommandResponse>;
  getRuntimeEvents(query?: RuntimeEventQuery): Promise<RuntimeEventHistory>;
  getRecorders(): Promise<VitalDBRecorders>;
  getBeds(): Promise<VitalDBBeds>;
  getTestKitStatus(): Promise<RuntimeTestKitStatus>;
  createTestKitBeds(
    request: RuntimeTestKitCreateBedsRequest
  ): Promise<unknown>;
  deleteTestKitBeds(
    request: RuntimeTestKitDeleteBedsRequest
  ): Promise<unknown>;
  resetTestKitBeds(): Promise<unknown>;
  startTestKitVirtualRecorders(
    request: RuntimeTestKitVirtualRecorderStartRequest
  ): Promise<RuntimeTestKitSession>;
  stopTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null>;
  pauseTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null>;
  resumeTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null>;
  restartTestKitVirtualRecorders(
    request: RuntimeTestKitRestartRequest
  ): Promise<RuntimeTestKitSession | null>;
  deleteTestKitVirtualRecorders(
    request: RuntimeTestKitSessionSelectionRequest
  ): Promise<RuntimeTestKitSession | null>;
  resetTestKitVirtualRecorders(): Promise<RuntimeTestKitStatus>;
  deleteTestKitOrphanVRecorder(
    request: RuntimeTestKitRecorderDeletionRequest
  ): Promise<unknown>;
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
  rollbackBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  deleteHostBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  restoreRedisBackup(request: RuntimeBackupRequest): Promise<RuntimeCommandResponse>;
  createRedisBackup(): Promise<RuntimeCommandResponse>;
  repairRuntime(): Promise<RuntimeCommandResponse>;
  repairProxy(proxyPort?: number): Promise<RuntimeCommandResponse>;
  repairDatastore(): Promise<RuntimeCommandResponse>;
  repairVMDisk(): Promise<RuntimeCommandResponse>;
};
