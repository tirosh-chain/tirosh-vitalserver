import { describe, expect, it } from "vitest";

import {
  backupRequest,
  uninstallRequest,
  updateBundleRequest
} from "./requestBuilders";

describe("console request builders", () => {
  it("builds update bundle file references", () => {
    expect(updateBundleRequest("/tmp/update.tar.gz")).toEqual({
      bundle: {
        kind: "localPath",
        value: "/tmp/update.tar.gz"
      }
    });
  });

  it("builds backup file references", () => {
    expect(backupRequest("/tmp/backup")).toEqual({
      backup: {
        kind: "localPath",
        value: "/tmp/backup"
      }
    });
  });

  it("maps clean uninstall selection to explicit mode", () => {
    expect(uninstallRequest(true)).toEqual({ mode: "clean" });
    expect(uninstallRequest(false)).toEqual({ mode: "standard" });
  });
});
