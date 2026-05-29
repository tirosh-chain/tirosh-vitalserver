export function successfulHTTP(value: string | null | undefined): boolean {
  return Boolean(value && /(^|\D)2\d\d(\D|$)/.test(value));
}

export function runtimeURL(proxyPort: number | null | undefined): string {
  const host =
    typeof window === "undefined" || !window.location.hostname
      ? "127.0.0.1"
      : window.location.hostname;
  const port = proxyPort ?? 80;
  return `http://${host}:${port}/`;
}

export function runtimeControlURL(runtimeControlPort?: number | null): string {
  if (runtimeControlPort !== undefined && runtimeControlPort !== null) {
    return runtimeControlURLForPort(runtimeControlPort);
  }
  if (typeof window === "undefined" || !window.location.origin) {
    return "http://127.0.0.1:18321/";
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
