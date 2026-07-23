"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const {
  createRecorderObservabilityLedger,
} = require("../../src/adapters/outbound/file/recorder-observability-ledger");

test("ledger persists accepted and quarantined evidence across reopen", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "observability-ledger-"));
  const ledger = createRecorderObservabilityLedger({ directory });

  ledger.persist(batch());

  const reopened = createRecorderObservabilityLedger({ directory });
  assert.deepStrictEqual(
    reopened.findAccepted("BRMH-OR1", "vr-brmh-15:boot-1:42"),
    { contentHash: "a".repeat(64) },
  );
  const segmentPath = path.join(directory, "ledger-2026-07-23.ndjson");
  const persisted = JSON.parse(fs.readFileSync(segmentPath, "utf8").trim());
  assert.deepStrictEqual(
    persisted.records.map((record) => record.disposition),
    ["accepted", "quarantined"],
  );
});

test("ledger exposes malformed durable state as an explicit startup failure", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "observability-ledger-"));
  fs.writeFileSync(
    path.join(directory, "ledger-2026-07-23.ndjson"),
    "{\"schemaVersion\":1,\"records\":[]}\n",
  );

  assert.throws(
    () => createRecorderObservabilityLedger({ directory }),
    /ledger segment is invalid/,
  );
});

function batch() {
  const base = {
    schemaVersion: 1,
    requestId: "request-1",
    receivedAt: "2026-07-23T02:00:00.000Z",
    resourceType: "observation",
    vrcode: "BRMH-OR1",
    requestDeviceId: "vr-brmh-15",
    sourceIp: "172.31.0.157",
  };
  return {
    schemaVersion: 1,
    requestId: "request-1",
    receivedAt: "2026-07-23T02:00:00.000Z",
    records: [
      {
        ...base,
        lineNumber: 1,
        disposition: "accepted",
        documentDeviceId: "vr-brmh-15",
        eventId: "vr-brmh-15:boot-1:42",
        contentHash: "a".repeat(64),
        rawDocument: "{\"eventId\":\"vr-brmh-15:boot-1:42\"}",
        quarantineReason: null,
      },
      {
        ...base,
        lineNumber: 2,
        disposition: "quarantined",
        documentDeviceId: "vr-brmh-03",
        eventId: "vr-brmh-15:boot-1:43",
        contentHash: "b".repeat(64),
        rawDocument: "{\"eventId\":\"vr-brmh-15:boot-1:43\"}",
        quarantineReason: "device_id_mismatch",
      },
    ],
  };
}
