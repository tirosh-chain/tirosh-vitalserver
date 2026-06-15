import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";

export function formatHTTPStatus(
  value: string | null | undefined
): string {
  const trimmed = value?.trim();
  return trimmed ? trimmed : NOT_REPORTED;
}

export function runtimeURL(target: {
  host: string;
  port: number;
}): string | null {
  const host = target.host.trim();
  if (!host) {
    return null;
  }
  return `http://${host}:${target.port}/`;
}

export function sameHostRuntimeURL(target: {
  hostname: string | undefined;
  port: number | undefined;
}): string | null {
  if (target.port === undefined || !Number.isInteger(target.port)) {
    return null;
  }
  const hostname = target.hostname?.trim();
  if (!hostname) {
    return null;
  }
  const host = hostname.includes(":") && !hostname.startsWith("[")
    ? `[${hostname}]`
    : hostname;
  return `http://${host}:${target.port}/`;
}
