import type { RuntimeLogSource } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export const consoleQueryKeys = {
  overview: ["console", "overview"] as const,
  operationState: ["console", "operation-state"] as const,
  guestStackStatus: ["console", "guest-stack-status"] as const,
  capabilities: ["console", "capabilities"] as const,
  settings: ["console", "settings"] as const,
  labScenarios: ["lab", "scenarios"] as const,
  labBeds: ["lab", "beds"] as const,
  labRecorders: ["lab", "recorders"] as const,
  labVitalFiles: ["lab", "vital-files"] as const,
  labSession: (sessionId: string) => ["lab", "sessions", sessionId] as const,
  events: (query: { limit?: number; type?: string; since?: string }) =>
    ["console", "events", query] as const,
  logs: (request: { source: RuntimeLogSource; lineLimit: number }) =>
    ["console", "logs", request] as const,
  hostBackups: ["host", "backups"] as const,
  redisBackups: ["host", "backups", "redis"] as const,
  runtimeDataBackups: ["host", "backups", "runtime-data"] as const,
  recorders: ["vitaldb", "recorders"] as const,
  beds: ["vitaldb", "beds"] as const,
  relationships: ["vitaldb", "relationships"] as const
};
