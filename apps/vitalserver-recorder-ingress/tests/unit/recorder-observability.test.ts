"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  validateRecorderObservabilityDocument,
} = require("../../src/domain/recorder-observability");

test("recorder observation preserves the existing v1 producer contract", () => {
  assert.deepStrictEqual(
    validateRecorderObservabilityDocument(
      "observation",
      observation(),
      "vr-brmh-15",
    ),
    {
      kind: "valid",
      candidate: {
        eventId: "vr-brmh-15:boot-1:42",
        deviceId: "vr-brmh-15",
      },
    },
  );
});

test("document identity mismatch is a line-level validation failure", () => {
  assert.deepStrictEqual(
    validateRecorderObservabilityDocument(
      "observation",
      observation({ deviceId: "vr-brmh-03" }),
      "vr-brmh-15",
    ),
    {
      kind: "invalid",
      eventId: "vr-brmh-15:boot-1:42",
      documentDeviceId: "vr-brmh-03",
      reason: "device_id_mismatch",
    },
  );
});

test("each endpoint requires its existing producer kind", () => {
  assert.strictEqual(
    validateRecorderObservabilityDocument(
      "diagnosticEvent",
      diagnosticEvent(),
      "vr-brmh-15",
    ).kind,
    "valid",
  );
  assert.strictEqual(
    validateRecorderObservabilityDocument(
      "kernelIncident",
      kernelIncident(),
      "vr-brmh-15",
    ).kind,
    "valid",
  );
  assert.strictEqual(
    validateRecorderObservabilityDocument(
      "diagnosticEvent",
      kernelIncident(),
      "vr-brmh-15",
    ).kind,
    "invalid",
  );
});

test("diagnostic source and kernel evidence invariants are enforced", () => {
  assert.deepStrictEqual(
    validateRecorderObservabilityDocument(
      "diagnosticEvent",
      diagnosticEvent({ source: "invented" }),
      "vr-brmh-15",
    ).reason,
    "diagnostic_source_invalid",
  );
  assert.deepStrictEqual(
    validateRecorderObservabilityDocument(
      "kernelIncident",
      kernelIncident({
        eventId: "vr-brmh-15:kernel-incident:ABC",
      }),
      "vr-brmh-15",
    ).reason,
    "event_id_invalid",
  );
  assert.deepStrictEqual(
    validateRecorderObservabilityDocument(
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
    "previous_boot_journal_invalid",
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
