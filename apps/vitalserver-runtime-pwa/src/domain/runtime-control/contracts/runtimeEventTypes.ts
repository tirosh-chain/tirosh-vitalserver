export const runtimeEventTypeValues = [
  "operation-accepted",
  "operation-running",
  "operation-completed",
  "operation-failed",
  "operation-cancelled",
  "operation-interrupted"
] as const;

export type RuntimeEventTypeValue = (typeof runtimeEventTypeValues)[number];
