import { describe, expect, it } from "vitest";

import {
  logExportPathMessages,
  validateHostLogExportPath
} from "./runtimePathPolicy";

describe("validateHostLogExportPath", () => {
  it("allows writable-user-location style zip paths", () => {
    expect(validateHostLogExportPath("/Users/test/Downloads/vitalserver-logs.zip")).toBeNull();
    expect(validateHostLogExportPath("/tmp/vitalserver-logs.zip")).toBeNull();
    expect(validateHostLogExportPath("/usr/local/var/vitalserver-logs.zip")).toBeNull();
  });

  it("requires an absolute zip path", () => {
    expect(validateHostLogExportPath("vitalserver-logs.zip")).toBe(logExportPathMessages.invalid);
    expect(validateHostLogExportPath("/tmp/vitalserver-logs.txt")).toBe(logExportPathMessages.invalid);
    expect(validateHostLogExportPath("   ")).toBe(logExportPathMessages.invalid);
  });

  it("rejects iCloud and protected user locations", () => {
    expect(
      validateHostLogExportPath("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/vitalserver-logs.zip")
    ).toBe(logExportPathMessages.protected);
    expect(validateHostLogExportPath("/Users/test/Desktop/vitalserver-logs.zip")).toBe(
      logExportPathMessages.protected
    );
    expect(validateHostLogExportPath("/Users/test/Documents/vitalserver-logs.zip")).toBe(
      logExportPathMessages.protected
    );
  });

  it("rejects system-managed locations", () => {
    expect(validateHostLogExportPath("/Applications/vitalserver-logs.zip")).toBe(
      logExportPathMessages.protected
    );
    expect(validateHostLogExportPath("/Library/Application Support/TiroshVitalServer/vitalserver-logs.zip")).toBe(
      logExportPathMessages.protected
    );
    expect(validateHostLogExportPath("/System/Volumes/Data/vitalserver-logs.zip")).toBe(
      logExportPathMessages.protected
    );
    expect(validateHostLogExportPath("/usr/bin/vitalserver-logs.zip")).toBe(
      logExportPathMessages.protected
    );
  });
});
