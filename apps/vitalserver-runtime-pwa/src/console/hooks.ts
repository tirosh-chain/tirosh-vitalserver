import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { useRuntimeControlGateway } from "@/console/runtimeControlGatewayContext";
import { consoleQueryKeys } from "@/console/queryKeys";
import {
  backupRequest,
  parseConsoleRequest,
  testKitCreateBedsRequest,
  testKitDeleteBedsRequest,
  testKitSessionSelectionRequest,
  uninstallRequest,
  updateBundleRequest
} from "@/console/requestBuilders";
import type {
  RuntimeApplySettingsRequest,
  RuntimeCommandResponse,
  RuntimeLogSource,
  RuntimeTestKitRestartRequest,
  RuntimeTestKitVirtualRecorderStartRequest,
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeApplySettingsRequestSchema,
  runtimeExportLogsRequestSchema,
  runtimeLogTextRequestSchema,
  runtimeRepairProxyRequestSchema,
  runtimeTestKitRecorderDeletionRequestSchema,
  runtimeTestKitRestartRequestSchema,
  runtimeTestKitVirtualRecorderStartRequestSchema,
} from "@/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas";

export function useRuntimeOverview() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.overview,
    queryFn: () => runtimeControlGateway.getOverview(),
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

export function useCreateRedisBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("redis", () => runtimeControlGateway.createRedisBackup());
}

export function useRestoreRedisBackup() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useBackupMutation("redis", (path) =>
    runtimeControlGateway.restoreRedisBackup(backupRequest(path))
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

export function useStartRuntimeServices() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.startRuntimeServices()
  });
}

export function useStopRuntimeServices() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: () => runtimeControlGateway.stopRuntimeServices()
  });
}

export function useUninstallRuntime() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useMutation({
    mutationFn: (clean: boolean) =>
      runtimeControlGateway.uninstallRuntime(uninstallRequest(clean))
  });
}

export function useTestKitStatus() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useQuery({
    queryKey: consoleQueryKeys.testKitStatus,
    queryFn: () => runtimeControlGateway.getTestKitStatus(),
    refetchInterval: 2_000
  });
}

export function useCreateTestKitBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation((request: {
    count: number | null;
    prefix: string;
    roomNames?: string[];
  }) =>
    runtimeControlGateway.createTestKitBeds(testKitCreateBedsRequest(
      request.count,
      request.prefix,
      request.roomNames ?? []
    ))
  );
}

export function useDeleteTestKitBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation((roomNames: string[]) =>
    runtimeControlGateway.deleteTestKitBeds(testKitDeleteBedsRequest(roomNames))
  );
}

export function useResetTestKitBeds() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation(() => runtimeControlGateway.resetTestKitBeds());
}

export function useStartTestKitVirtualRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation((request: RuntimeTestKitVirtualRecorderStartRequest) =>
    runtimeControlGateway.startTestKitVirtualRecorders(
      parseConsoleRequest(runtimeTestKitVirtualRecorderStartRequestSchema, request)
    )
  );
}

export function useSessionTestKitAction(
  action: "stop" | "pause" | "resume" | "delete"
) {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation((sessionID: string) => {
    const request = testKitSessionSelectionRequest(sessionID);
    switch (action) {
      case "stop":
        return runtimeControlGateway.stopTestKitVirtualRecorders(request);
      case "pause":
        return runtimeControlGateway.pauseTestKitVirtualRecorders(request);
      case "resume":
        return runtimeControlGateway.resumeTestKitVirtualRecorders(request);
      case "delete":
        return runtimeControlGateway.deleteTestKitVirtualRecorders(request);
    }
  });
}

export function useRestartTestKitVirtualRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation((request: RuntimeTestKitRestartRequest) =>
    runtimeControlGateway.restartTestKitVirtualRecorders(
      parseConsoleRequest(runtimeTestKitRestartRequestSchema, request)
    )
  );
}

export function useResetTestKitVirtualRecorders() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation(() =>
    runtimeControlGateway.resetTestKitVirtualRecorders()
  );
}

export function useDeleteTestKitOrphanVRecorder() {
  const runtimeControlGateway = useRuntimeControlGateway();
  return useTestKitMutation((vrcode: string) =>
    runtimeControlGateway.deleteTestKitOrphanVRecorder(
      parseConsoleRequest(runtimeTestKitRecorderDeletionRequestSchema, { vrcode })
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
          queryKey: consoleQueryKeys.hostBackups
        });
      }
      queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.redisBackups
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
        queryKey: consoleQueryKeys.testKitStatus
      });
      queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.recorders
      });
      queryClient.invalidateQueries({
        queryKey: consoleQueryKeys.beds
      });
    }
  });
}
