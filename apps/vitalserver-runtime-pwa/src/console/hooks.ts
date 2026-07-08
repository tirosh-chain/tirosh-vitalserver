import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { useRuntimeControlGateway } from "@/console/runtimeControlGatewayContext";
import { consoleQueryKeys } from "@/console/queryKeys";
import {
  backupRequest,
  parseConsoleRequest,
  uninstallRequest,
  updateBundleRequest
} from "@/console/requestBuilders";
import type {
  RuntimeApplySettingsRequest,
  RuntimeCommandResponse,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabSessionCreateRequest,
  RuntimeLabVitalFileUploadRequest,
  RuntimeLabVitalFileReplayRequest,
  RuntimeLogSource,
  VitalDBBedVisibilityRequest,
  VitalDBRecorderVisibilityRequest,
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeApplySettingsRequestSchema,
  runtimeExportLogsRequestSchema,
  runtimeLabBedCreateRequestSchema,
  runtimeLabBedDeleteRequestSchema,
  runtimeLabRecorderCreateRequestSchema,
  runtimeLabRecorderDeleteRequestSchema,
  runtimeLabSessionIdSchema,
  runtimeLabSessionCreateRequestSchema,
  runtimeLabVitalFileUploadRequestSchema,
  runtimeLabVitalFileReplayRequestSchema,
  runtimeLogTextRequestSchema,
  runtimeRepairProxyRequestSchema,
  vitalDBBedVisibilityRequestSchema,
  vitalDBRecorderVisibilityRequestSchema,
} from "@/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas";

export function useRuntimeOverview() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.overview,
    queryFn: () => runtimeControlGateway.getOverview(),
    refetchInterval: 2_000
  });
}

export function useRuntimeOperationState() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.operationState,
    queryFn: () => runtimeControlGateway.getOperationState(),
    refetchInterval: 2_000
  });
}

export function useGuestStackStatus() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.guestStackStatus,
    queryFn: () => runtimeControlGateway.getGuestStackStatus(),
    refetchInterval: 2_000
  });
}

export function useRuntimeCapabilities() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.capabilities,
    queryFn: () => runtimeControlGateway.getCapabilities(),
    staleTime: 30_000
  });
}

export function useRuntimeEvents(query: {
  limit?: number;
  type?: string;
  since?: string;
}) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.events(query),
    queryFn: () => runtimeControlGateway.getRuntimeEvents(query),
    refetchInterval: 5_000
  });
}

export function useRuntimeSettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.settings,
    queryFn: () => runtimeControlGateway.getSettings(),
    refetchInterval: 5_000
  });
}

export function useApplyRuntimeSettings() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (request: RuntimeApplySettingsRequest) =>
      runtimeControlGateway.applySettings(
        parseConsoleRequest(runtimeApplySettingsRequestSchema, request)
      )
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

export function useReplayLabVitalFile() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabVitalFileReplayRequest) =>
    runtimeControlGateway.replayLabVitalFile(
      parseConsoleRequest(runtimeLabVitalFileReplayRequestSchema, request)
    )
  );
}

export function useUploadLabVitalFile() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useLabMutation((request: RuntimeLabVitalFileUploadRequest) =>
    runtimeControlGateway.uploadLabVitalFile(
      parseConsoleRequest(runtimeLabVitalFileUploadRequestSchema, request)
    )
  );
}

export function useVitalDBRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.recorders,
    queryFn: () => runtimeControlGateway.getRecorders(),
    refetchInterval: 5_000
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
    refetchInterval: request.live ? 2_000 : false
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
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlGateway.verifyUpdateBundle(updateBundleRequest(path))
  });
}

export function useApplyUpdateBundle() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlGateway.applyUpdateBundle(updateBundleRequest(path))
  });
}

export function useHostBackups() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.hostBackups,
    queryFn: () => runtimeControlGateway.listHostBackups(),
    refetchInterval: 10_000
  });
}

export function useRedisBackups() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.redisBackups,
    queryFn: () => runtimeControlGateway.listRedisBackups(),
    refetchInterval: 10_000
  });
}

export function useRuntimeDataBackups() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.runtimeDataBackups,
    queryFn: () => runtimeControlGateway.listRuntimeDataBackups(),
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

export function useRepairRuntime() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.repairRuntime()
  });
}

export function useRepairProxy() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (proxyPort: number) =>
      runtimeControlGateway.repairProxy(
        parseConsoleRequest(runtimeRepairProxyRequestSchema, { proxyPort }).proxyPort
      )
  });
}

export function useRepairDatastore() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.repairDatastore()
  });
}

export function useRepairVMDisk() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.repairVMDisk()
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
        .session?.sessionId;
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
