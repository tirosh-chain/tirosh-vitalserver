"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  createRecorderObservabilityIngressService,
} = require("../../src/application/recorder-observability-ingress-service");

test("mixed permanent failures are quarantined without rejecting valid lines", () => {
  const ledger = memoryLedger();
  const service = createRecorderObservabilityIngressService({
    ledger,
    clock: { now: () => "2026-07-23T02:00:00.000Z" },
    createRequestId: () => "request-1",
  });

  const result = service.admit({
    resourceType: "observation",
    vrcode: "BRMH-OR1",
    requestDeviceId: "vr-brmh-15",
    sourceIp: "172.31.0.157",
    lines: [
      line(1, observation()),
      line(2, observation({
        eventId: "vr-brmh-15:boot-1:43",
        sequence: 43,
        deviceId: "vr-brmh-03",
      })),
    ],
  });

  assert.deepStrictEqual(result, {
    state: "admitted",
    requestId: "request-1",
    accepted: 1,
    duplicates: 0,
    quarantined: 1,
  });
  assert.strictEqual(ledger.batches.length, 1);
  assert.deepStrictEqual(
    ledger.batches[0].records.map((record) => [
      record.disposition,
      record.vrcode,
      record.requestDeviceId,
      record.quarantineReason,
    ]),
    [
      ["accepted", "BRMH-OR1", "vr-brmh-15", null],
      ["quarantined", "BRMH-OR1", "vr-brmh-15", "device_id_mismatch"],
    ],
  );
});

test("duplicate succeeds and conflicting content is durably quarantined", () => {
  const ledger = memoryLedger();
  const service = createRecorderObservabilityIngressService({
    ledger,
    clock: { now: () => "2026-07-23T02:00:00.000Z" },
    createRequestId: (() => {
      let value = 0;
      return () => `request-${++value}`;
    })(),
  });
  const input = {
    resourceType: "observation",
    vrcode: "BRMH-OR1",
    requestDeviceId: "vr-brmh-15",
    sourceIp: "172.31.0.157",
    lines: [line(1, observation())],
  };

  assert.strictEqual(service.admit(input).accepted, 1);
  assert.deepStrictEqual(service.admit(input), {
    state: "admitted",
    requestId: "request-2",
    accepted: 0,
    duplicates: 1,
    quarantined: 0,
  });
  const conflict = service.admit({
    ...input,
    lines: [line(1, observation({ collectionState: "partial" }))],
  });

  assert.strictEqual(conflict.accepted, 0);
  assert.strictEqual(conflict.quarantined, 1);
  assert.strictEqual(
    ledger.batches[1].records[0].quarantineReason,
    "event_id_content_conflict",
  );
});

function memoryLedger() {
  const accepted = new Map();
  return {
    batches: [],
    findAccepted(vrcode, eventId) {
      return accepted.get(`${vrcode}\u0000${eventId}`) || null;
    },
    persist(batch) {
      this.batches.push(batch);
      for (const record of batch.records) {
        if (record.disposition === "accepted") {
          accepted.set(`${record.vrcode}\u0000${record.eventId}`, {
            contentHash: record.contentHash,
          });
        }
      }
    },
  };
}

function line(lineNumber, document) {
  return {
    lineNumber,
    rawDocument: JSON.stringify(document),
    document,
  };
}

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
