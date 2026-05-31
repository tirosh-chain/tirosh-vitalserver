import type { RuntimeLogSource } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export const consoleQueryKeys = {
  overview: ["console", "overview"] as const,
  capabilities: ["console", "capabilities"] as const,
  settings: ["console", "settings"] as const,
  events: (query: { limit?: number; type?: string; since?: string }) =>
    ["console", "events", query] as const,
  logs: (request: { source: RuntimeLogSource; lineLimit: number }) =>
    ["console", "logs", request] as const,
  hostBackups: ["host", "backups"] as const,
  redisBackups: ["host", "backups", "redis"] as const,
  testKitStatus: ["dev", "testkit", "status"] as const,
  recorders: ["vitaldb", "recorders"] as const,
  beds: ["vitaldb", "beds"] as const
};
