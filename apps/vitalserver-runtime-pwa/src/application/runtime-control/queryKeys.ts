import type { RuntimeLogSource } from "@/domain/runtime-control/contracts/runtimeControlTypes";

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
