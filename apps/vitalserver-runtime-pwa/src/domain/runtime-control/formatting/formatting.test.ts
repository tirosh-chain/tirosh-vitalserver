import { describe, expect, it } from "vitest";

import { formatBytes } from "./bytes";
import {
  formatHTTPStatus,
  runtimeURL,
  sameHostRuntimeURL
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
    expect(formatRuntimeState("initializing")).toBe("Initializing");
    expect(formatRuntimeState("healthy")).toBe("Healthy");
    expect(formatRuntimeState("critical")).toBe("Critical");
    expect(formatRuntimeState(undefined)).toBe("Unknown");
  });

  it("formats uptime from a startedAt timestamp", () => {
    const now = Date.now();
    const startedAt = new Date(now - 3661 * 1000).toISOString();
    expect(formatUptimeSince(startedAt)).toMatch(/^01:01:0[0-2]$/);
  });

  it("formats HTTP probe text without deriving reachability state", () => {
    expect(formatHTTPStatus("HTTP 200")).toBe("HTTP 200");
    expect(formatHTTPStatus("failed")).toBe("failed");
    expect(formatHTTPStatus(undefined)).toBe("Not reported");
  });

  it("builds runtime URLs only from explicit host and port", () => {
    expect(runtimeURL({ host: "vital.local", port: 18080 })).toBe(
      "http://vital.local:18080/"
    );
    expect(runtimeURL({ host: "", port: 18080 })).toBeNull();
  });

  it("builds same-host runtime URLs from the browser host and explicit port", () => {
    expect(sameHostRuntimeURL({ hostname: "mac.local", port: 18080 })).toBe(
      "http://mac.local:18080/"
    );
    expect(sameHostRuntimeURL({ hostname: "::1", port: 18321 })).toBe(
      "http://[::1]:18321/"
    );
    expect(sameHostRuntimeURL({ hostname: "", port: 18080 })).toBeNull();
    expect(
      sameHostRuntimeURL({ hostname: "mac.local", port: undefined })
    ).toBeNull();
  });
});
