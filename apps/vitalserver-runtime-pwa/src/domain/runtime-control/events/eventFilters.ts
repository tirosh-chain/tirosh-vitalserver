import { runtimeEventTypeValues } from "@/domain/runtime-control/contracts/runtimeEventTypes";

export type RuntimeEventPeriod = "1h" | "6h" | "24h" | "7d";

export const runtimeEventPeriods: Array<{
  value: RuntimeEventPeriod;
  label: string;
  milliseconds: number;
}> = [
  { value: "1h", label: "Last 1 hour", milliseconds: 60 * 60 * 1000 },
  { value: "6h", label: "Last 6 hours", milliseconds: 6 * 60 * 60 * 1000 },
  { value: "24h", label: "Last 24 hours", milliseconds: 24 * 60 * 60 * 1000 },
  { value: "7d", label: "Last 7 days", milliseconds: 7 * 24 * 60 * 60 * 1000 }
];

export const runtimeEventTypes = [...runtimeEventTypeValues];

export function sinceForPeriod(
  period: RuntimeEventPeriod,
  now: Date = new Date()
): string {
  const match = runtimeEventPeriods.find((candidate) => candidate.value === period);
  const milliseconds = match?.milliseconds ?? runtimeEventPeriods[2].milliseconds;
  return new Date(now.getTime() - milliseconds).toISOString();
}
