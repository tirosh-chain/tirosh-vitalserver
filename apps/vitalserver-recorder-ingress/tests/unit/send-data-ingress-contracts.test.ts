"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const test = require("node:test");
const {
  sendDataBackpressureActions,
  sendDataFailureReasons,
  sendDataIngressModes,
  sendDataIngressOutcomes,
  sendDataSpoolItemStates,
  isTerminalSpoolItemState,
} = require("../../src/domain/send-data-ingress-contracts");
const {
  recorderIngressReplayMemoryGuardStatusValues,
} = require("../../src/domain/memory-guard-types");

test("send_data ingress contract keeps mode, outcome, and state names explicit", () => {
  assert.deepStrictEqual(Object.values(sendDataIngressModes), [
    "passthrough",
    "observe_only",
    "mirror_spool",
    "spool_only",
    "spool_and_replay",
  ]);
  assert.deepStrictEqual(Object.values(sendDataIngressOutcomes), [
    "accepted",
    "spooled",
    "rejected",
    "invalid_payload",
    "raw_archive_write_failed",
    "spool_write_failed",
  ]);
  assert.deepStrictEqual(Object.values(sendDataSpoolItemStates), [
    "pending",
    "in_flight",
    "replayed",
    "retryable_failed",
    "dead_lettered",
  ]);
  assert.deepStrictEqual(Object.values(sendDataBackpressureActions), [
    "accept",
    "reject",
    "dead_letter_oldest",
  ]);
});

test("send_data ingress contract keeps failure reasons explicit", () => {
  assert.deepStrictEqual(Object.values(sendDataFailureReasons), [
    "invalid_payload",
    "spool_unavailable",
    "spool_full",
    "raw_archive_unavailable",
    "raw_archive_write_failed",
    "spool_write_failed",
    "upstream_unavailable",
    "upstream_timeout",
    "upstream_rejected",
    "replay_session_unavailable",
  ]);
});

test("send_data spool terminal states stay narrow", () => {
  assert.strictEqual(isTerminalSpoolItemState("pending"), false);
  assert.strictEqual(isTerminalSpoolItemState("in_flight"), false);
  assert.strictEqual(isTerminalSpoolItemState("retryable_failed"), false);
  assert.strictEqual(isTerminalSpoolItemState("replayed"), true);
  assert.strictEqual(isTerminalSpoolItemState("dead_lettered"), true);
});

test("OpenAPI send_data enums match recorder ingress domain contract", () => {
  const openAPIPath = path.resolve(process.cwd(), "../../docs/api/recorder-ingress.openapi.yaml");
  const openAPI = fs.readFileSync(openAPIPath, "utf8");

  assert.deepStrictEqual(enumValues(openAPI, "SendDataIngressMode"), Object.values(sendDataIngressModes));
  assert.deepStrictEqual(
    enumValues(openAPI, "RecorderIngressFailure", "reason"),
    Object.values(sendDataFailureReasons)
  );
  assert.deepStrictEqual(
    enumValues(openAPI, "RecorderIngressReplayAdaptiveStatus", "memoryGuardStatus"),
    recorderIngressReplayMemoryGuardStatusValues
  );
});

function enumValues(yaml: string, schemaName: string, propertyName?: string) {
  const block = propertyName
    ? nestedBlock(yaml, `${schemaName}:`, `${propertyName}:`)
    : blockAfter(yaml, `${schemaName}:`);
  const enumBlock = blockAfter(block, "enum:");
  const values = [];
  for (const line of enumBlock.split("\n")) {
    const match = line.match(/^\s+-\s+([a-z0-9_]+)\s*$/);
    if (!match && values.length === 0) continue;
    if (!match) break;
    values.push(match[1]);
  }
  return values;
}

function nestedBlock(yaml: string, schemaMarker: string, propertyMarker: string) {
  return blockAfter(blockAfter(yaml, schemaMarker), propertyMarker);
}

function blockAfter(text: string, marker: string) {
  const index = text.indexOf(marker);
  assert.notStrictEqual(index, -1, `missing marker: ${marker}`);
  return text.slice(index + marker.length);
}
