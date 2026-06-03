import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { useConsoleGateway } from "@/console/gatewayContext";
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
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.overview,
    queryFn: () => consoleGateway.getOverview(),
    refetchInterval: 2_000
  });
}

export function useRuntimeCapabilities() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.capabilities,
    queryFn: () => consoleGateway.getCapabilities(),
    staleTime: 30_000
  });
}

export function useRuntimeEvents(query: {
  limit?: number;
  type?: string;
  since?: string;
}) {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.events(query),
    queryFn: () => consoleGateway.getRuntimeEvents(query),
    refetchInterval: 5_000
  });
}

export function useRuntimeSettings() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.settings,
    queryFn: () => consoleGateway.getSettings(),
    refetchInterval: 5_000
  });
}

export function useApplyRuntimeSettings() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (request: RuntimeApplySettingsRequest) =>
      consoleGateway.applySettings(
        parseConsoleRequest(runtimeApplySettingsRequestSchema, request)
      )
  });
}

export function useVitalDBRecorders() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.recorders,
    queryFn: () => consoleGateway.getRecorders(),
    refetchInterval: 5_000
  });
}

export function useVitalDBBeds() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.beds,
    queryFn: () => consoleGateway.getBeds(),
    refetchInterval: 5_000
  });
}

export function useHostLogs(request: {
  source: RuntimeLogSource;
  lineLimit: number;
  live: boolean;
}) {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.logs(request),
    queryFn: () =>
      consoleGateway.readLogs(parseConsoleRequest(runtimeLogTextRequestSchema, {
        source: request.source,
        helperMessage: null,
        lineLimit: request.lineLimit
      })),
    refetchInterval: request.live ? 2_000 : false
  });
}

export function useExportHostLogs() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (destination: string) =>
      consoleGateway.exportLogs(parseConsoleRequest(runtimeExportLogsRequestSchema, {
        destination: {
          kind: "localPath",
          value: destination
        }
      }))
  });
}

export function useSummarizeUpdateBundle() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (path: string) =>
      consoleGateway.summarizeUpdateBundle(updateBundleRequest(path))
  });
}

export function useVerifyUpdateBundle() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (path: string) =>
      consoleGateway.verifyUpdateBundle(updateBundleRequest(path))
  });
}

export function useApplyUpdateBundle() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (path: string) =>
      consoleGateway.applyUpdateBundle(updateBundleRequest(path))
  });
}

export function useHostBackups() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.hostBackups,
    queryFn: () => consoleGateway.listHostBackups(),
    refetchInterval: 10_000
  });
}

export function useRedisBackups() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.redisBackups,
    queryFn: () => consoleGateway.listRedisBackups(),
    refetchInterval: 10_000
  });
}

export function useRollbackBackup() {
  const consoleGateway = useConsoleGateway();
  return useBackupMutation("host", (path) =>
    consoleGateway.rollbackBackup(backupRequest(path))
  );
}

export function useDeleteHostBackup() {
  const consoleGateway = useConsoleGateway();
  return useBackupMutation("host", (path) =>
    consoleGateway.deleteHostBackup(backupRequest(path))
  );
}

export function useCreateRedisBackup() {
  const consoleGateway = useConsoleGateway();
  return useBackupMutation("redis", () => consoleGateway.createRedisBackup());
}

export function useRestoreRedisBackup() {
  const consoleGateway = useConsoleGateway();
  return useBackupMutation("redis", (path) =>
    consoleGateway.restoreRedisBackup(backupRequest(path))
  );
}

export function useRepairRuntime() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: () => consoleGateway.repairRuntime()
  });
}

export function useRepairProxy() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (proxyPort: number) =>
      consoleGateway.repairProxy(
        parseConsoleRequest(runtimeRepairProxyRequestSchema, { proxyPort }).proxyPort
      )
  });
}

export function useRepairDatastore() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: () => consoleGateway.repairDatastore()
  });
}

export function useRepairVMDisk() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: () => consoleGateway.repairVMDisk()
  });
}

export function useStartRuntimeServices() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: () => consoleGateway.startRuntimeServices()
  });
}

export function useStopRuntimeServices() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: () => consoleGateway.stopRuntimeServices()
  });
}

export function useUninstallRuntime() {
  const consoleGateway = useConsoleGateway();
  return useMutation({
    mutationFn: (clean: boolean) =>
      consoleGateway.uninstallRuntime(uninstallRequest(clean))
  });
}

export function useTestKitStatus() {
  const consoleGateway = useConsoleGateway();
  return useQuery({
    queryKey: consoleQueryKeys.testKitStatus,
    queryFn: () => consoleGateway.getTestKitStatus(),
    refetchInterval: 2_000
  });
}

export function useCreateTestKitBeds() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation((request: {
    count: number | null;
    prefix: string;
    roomNames?: string[];
  }) =>
    consoleGateway.createTestKitBeds(testKitCreateBedsRequest(
      request.count,
      request.prefix,
      request.roomNames ?? []
    ))
  );
}

export function useDeleteTestKitBeds() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation((roomNames: string[]) =>
    consoleGateway.deleteTestKitBeds(testKitDeleteBedsRequest(roomNames))
  );
}

export function useResetTestKitBeds() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation(() => consoleGateway.resetTestKitBeds());
}

export function useStartTestKitVirtualRecorders() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation((request: RuntimeTestKitVirtualRecorderStartRequest) =>
    consoleGateway.startTestKitVirtualRecorders(
      parseConsoleRequest(runtimeTestKitVirtualRecorderStartRequestSchema, request)
    )
  );
}

export function useSessionTestKitAction(
  action: "stop" | "pause" | "resume" | "delete"
) {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation((sessionID: string) => {
    const request = testKitSessionSelectionRequest(sessionID);
    switch (action) {
      case "stop":
        return consoleGateway.stopTestKitVirtualRecorders(request);
      case "pause":
        return consoleGateway.pauseTestKitVirtualRecorders(request);
      case "resume":
        return consoleGateway.resumeTestKitVirtualRecorders(request);
      case "delete":
        return consoleGateway.deleteTestKitVirtualRecorders(request);
    }
  });
}

export function useRestartTestKitVirtualRecorders() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation((request: RuntimeTestKitRestartRequest) =>
    consoleGateway.restartTestKitVirtualRecorders(
      parseConsoleRequest(runtimeTestKitRestartRequestSchema, request)
    )
  );
}

export function useResetTestKitVirtualRecorders() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation(() =>
    consoleGateway.resetTestKitVirtualRecorders()
  );
}

export function useDeleteTestKitOrphanVRecorder() {
  const consoleGateway = useConsoleGateway();
  return useTestKitMutation((vrcode: string) =>
    consoleGateway.deleteTestKitOrphanVRecorder(
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
