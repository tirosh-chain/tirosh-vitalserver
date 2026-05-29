import { describe, expect, it } from "vitest";

import { formatBytes } from "./bytes";
import {
  runtimeControlURL,
  runtimeControlURLForPort,
  successfulHTTP
} from "./http";
import { formatRuntimeState } from "./runtimeState";
import { formatUptimeSince } from "./time";

describe("runtime presentation formatting", () => {
  it("formats byte values with binary units", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(1024)).toBe("1.0 KiB");
    expect(formatBytes(1024 * 1024)).toBe("1.0 MiB");
  });

  it("formats unknown byte values", () => {
    expect(formatBytes(undefined)).toBe("Unknown");
    expect(formatBytes(null)).toBe("Unknown");
  });

  it("maps runtime state values to display labels", () => {
    expect(formatRuntimeState("healthy")).toBe("Healthy");
    expect(formatRuntimeState("critical")).toBe("Critical");
    expect(formatRuntimeState(undefined)).toBe("Unknown");
  });

  it("formats uptime from a startedAt timestamp", () => {
    const now = Date.now();
    const startedAt = new Date(now - 3661 * 1000).toISOString();
    expect(formatUptimeSince(startedAt)).toMatch(/^01:01:0[0-2]$/);
  });

  it("detects successful HTTP status text", () => {
    expect(successfulHTTP("HTTP 200")).toBe(true);
    expect(successfulHTTP("HTTP 503")).toBe(false);
    expect(successfulHTTP(undefined)).toBe(false);
  });

  it("falls back to the packaged Remote Console URL outside the browser", () => {
    expect(runtimeControlURL()).toBe("http://127.0.0.1:18321/");
    expect(runtimeControlURLForPort(18444)).toBe("http://127.0.0.1:18444/");
  });
});
