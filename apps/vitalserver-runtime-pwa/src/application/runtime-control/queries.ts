import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { useRuntimeControlGateway } from "@/application/runtime-control/RuntimeControlGatewayContext";
import { runtimeControlQueryKeys } from "@/application/runtime-control/queryKeys";
import {
  backupRequest,
  parseRuntimeControlRequest,
  testKitDeleteBedsRequest,
  testKitSessionSelectionRequest,
  uninstallRequest,
  updateBundleRequest
} from "@/application/runtime-control/requestBuilders";
import type {
  RuntimeApplySettingsRequest,
  RuntimeCommandResponse,
  RuntimeLogSource,
  RuntimeTestKitCreateBedsRequest,
  RuntimeTestKitRestartRequest,
  RuntimeTestKitVirtualRecorderStartRequest,
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeApplySettingsRequestSchema,
  runtimeExportLogsRequestSchema,
  runtimeLogTextRequestSchema,
  runtimeRepairProxyRequestSchema,
  runtimeTestKitCreateBedsRequestSchema,
  runtimeTestKitRecorderDeletionRequestSchema,
  runtimeTestKitRestartRequestSchema,
  runtimeTestKitVirtualRecorderStartRequestSchema,
} from "@/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas";

export function useRuntimeOverview() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.overview,
    queryFn: () => runtimeControlClient.getOverview(),
    refetchInterval: 2_000
  });
}

export function useRuntimeCapabilities() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.capabilities,
    queryFn: () => runtimeControlClient.getCapabilities(),
    staleTime: 30_000
  });
}

export function useRuntimeEvents(query: {
  limit?: number;
  type?: string;
  since?: string;
}) {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.events(query),
    queryFn: () => runtimeControlClient.getRuntimeEvents(query),
    refetchInterval: 5_000
  });
}

export function useRuntimeSettings() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.settings,
    queryFn: () => runtimeControlClient.getSettings(),
    refetchInterval: 5_000
  });
}

export function useApplyRuntimeSettings() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (request: RuntimeApplySettingsRequest) =>
      runtimeControlClient.applySettings(
        parseRuntimeControlRequest(runtimeApplySettingsRequestSchema, request)
      )
  });
}

export function useVitalDBRecorders() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.recorders,
    queryFn: () => runtimeControlClient.getRecorders(),
    refetchInterval: 5_000
  });
}

export function useVitalDBBeds() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.beds,
    queryFn: () => runtimeControlClient.getBeds(),
    refetchInterval: 5_000
  });
}

export function useHostLogs(request: {
  source: RuntimeLogSource;
  lineLimit: number;
  live: boolean;
}) {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.logs(request),
    queryFn: () =>
      runtimeControlClient.readLogs(parseRuntimeControlRequest(runtimeLogTextRequestSchema, {
        source: request.source,
        helperMessage: "",
        lineLimit: request.lineLimit
      })),
    refetchInterval: request.live ? 2_000 : false
  });
}

export function useExportHostLogs() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (destination: string) =>
      runtimeControlClient.exportLogs(parseRuntimeControlRequest(runtimeExportLogsRequestSchema, {
        destination: {
          kind: "localPath",
          value: destination
        }
      }))
  });
}

export function useSummarizeUpdateBundle() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlClient.summarizeUpdateBundle(updateBundleRequest(path))
  });
}

export function useVerifyUpdateBundle() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlClient.verifyUpdateBundle(updateBundleRequest(path))
  });
}

export function useApplyUpdateBundle() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlClient.applyUpdateBundle(updateBundleRequest(path))
  });
}

export function useHostBackups() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.hostBackups,
    queryFn: () => runtimeControlClient.listHostBackups(),
    refetchInterval: 10_000
  });
}

export function useRedisBackups() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.redisBackups,
    queryFn: () => runtimeControlClient.listRedisBackups(),
    refetchInterval: 10_000
  });
}

export function useRollbackBackup() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useBackupMutation("host", (path) =>
    runtimeControlClient.rollbackBackup(backupRequest(path))
  );
}

export function useDeleteHostBackup() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useBackupMutation("host", (path) =>
    runtimeControlClient.deleteHostBackup(backupRequest(path))
  );
}

export function useCreateRedisBackup() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useBackupMutation("redis", () => runtimeControlClient.createRedisBackup());
}

