import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";

import { useRuntimeControlGateway } from "@/console/runtimeControlGatewayContext";
import type { RuntimeEventQuery } from "@/console/runtimeControlGateway";
import { consoleQueryKeys } from "@/console/queryKeys";
import {
  backupRequest,
  parseConsoleRequest,
  uninstallRequest,
  updateBundleRequest
} from "@/console/requestBuilders";
import type {
  RuntimeApplyProductSettingsRequest,
  RuntimeApplyPlatformSettingsRequest,
  RuntimeAdminPasswordRequest,
  RuntimeRedisRelaySettingsApplyRequest,
  RuntimeCommandResponse,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabSessionCreateRequest,
  RuntimeLabVitalFileUploadRequest,
  RuntimeLabVitalFileReplayRequest,
  RuntimeLogSource,
  RuntimeVitalRecorderActivityWindowQuery,
  VitalDBBedVisibilityRequest,
  VitalDBRecorderVisibilityRequest,
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeExportLogsRequestSchema,
  runtimeLabBedCreateRequestSchema,
  runtimeLabBedDeleteRequestSchema,
  runtimeLabRecorderCreateRequestSchema,
  runtimeLabRecorderDeleteRequestSchema,
  runtimeLabSessionIdSchema,
  runtimeLabSessionCreateRequestSchema,
  runtimeLabVitalFileReplayRequestSchema,
  runtimeLogTextRequestSchema,
  vitalDBBedVisibilityRequestSchema,
  vitalDBRecorderVisibilityRequestSchema,
} from "@/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas";

export function usePlatformState() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.platformState,
    queryFn: () => runtimeControlGateway.getPlatformState(),
    refetchInterval: 2_000
  });
}

export function useRedisRelayStatus() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.redisRelayStatus,
    queryFn: () => runtimeControlGateway.getRedisRelayStatus(),
    refetchInterval: 2_000
  });
}

export function useRuntimeRedisRelaySettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.redisRelaySettings,
    queryFn: () => runtimeControlGateway.getRuntimeRedisRelaySettings()
  });
}

export function useApplyRuntimeRedisRelaySettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: RuntimeRedisRelaySettingsApplyRequest) =>
      runtimeControlGateway.applyRuntimeRedisRelaySettings(request),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.redisRelaySettings
      });
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.runtimeStack });
    }
  });
}

export function useLatestVitalDBObservation() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.vitalDBObservation,
    queryFn: () => runtimeControlGateway.getLatestVitalDBObservation(),
    refetchInterval: 5_000
  });
}

export function usePlatformOperationState() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.operationState,
    queryFn: () => runtimeControlGateway.getOperationState(),
    refetchInterval: 2_000
  });
}

export function usePlatformWorkflow() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.platformWorkflow,
    queryFn: () => runtimeControlGateway.getPlatformWorkflow(),
    refetchInterval: 2_000
  });
}

export function useCreatePlatformSupportExport() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => runtimeControlGateway.createPlatformSupportExport(),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.platformWorkflow });
    }
  });
}

export function useRuntimeStack() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.runtimeStack,
    queryFn: () => runtimeControlGateway.getRuntimeStack(),
    refetchInterval: 2_000
  });
}

export function useRuntimeServiceResources(services: string[]) {
  const runtimeControlGateway = useRuntimeControlGateway();
  const uniqueServices = Array.from(new Set(services)).sort();
  const results = useQueries({
    queries: uniqueServices.map((service) => ({
      queryKey: consoleQueryKeys.runtimeServiceResource(service),
      queryFn: () => runtimeControlGateway.getGuestServiceResource(service),
      refetchInterval: 2_000
    }))
  });
  return uniqueServices.map((service, index) => ({
    service,
    resource: results[index]?.data,
    error: results[index]?.error ?? null
  }));
}

export function useControlCapabilities() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.capabilities,
    queryFn: () => runtimeControlGateway.getCapabilities(),
    staleTime: 30_000
  });
}

export function useRuntimeEvents(query: RuntimeEventQuery) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.events(query),
    queryFn: () => runtimeControlGateway.getRuntimeEvents(query),
    refetchInterval: 5_000
  });
}

export function useRuntimeProductSettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.runtimeProductSettings,
    queryFn: () => runtimeControlGateway.getRuntimeProductSettings(),
    refetchInterval: 5_000
  });
}

