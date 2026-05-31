import { DEFAULT_APP_SETTINGS } from "@/config/appSettings";

export function successfulHTTP(value: string | null | undefined): boolean {
  return Boolean(value && /(^|\D)2\d\d(\D|$)/.test(value));
}

export function formatHTTPReachability(
  value: string | null | undefined
): string {
  if (successfulHTTP(value)) {
    return "Reachable";
  }
  if (!value) {
    return "Unknown";
  }
  if (value.toLowerCase() === "failed") {
    return "Unreachable";
  }
  return value;
}

export function runtimeURL(
  proxyPort: number | null | undefined,
  defaultProxyPort = DEFAULT_APP_SETTINGS.runtimeControl.defaultProxyPort
): string {
  const host =
    typeof window === "undefined" || !window.location.hostname
      ? "127.0.0.1"
      : window.location.hostname;
  const port = proxyPort ?? defaultProxyPort;
  return `http://${host}:${port}/`;
}

export function runtimeControlURL(
  runtimeControlPort?: number | null,
  defaultRuntimeControlPort = DEFAULT_APP_SETTINGS.runtimeControl.defaultPort
): string {
  if (runtimeControlPort !== undefined && runtimeControlPort !== null) {
    return runtimeControlURLForPort(runtimeControlPort);
  }
  if (typeof window === "undefined" || !window.location.origin) {
    return `http://127.0.0.1:${defaultRuntimeControlPort}/`;
  }
  return `${window.location.origin}/`;
}

export function runtimeControlURLForPort(runtimeControlPort: number): string {
  const host =
    typeof window === "undefined" || !window.location.hostname
      ? "127.0.0.1"
      : window.location.hostname;
  return `http://${host}:${runtimeControlPort}/`;
}
