"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  createRecorderObservabilityIngressService,
} = require("../../src/application/recorder-observability-ingress-service");

test("mixed permanent failures are prepared for one durable transaction", async () => {
  const repository = memoryRepository();
  const service = createRecorderObservabilityIngressService({
    repository,
    schemas: testSchemas(),
    clock: { now: () => "2026-07-23T02:00:00.000Z" },
    createRequestId: () => "00000000-0000-4000-8000-000000000001",
  });

  const result = await service.admit({
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
      {
        lineNumber: 3,
        rawDocument: "{broken",
        document: null,
        parseFailure: "Unexpected token",
      },
    ],
  });

  assert.deepStrictEqual(result, {
    state: "admitted",
    requestId: "00000000-0000-4000-8000-000000000001",
    accepted: 1,
    duplicates: 0,
    quarantined: 2,
  });
  assert.strictEqual(repository.batches.length, 1);
  assert.deepStrictEqual(
    repository.batches[0].lines.map((record) => record.failureCode),
    [null, "device_id_mismatch", "json_parse_failed"],
  );
  assert.strictEqual(repository.batches[0].lines[0].rawDocument, JSON.stringify(
    observation(),
  ));
});

test("RFC 8785 canonical hash ignores JSON object key order", async () => {
  const repository = memoryRepository();
  const service = createRecorderObservabilityIngressService({
    repository,
    schemas: testSchemas(),
    createRequestId: () => "00000000-0000-4000-8000-000000000002",
  });
  const left = observation();
  const right = Object.fromEntries(Object.entries(left).reverse());

  await service.admit({
    resourceType: "observation",
    vrcode: "BRMH-OR1",
    requestDeviceId: "vr-brmh-15",
    sourceIp: "172.31.0.157",
    lines: [line(1, left), line(2, right)],
  });

  assert.strictEqual(
    repository.batches[0].lines[0].canonicalSha256,
    repository.batches[0].lines[1].canonicalSha256,
  );
  assert.notStrictEqual(
    repository.batches[0].lines[0].rawSha256,
    repository.batches[0].lines[1].rawSha256,
  );
});

function memoryRepository() {
  return {
    batches: [],
    async admit(batch) {
      this.batches.push(batch);
      return batch.lines.reduce((counts, item) => {
        if (item.failureCode) counts.quarantined += 1;
        else counts.accepted += 1;
        return counts;
      }, { accepted: 0, duplicates: 0, quarantined: 0 });
    },
  };
}

function testSchemas() {
  return {
    validate(_resourceType, document, requestDeviceId) {
      const identity = {
        eventId: document.eventId,
        deviceId: document.deviceId,
        schemaVersion: document.schemaVersion,
        kind: document.kind,
        siteId: null,
        bootId: document.bootId,
        sequence: document.sequence,
        deviceObservedAt: document.deviceObservedAt,
        deviceTimeState: null,
      };
      return document.deviceId === requestDeviceId
        ? { kind: "valid", identity, contractReceipt: "a".repeat(64) }
        : {
          kind: "invalid",
          identity,
          reason: "device_id_mismatch",
          detail: null,
          contractReceipt: "a".repeat(64),
        };
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