export function useRuntimePlatformSettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.runtimePlatformSettings,
    queryFn: () => runtimeControlGateway.getRuntimePlatformSettings(),
    refetchInterval: 5_000
  });
}

export function useApplyRuntimePlatformSettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: RuntimeApplyPlatformSettingsRequest) =>
      runtimeControlGateway.applyRuntimePlatformSettings(request),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.runtimePlatformSettings
      });
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.platformState });
    }
  });
}

export function useApplyRuntimeProductSettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: RuntimeApplyProductSettingsRequest) =>
      runtimeControlGateway.applyRuntimeProductSettings(request),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.runtimeProductSettings
      });
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.runtimeStack });
    }
  });
}

export function useApplyRuntimeAdminPassword() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: RuntimeAdminPasswordRequest) =>
      runtimeControlGateway.applyRuntimeAdminPassword(request),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.runtimeStack });
    }
  });
}

export function useLabScenarios() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.labScenarios,
    queryFn: () => runtimeControlGateway.getLabScenarios(),
    refetchInterval: 5_000
  });
}

export function useLabBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.labBeds,
    queryFn: () => runtimeControlGateway.getLabBeds(),
    refetchInterval: 2_000
  });
}

export function useLabRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.labRecorders,
    queryFn: () => runtimeControlGateway.getLabRecorders(),
    refetchInterval: 2_000
  });
}

export function useLabSessions(enabled = true) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.labSessions,
    queryFn: () => runtimeControlGateway.getLabSessions(),
    enabled,
    refetchInterval: 2_000
  });
}

export function useLabVitalFiles() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.labVitalFiles,
    queryFn: () => runtimeControlGateway.getLabVitalFiles(),
    refetchInterval: 10_000
  });
}

export function useCreateLabBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabBedCreateRequest) =>
    runtimeControlGateway.createLabBeds(
      parseConsoleRequest(runtimeLabBedCreateRequestSchema, request)
    )
  );
}

export function useDeleteLabBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabBedDeleteRequest) =>
    runtimeControlGateway.deleteLabBeds(
      parseConsoleRequest(runtimeLabBedDeleteRequestSchema, request)
    )
  );
}

export function useResetLabBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation(() => runtimeControlGateway.resetLabBeds());
}

export function useCreateLabRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabRecorderCreateRequest) =>
    runtimeControlGateway.createLabRecorders(
      parseConsoleRequest(runtimeLabRecorderCreateRequestSchema, request)
    )
  );
}

export function useDeleteLabRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabRecorderDeleteRequest) =>
    runtimeControlGateway.deleteLabRecorders(
      parseConsoleRequest(runtimeLabRecorderDeleteRequestSchema, request)
    )
  );
}

export function useResetLabRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation(() => runtimeControlGateway.resetLabRecorders());
}

export function useLabSession(sessionId: string | null) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.labSession(sessionId ?? ""),
    queryFn: () => runtimeControlGateway.getLabSession(sessionId ?? ""),
    enabled: sessionId !== null && sessionId.trim().length > 0,
    refetchInterval: 2_000
  });
}

export function useCreateLabSession() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabSessionCreateRequest) =>
    runtimeControlGateway.createLabSession(
      parseConsoleRequest(runtimeLabSessionCreateRequestSchema, request)
    )
  );
}

export function useStartLabSession() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((sessionId: string) =>
    runtimeControlGateway.startLabSession(parseSessionId(sessionId))
  );
}

export function useStopLabSession() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((sessionId: string) =>
    runtimeControlGateway.stopLabSession(parseSessionId(sessionId))
  );
}

export function useFinishLabSession() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((sessionId: string) =>
    runtimeControlGateway.finishLabSession(parseSessionId(sessionId))
  );
}

export type RuntimeLabRecorderCommand = {
  sessionId: string;
  recorderId: string;
};

export function useStartLabRecorder() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation(({ sessionId, recorderId }: RuntimeLabRecorderCommand) =>
    runtimeControlGateway.startLabRecorder(
      parseSessionId(sessionId),
      parseSessionId(recorderId)
    )
  );
}

export function useStopLabRecorder() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation(({ sessionId, recorderId }: RuntimeLabRecorderCommand) =>
    runtimeControlGateway.stopLabRecorder(
      parseSessionId(sessionId),
      parseSessionId(recorderId)
    )
  );
}

export function useReplayLabVitalFile() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabVitalFileReplayRequest) =>
    runtimeControlGateway.replayLabVitalFile(
      parseConsoleRequest(runtimeLabVitalFileReplayRequestSchema, request)
    )
  );
}

