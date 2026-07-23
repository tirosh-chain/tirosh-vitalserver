import type { RuntimeLogSource } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export const consoleQueryKeys = {
  platformState: ["platform", "state"] as const,
  redisRelayStatus: ["runtime", "redis-relay", "status"] as const,
  redisRelaySettings: ["runtime", "redis-relay", "settings"] as const,
  vitalDBObservation: ["runtime", "vitaldb", "observations", "latest"] as const,
  operationState: ["console", "operation-state"] as const,
  platformWorkflow: ["platform", "workflows", "current"] as const,
  runtimeStack: ["runtime", "stack"] as const,
  runtimeServiceResource: (service: string) =>
    ["runtime", "services", service, "resource"] as const,
  capabilities: ["console", "capabilities"] as const,
  runtimeProductSettings: ["runtime", "settings"] as const,
  runtimePlatformSettings: ["platform", "settings"] as const,
  labScenarios: ["lab", "scenarios"] as const,
  labBeds: ["lab", "beds"] as const,
  labRecorders: ["lab", "recorders"] as const,
  labSessions: ["lab", "sessions"] as const,
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
  recorderActivity: (query: {
    vrcode: string;
    bucketSeconds: number;
    period: string;
    pageIndex?: number;
  }) => ["vitaldb", "recorders", query.vrcode, "activity", query] as const,
  recorderVitalFiles: (vrcode: string) =>
    ["vitaldb", "recorders", vrcode, "vital-files"] as const,
  recorderObservability: (vrcode: string) =>
    ["vitaldb", "recorders", vrcode, "observability"] as const,
  recorderObservabilityTimeline: (query: object) =>
    ["vitaldb", "recorders", "observability", "timeline", query] as const,
  recorderObservabilityIncidents: (query: object) =>
    ["vitaldb", "recorders", "observability", "incidents", query] as const,
  releaseInfo: ["platform", "release"] as const,
  installInfo: ["platform", "installation"] as const,
  beds: ["vitaldb", "beds"] as const,
  relationships: ["vitaldb", "relationships"] as const
};
