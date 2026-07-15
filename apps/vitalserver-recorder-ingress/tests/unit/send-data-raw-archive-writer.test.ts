"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { createSendDataRawArchiveWriter } = require("../../src/adapters/outbound/file/send-data-raw-archive-writer");

test("send_data raw archive writer appends source payload JSONL", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "send-data-raw-archive-"));
  const archivePath = path.join(directory, "send-data-raw.jsonl");
  const writer = createSendDataRawArchiveWriter({ enabled: true, path: archivePath });

  const result = writer.append(spoolItem());

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.archiveId, "send-data-raw.jsonl");
  assert.strictEqual(result.offset, 0);
  assert.strictEqual(result.endOffset, fs.statSync(archivePath).size);
  const lines = fs.readFileSync(archivePath, "utf8").trim().split("\n");
  assert.strictEqual(lines.length, 1);
  const record = JSON.parse(lines[0]);
  assert.strictEqual(record.schemaVersion, 1);
  assert.strictEqual(record.kind, "send_data_raw_payload");
  assert.strictEqual(record.itemId, "senddata_test");
  assert.strictEqual(record.vrcode, "VR_A");
  assert.strictEqual(record.receivedAt, "2026-06-22T10:00:00.000Z");
  assert.strictEqual(record.payloadBase64, Buffer.from("payload").toString("base64"));
  assert.strictEqual(record.payloadSha256, "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5");
  assert.strictEqual(record.payloadBytes, 7);
});

test("send_data raw archive writer reports disabled archive as unavailable", () => {
  const writer = createSendDataRawArchiveWriter({ enabled: false, path: "" });

  const result = writer.append(spoolItem());

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "raw_archive_unavailable");
});

test("send_data raw archive writer rotates and prunes archive files", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "send-data-raw-archive-"));
  const archivePath = path.join(directory, "send-data-raw.jsonl");
  const writer = createSendDataRawArchiveWriter({
    enabled: true,
    path: archivePath,
    maxFileBytes: 1,
    maxFiles: 2,
  });

  assert.strictEqual(writer.append(spoolItem("senddata_1")).ok, true);
  assert.strictEqual(writer.append(spoolItem("senddata_2")).ok, true);
  assert.strictEqual(writer.append(spoolItem("senddata_3")).ok, true);

  const files = fs.readdirSync(directory).sort();
  const active = fs.readFileSync(archivePath, "utf8").trim().split("\n");
  const rotated = files.filter((name) => /^send-data-raw\..+\.jsonl$/.test(name));

  assert.strictEqual(active.length, 1);
  assert.strictEqual(JSON.parse(active[0]).itemId, "senddata_3");
  assert.strictEqual(rotated.length, 1);
});

function spoolItem(id = "senddata_test") {
  return {
    schemaVersion: 1,
    id,
    state: "pending",
    vrcode: "VR_A",
    connectionId: "connection-1",
    requestId: "request-1",
    receivedAt: "2026-06-22T10:00:00.000Z",
    payloadEncoding: "binary",
    payloadBytes: 7,
    payloadBase64: Buffer.from("payload").toString("base64"),
    payloadSummary: { bytes: 7, vrcode: "VR_A" },
    attemptCount: 0,
    lastAttemptAt: null,
    lastFailure: null,
  };
}