export function useUploadLabVitalFiles() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabVitalFileUploadRequest) => {
    validateVitalFileUpload(request.files);
    return runtimeControlGateway.uploadLabVitalFiles(request);
  });
}

function validateVitalFileUpload(files: File[]): void {
  if (files.length === 0) {
    throw new Error("Select at least one .vital file.");
  }
}

export function useVitalDBRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.recorders,
    queryFn: () => runtimeControlGateway.getRecorders(),
    refetchInterval: 5_000
  });
}

export function useVitalDBRecorderActivity(
  query: RuntimeVitalRecorderActivityWindowQuery
) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.recorderActivity(query),
    queryFn: () => runtimeControlGateway.getRecorderActivity(query),
    refetchInterval: 5_000
  });
}

export function useVitalDBRecorderVitalFiles(vrcode: string | null) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.recorderVitalFiles(vrcode ?? ""),
    queryFn: () => runtimeControlGateway.getRecorderVitalFiles(vrcode ?? ""),
    enabled: vrcode !== null
  });
}

export function useRecorderObservabilityDetail(vrcode: string | null) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.recorderObservability(vrcode ?? ""),
    queryFn: () => runtimeControlGateway.getRecorderObservability(vrcode ?? ""),
    enabled: vrcode !== null,
    refetchInterval: 5_000
  });
}

export function useReleaseInfo() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.releaseInfo,
    queryFn: () => runtimeControlGateway.getReleaseInfo()
  });
}

export function useInstallInfo() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.installInfo,
    queryFn: () => runtimeControlGateway.getInstallInfo()
  });
}

export function useVitalDBBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.beds,
    queryFn: () => runtimeControlGateway.getBeds(),
    refetchInterval: 5_000
  });
}

export function useHideVitalDBRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useVitalDBMutation((request: VitalDBRecorderVisibilityRequest) =>
    runtimeControlGateway.hideRecorders(
      parseConsoleRequest(vitalDBRecorderVisibilityRequestSchema, request)
    )
  );
}

export function useUnhideVitalDBRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useVitalDBMutation((request: VitalDBRecorderVisibilityRequest) =>
    runtimeControlGateway.unhideRecorders(
      parseConsoleRequest(vitalDBRecorderVisibilityRequestSchema, request)
    )
  );
}

export function useDeleteVitalDBRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useVitalDBMutation((request: VitalDBRecorderVisibilityRequest) =>
    runtimeControlGateway.deleteRecorders(
      parseConsoleRequest(vitalDBRecorderVisibilityRequestSchema, request)
    )
  );
}

export function useHideVitalDBBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useVitalDBMutation((request: VitalDBBedVisibilityRequest) =>
    runtimeControlGateway.hideBeds(
      parseConsoleRequest(vitalDBBedVisibilityRequestSchema, request)
    )
  );
}

export function useUnhideVitalDBBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useVitalDBMutation((request: VitalDBBedVisibilityRequest) =>
    runtimeControlGateway.unhideBeds(
      parseConsoleRequest(vitalDBBedVisibilityRequestSchema, request)
    )
  );
}

export function useDeleteVitalDBBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useVitalDBMutation((request: VitalDBBedVisibilityRequest) =>
    runtimeControlGateway.deleteBeds(
      parseConsoleRequest(vitalDBBedVisibilityRequestSchema, request)
    )
  );
}

export function useVitalDBRelationships() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.relationships,
    queryFn: () => runtimeControlGateway.getRelationships(),
    refetchInterval: 5_000
  });
}

function useVitalDBMutation<TRequest>(
  mutationFn: (request: TRequest) => Promise<unknown>
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.recorders });
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.beds });
      void queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.relationships
      });
    }
  });
}

export function useHostLogs(request: {
  source: RuntimeLogSource;
  lineLimit: number;
  live: boolean;
  enabled: boolean;
}) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.logs(request),
    queryFn: () =>
      runtimeControlGateway.readLogs(parseConsoleRequest(runtimeLogTextRequestSchema, {
        source: request.source,
        helperMessage: null,
        lineLimit: request.lineLimit
      })),
    enabled: request.enabled,
    refetchInterval: request.enabled && request.live ? 2_000 : false
  });
}

export function useExportHostLogs() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (destination: string) =>
      runtimeControlGateway.exportLogs(parseConsoleRequest(runtimeExportLogsRequestSchema, {
        destination: {
          kind: "localPath",
          value: destination
        }
      }))
  });
}