export function useRestoreRedisBackup() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useBackupMutation("redis", (path) =>
    runtimeControlClient.restoreRedisBackup(backupRequest(path))
  );
}

export function useRepairRuntime() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlClient.repairRuntime()
  });
}

export function useRepairProxy() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (proxyPort?: number) =>
      runtimeControlClient.repairProxy(
        parseRuntimeControlRequest(runtimeRepairProxyRequestSchema, { proxyPort }).proxyPort
      )
  });
}

export function useRepairDatastore() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlClient.repairDatastore()
  });
}

export function useStartRuntimeServices() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlClient.startRuntimeServices()
  });
}

export function useStopRuntimeServices() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlClient.stopRuntimeServices()
  });
}

export function useUninstallRuntime() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (clean: boolean) =>
      runtimeControlClient.uninstallRuntime(uninstallRequest(clean))
  });
}

export function useTestKitStatus() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useQuery({
    queryKey: runtimeControlQueryKeys.testKitStatus,
    queryFn: () => runtimeControlClient.getTestKitStatus(),
    refetchInterval: 2_000
  });
}

export function useCreateTestKitBeds() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation((request: RuntimeTestKitCreateBedsRequest) =>
    runtimeControlClient.createTestKitBeds(
      parseRuntimeControlRequest(runtimeTestKitCreateBedsRequestSchema, request)
    )
  );
}

export function useDeleteTestKitBeds() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation((roomNames: string[]) =>
    runtimeControlClient.deleteTestKitBeds(testKitDeleteBedsRequest(roomNames))
  );
}

export function useResetTestKitBeds() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation(() => runtimeControlClient.resetTestKitBeds());
}

export function useStartTestKitVirtualRecorders() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation((request: RuntimeTestKitVirtualRecorderStartRequest) =>
    runtimeControlClient.startTestKitVirtualRecorders(
      parseRuntimeControlRequest(runtimeTestKitVirtualRecorderStartRequestSchema, request)
    )
  );
}

export function useSessionTestKitAction(
  action: "stop" | "pause" | "resume" | "delete"
) {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation((sessionID: string | null) => {
    const request = testKitSessionSelectionRequest(sessionID);
    switch (action) {
      case "stop":
        return runtimeControlClient.stopTestKitVirtualRecorders(request);
      case "pause":
        return runtimeControlClient.pauseTestKitVirtualRecorders(request);
      case "resume":
        return runtimeControlClient.resumeTestKitVirtualRecorders(request);
      case "delete":
        return runtimeControlClient.deleteTestKitVirtualRecorders(request);
    }
  });
}

export function useRestartTestKitVirtualRecorders() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation((request: RuntimeTestKitRestartRequest) =>
    runtimeControlClient.restartTestKitVirtualRecorders(
      parseRuntimeControlRequest(runtimeTestKitRestartRequestSchema, request)
    )
  );
}

export function useResetTestKitVirtualRecorders() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation(() =>
    runtimeControlClient.resetTestKitVirtualRecorders()
  );
}

export function useDeleteTestKitOrphanVRecorder() {
  const runtimeControlClient = useRuntimeControlGateway();
  return useTestKitMutation((vrcode: string) =>
    runtimeControlClient.deleteTestKitOrphanVRecorder(
      parseRuntimeControlRequest(runtimeTestKitRecorderDeletionRequestSchema, { vrcode })
    )
  );
}

function useBackupMutation(
  scope: "host" | "redis",
  mutationFn: (path: string) => Promise<RuntimeCommandResponse>
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: () => {
      if (scope === "host") {
        queryClient.invalidateQueries({
          queryKey: runtimeControlQueryKeys.hostBackups
        });
      }
      queryClient.invalidateQueries({
        queryKey: runtimeControlQueryKeys.redisBackups
      });
    }
  });
}

function useTestKitMutation<TVariables, TResult>(
  mutationFn: (variables: TVariables) => Promise<TResult>
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: runtimeControlQueryKeys.testKitStatus
      });
      queryClient.invalidateQueries({
        queryKey: runtimeControlQueryKeys.recorders
      });
      queryClient.invalidateQueries({
        queryKey: runtimeControlQueryKeys.beds
      });
    }
  });
}
