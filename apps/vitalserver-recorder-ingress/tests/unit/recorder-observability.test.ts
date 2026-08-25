"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const test = require("node:test");
const {
  createRecorderObservabilitySchemaRegistry,
} = require("../../src/adapters/outbound/schema/recorder-observability-schema-registry");

const schemas = createRecorderObservabilitySchemaRegistry();

test("registry receipts exactly cover the authoritative nine-schema set", () => {
  assert.deepStrictEqual(
    schemas.receipts().map((receipt) => receipt.sha256).sort(),
    [
      "079497384d1fbaa87846197df88ff7c279a20df1685149a455023d878974644f",
      "0ddc7ba83e0cfb7369f4d313ea350736c7a4e360617e78057ff55de711d85175",
      "5c756e78fe771d5288c6ec6e4b3d3b43a8c95f54590b52aee687de7b19408daf",
      "84f3d071c837f57347f46aacd6467b933161843e20ae7843b0853f96979d783f",
      "8c3c0b2b2686ee993d6e86202140e8fb3c931ef5487b0f295f34afad285d78aa",
      "d1576c60ba733a38813654b71f10ae9ac0871e88bd91970d8f65f5b1425cc8cf",
      "f3ecc28fb50ad6aca2cef0d887d787f385d7ed3b2d0da2795271d5c6c40d1bd2",
      "f60a1fa3170e110383738d5727526cd7fbe51b2aedcef372b3e2456fd168ad3e",
      "fe0eb2e9a17844efd18ddc41b12affa51663cf286c61b3c85742b62f023dc2ba",
    ].sort(),
  );
});

test("Recorder final profile, boot, diagnostic v2, kernel v2, and active-contract goldens validate", () => {
  const fixtures = [
    ["profile-v1-valid.json", "recorderProfile"],
    ["boot-started-v1-valid.json", "bootEvent"],
    ["shutdown-clean-v1-valid.json", "bootEvent"],
    ["boot-event-v2-valid.json", "bootEvent"],
    ["observation-v2-valid.json", "observation"],
    ["diagnostic-log-v2-valid.json", "diagnosticEvent"],
    ["kernel-incident-v2-valid.json", "kernelIncident"],
  ];
  for (const [file, resourceType] of fixtures) {
    const document = JSON.parse(fs.readFileSync(path.resolve(
      process.cwd(),
      "contracts/recorder-observability/testdata",
      file,
    ), "utf8"));
    const result = schemas.validate(
      resourceType,
      document,
      document.deviceId,
    );
    assert.strictEqual(result.kind, "valid", `${file}: ${result.detail || ""}`);
  }
});

test("schema registry rejects a truncated observation fixture", () => {
  const result = schemas.validate(
    "observation",
    observation(),
    "vr-brmh-15",
  );
  assert.strictEqual(result.kind, "invalid");
  assert.strictEqual(result.reason, "schema_validation_failed");
});

test("document identity mismatch is a line-level validation failure", () => {
  const document = diagnosticEvent({ deviceId: "vr-brmh-03" });
  assert.deepStrictEqual(
    schemas.validate(
      "diagnosticEvent",
      document,
      "vr-brmh-15",
    ),
    {
      kind: "invalid",
      identity: {
        eventId: "vr-brmh-15:boot-1:journal:cursor-1",
        deviceId: "vr-brmh-03",
        schemaVersion: "v1",
        kind: "diagnostic-log",
        siteId: null,
        bootId: "boot-1",
        sequence: null,
        deviceObservedAt: "2026-07-23T01:00:00Z",
        deviceTimeState: null,
      },
      reason: "device_id_mismatch",
      detail: "header=vr-brmh-15; document=vr-brmh-03",
      contractReceipt:
        "5c756e78fe771d5288c6ec6e4b3d3b43a8c95f54590b52aee687de7b19408daf",
    },
  );
});

test("each endpoint requires its existing producer kind", () => {
  assert.strictEqual(
    schemas.validate(
      "diagnosticEvent",
      diagnosticEvent(),
      "vr-brmh-15",
    ).kind,
    "valid",
  );
  assert.strictEqual(
    schemas.validate(
      "kernelIncident",
      kernelIncident(),
      "vr-brmh-15",
    ).kind,
    "valid",
  );
  assert.strictEqual(
    schemas.validate(
      "diagnosticEvent",
      kernelIncident(),
      "vr-brmh-15",
    ).kind,
    "invalid",
  );
});

test("diagnostic source and kernel evidence invariants are enforced", () => {
  assert.deepStrictEqual(
    schemas.validate(
      "diagnosticEvent",
      diagnosticEvent({ source: "invented" }),
      "vr-brmh-15",
    ).reason,
    "schema_validation_failed",
  );
  assert.deepStrictEqual(
    schemas.validate(
      "kernelIncident",
      kernelIncident({
        eventId: "vr-brmh-15:kernel-incident:ABC",
      }),
      "vr-brmh-15",
    ).reason,
    "schema_validation_failed",
  );
  assert.deepStrictEqual(
    schemas.validate(
      "kernelIncident",
      kernelIncident({
        previousBootJournal: {
          available: true,
          storedPath: "/tmp/journal",
          sizeBytes: 42,
          sha256: "a".repeat(64),
        },
      }),
      "vr-brmh-15",
    ).reason,
    "schema_validation_failed",
  );
});

function observation(overrides = {}) {
  return {
    schemaVersion: "v1",
    eventId: "vr-brmh-15:boot-1:42",
    deviceId: "vr-brmh-15",
    bootId: "boot-1",
    sequence: 42,
    kind: "device-health",
    collectionState: "ok",
    deviceObservedAt: "2026-07-23T01:00:00Z",
    uptimeSeconds: { state: "ok", value: 42 },
    ntpState: "synchronized",
    payload: {},
    readIssues: [],
    ...overrides,
  };
}

function diagnosticEvent(overrides = {}) {
  return {
    schemaVersion: "v1",
    eventId: "vr-brmh-15:boot-1:journal:cursor-1",
    deviceId: "vr-brmh-15",
    bootId: "boot-1",
    kind: "diagnostic-log",
    source: "kernel",
    deviceObservedAt: "2026-07-23T01:00:00Z",
    message: "wlan1: beacon loss",
    ...overrides,
  };
}

function kernelIncident(overrides = {}) {
  return {
    schemaVersion: "v1",
    eventId: `vr-brmh-15:kernel-incident:${"a".repeat(64)}`,
    deviceId: "vr-brmh-15",
    captureBootId: "boot-2",
    kind: "kernel-incident",
    capturedAt: "2026-07-23T01:00:00Z",
    source: "pstore",
    incidentType: "panic",
    kernelRelease: "6.12.25+rpt-rpi-v8",
    model: "Raspberry Pi 4 Model B Rev 1.2",
    kernelCommandLine: "console=tty1",
    firmwareThrottleFlags: "throttled=0x0",
    artifacts: [{
      name: "console-ramoops-0",
      sourcePath: "/sys/fs/pstore/console-ramoops-0",
      sourceRoot: "/sys/fs/pstore",
      storedPath: "/data/vitalrecorder-observer/kernel-incidents/a/console-ramoops-0",
      sizeBytes: 42,
      sha256: "a".repeat(64),
    }],
    previousBootJournal: { available: false },
    messageExcerpt: "Kernel panic",
    truncated: false,
    ...overrides,
  };
}