export function useSummarizeUpdateBundle() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlGateway.summarizeUpdateBundle(updateBundleRequest(path))
  });
}

export function useVerifyUpdateBundle() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlGateway.verifyUpdateBundle(updateBundleRequest(path)),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.platformWorkflow });
    }
  });
}

export function useApplyUpdateBundle() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlGateway.applyUpdateBundle(updateBundleRequest(path)),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.platformWorkflow });
    }
  });
}

export function useRollbackRelease() {
  const runtimeControlGateway = useRuntimeControlGateway();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => runtimeControlGateway.rollbackRelease(),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: consoleQueryKeys.platformWorkflow });
    }
  });
}

export function useHostBackups(enabled: boolean) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.hostBackups,
    queryFn: () => runtimeControlGateway.listHostBackups(),
    enabled,
    refetchInterval: 10_000
  });
}

export function useRedisBackups(enabled: boolean) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.redisBackups,
    queryFn: () => runtimeControlGateway.listRedisBackups(),
    enabled,
    refetchInterval: 10_000
  });
}

export function useRuntimeDataBackups(enabled: boolean) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.runtimeDataBackups,
    queryFn: () => runtimeControlGateway.listRuntimeDataBackups(),
    enabled,
    refetchInterval: 10_000
  });
}

export function useRollbackBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("host", (path) =>
    runtimeControlGateway.rollbackBackup(backupRequest(path))
  );
}

export function useDeleteHostBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("host", (path) =>
    runtimeControlGateway.deleteHostBackup(backupRequest(path))
  );
}

export function useDeleteUpdateBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("host", (path) =>
    runtimeControlGateway.deleteUpdateBackup(backupRequest(path))
  );
}

export function useDeleteRuntimeDataBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("runtime-data", (path) =>
    runtimeControlGateway.deleteRuntimeDataBackup(backupRequest(path))
  );
}

export function useCreateRedisBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("redis", () => runtimeControlGateway.createRedisBackup());
}

export function useCreateRuntimeDataBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("runtime-data", () =>
    runtimeControlGateway.createRuntimeDataBackup()
  );
}

export function useRestoreRedisBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("redis", (path) =>
    runtimeControlGateway.restoreRedisBackup(backupRequest(path))
  );
}

export function useRestoreRuntimeDataBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("runtime-data", (path) =>
    runtimeControlGateway.restoreRuntimeDataBackup(backupRequest(path))
  );
}

export function useRestartRuntimeProvider() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.restartRuntimeProvider()
  });
}

export function useRepairDatastore() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.repairDatastore()
  });
}

export function useStartGuestService() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (service: string) =>
      runtimeControlGateway.startGuestService({ service })
  });
}

export function useStopGuestService() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (service: string) =>
      runtimeControlGateway.stopGuestService({ service })
  });
}

export function useRestartGuestService() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (service: string) =>
      runtimeControlGateway.restartGuestService({ service })
  });
}

export function useUninstallRuntime() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (clean: boolean) =>
      runtimeControlGateway.uninstallRuntime(uninstallRequest(clean))
  });
}

function useLabMutation<TVariables, TResult>(
  mutationFn: (variables: TVariables) => Promise<TResult>
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: (response) => {
      queryClient.invalidateQueries({
        queryKey: ["lab"]
      });
      queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.recorders
      });
      queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.beds
      });
      const sessionId = (response as { session?: { sessionId?: string } | null })
        .session?.sessionId ??
        (response as { recorder?: { sessionId?: string } | null }).recorder?.sessionId;
      if (sessionId) {
        queryClient.invalidateQueries({
          queryKey: consoleQueryKeys.labSession(sessionId)
        });
      }
    }
  });
}

function parseSessionId(sessionId: string): string {
  return parseConsoleRequest(runtimeLabSessionIdSchema, sessionId);
}

function useBackupMutation(
  scope: "host" | "redis" | "runtime-data",
  mutationFn: (path: string) => Promise<RuntimeCommandResponse>
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: () => {
      if (scope === "host") {
        queryClient.invalidateQueries({
          queryKey: consoleQueryKeys.hostBackups
        });
      }
      queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.redisBackups
      });
      if (scope === "runtime-data") {
        queryClient.invalidateQueries({
          queryKey: consoleQueryKeys.runtimeDataBackups
        });
      }
    }
  });
}
