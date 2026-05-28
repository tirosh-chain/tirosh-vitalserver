import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { runtimeControlClient } from "./runtimeControlClient";
import type { RuntimeLogSource } from "./runtimeControlTypes";

export const runtimeControlQueryKeys = {
  overview: ["runtime-control", "overview"] as const,
  capabilities: ["runtime-control", "capabilities"] as const,
  settings: ["runtime-control", "settings"] as const,
  events: (query: { limit?: number; type?: string; since?: string }) =>
    ["runtime-control", "events", query] as const,
  logs: (request: { source: RuntimeLogSource; lineLimit: number }) =>
    ["runtime-control", "logs", request] as const,
  hostBackups: ["host", "backups"] as const,
  redisBackups: ["host", "backups", "redis"] as const,
  testKitStatus: ["dev", "testkit", "status"] as const,
  recorders: ["vitaldb", "recorders"] as const,
  beds: ["vitaldb", "beds"] as const
};

export function useRuntimeOverview() {
  return useQuery({
    queryKey: runtimeControlQueryKeys.overview,
    queryFn: () => runtimeControlClient.getOverview(),
    refetchInterval: 2_000
  });
}

export function useRuntimeEvents(query: {
  limit?: number;
  type?: string;
  since?: string;
}) {
  return useQuery({
    queryKey: runtimeControlQueryKeys.events(query),
    queryFn: () => runtimeControlClient.getRuntimeEvents(query),
    refetchInterval: 5_000
  });
}

export function useRuntimeSettings() {
  return useQuery({
    queryKey: runtimeControlQueryKeys.settings,
    queryFn: () => runtimeControlClient.getSettings(),
    refetchInterval: 5_000
  });
}

export function useApplyRuntimeSettings() {
  return useMutation({
    mutationFn: runtimeControlClient.applySettings.bind(runtimeControlClient)
  });
}

export function useVitalDBRecorders() {
  return useQuery({
    queryKey: runtimeControlQueryKeys.recorders,
    queryFn: () => runtimeControlClient.getRecorders(),
    refetchInterval: 5_000
  });
}

export function useVitalDBBeds() {
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
  return useQuery({
    queryKey: runtimeControlQueryKeys.logs(request),
    queryFn: () =>
      runtimeControlClient.readLogs({
        source: request.source,
        helperMessage: "",
        lineLimit: request.lineLimit
      }),
    refetchInterval: request.live ? 2_000 : false
  });
}

export function useExportHostLogs() {
  return useMutation({
    mutationFn: (destination: string) =>
      runtimeControlClient.exportLogs({
        destination: {
          kind: "localPath",
          value: destination
        }
      })
  });
}

export function useSummarizeUpdateBundle() {
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlClient.summarizeUpdateBundle({
        bundle: {
          kind: "localPath",
          value: path
        }
      })
  });
}

export function useVerifyUpdateBundle() {
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlClient.verifyUpdateBundle({
        bundle: {
          kind: "localPath",
          value: path
        }
      })
  });
}

export function useApplyUpdateBundle() {
  return useMutation({
    mutationFn: (path: string) =>
      runtimeControlClient.applyUpdateBundle({
        bundle: {
          kind: "localPath",
          value: path
        }
      })
  });
}

export function useHostBackups() {
  return useQuery({
    queryKey: runtimeControlQueryKeys.hostBackups,
    queryFn: () => runtimeControlClient.listHostBackups(),
    refetchInterval: 10_000
  });
}

export function useRedisBackups() {
  return useQuery({
    queryKey: runtimeControlQueryKeys.redisBackups,
    queryFn: () => runtimeControlClient.listRedisBackups(),
    refetchInterval: 10_000
  });
}

export function useRollbackBackup() {
  return useBackupMutation("host", (path) =>
    runtimeControlClient.rollbackBackup(backupRequest(path))
  );
}

export function useDeleteHostBackup() {
  return useBackupMutation("host", (path) =>
    runtimeControlClient.deleteHostBackup(backupRequest(path))
  );
}

export function useCreateRedisBackup() {
  return useBackupMutation("redis", () => runtimeControlClient.createRedisBackup());
}

export function useRestoreRedisBackup() {
  return useBackupMutation("redis", (path) =>
    runtimeControlClient.restoreRedisBackup(backupRequest(path))
  );
}

export function useRepairRuntime() {
  return useMutation({
    mutationFn: () => runtimeControlClient.repairRuntime()
  });
}

export function useRepairProxy() {
  return useMutation({
    mutationFn: (proxyPort?: number) => runtimeControlClient.repairProxy(proxyPort)
  });
}

export function useRepairDatastore() {
  return useMutation({
    mutationFn: () => runtimeControlClient.repairDatastore()
  });
}

export function useStartRuntimeServices() {
  return useMutation({
    mutationFn: () => runtimeControlClient.startRuntimeServices()
  });
}

export function useStopRuntimeServices() {
  return useMutation({
    mutationFn: () => runtimeControlClient.stopRuntimeServices()
  });
}

export function useUninstallRuntime() {
  return useMutation({
    mutationFn: (clean: boolean) => runtimeControlClient.uninstallRuntime({ clean })
  });
}

export function useTestKitStatus() {
  return useQuery({
    queryKey: runtimeControlQueryKeys.testKitStatus,
    queryFn: () => runtimeControlClient.getTestKitStatus(),
    refetchInterval: 2_000
  });
}

export function useCreateTestKitBeds() {
  return useTestKitMutation((request: { count: number; prefix: string }) =>
    runtimeControlClient.createTestKitBeds(request)
  );
}

export function useDeleteTestKitBeds() {
  return useTestKitMutation((roomNames: string[]) =>
    runtimeControlClient.deleteTestKitBeds({ roomNames })
  );
}

export function useResetTestKitBeds() {
  return useTestKitMutation(() => runtimeControlClient.resetTestKitBeds());
}

export function useStartTestKitVirtualRecorders() {
  return useTestKitMutation(
    runtimeControlClient.startTestKitVirtualRecorders.bind(runtimeControlClient)
  );
}

export function useSessionTestKitAction(
  action: "stop" | "pause" | "resume" | "delete"
) {
  return useTestKitMutation((sessionID: string | null) => {
    const request = { sessionID };
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
  return useTestKitMutation((request: {
    sessionID: string | null;
    bedRoomNames: string[];
  }) => runtimeControlClient.restartTestKitVirtualRecorders(request));
}

export function useResetTestKitVirtualRecorders() {
  return useTestKitMutation(() =>
    runtimeControlClient.resetTestKitVirtualRecorders()
  );
}

export function useDeleteTestKitOrphanVRecorder() {
  return useTestKitMutation((vrcode: string) =>
    runtimeControlClient.deleteTestKitOrphanVRecorder({ vrcode })
  );
}

function useBackupMutation(
  scope: "host" | "redis",
  mutationFn: (path: string) => ReturnType<typeof runtimeControlClient.rollbackBackup>
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

function backupRequest(path: string) {
  return {
    backup: {
      kind: "localPath" as const,
      value: path
    }
  };
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
