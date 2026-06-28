"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  DEFAULT_QUIET_WINDOW_MS,
  decideSendDataRawArchiveFinalization,
} = require("../../src/domain/send-data-raw-archive-finalization-policy");

test("raw archive finalization uses a five minute inactivity window", () => {
  const nowMs = Date.parse("2026-06-28T10:05:00.000Z");

  const decision = decideSendDataRawArchiveFinalization({
    vrcode: "VR-1",
    hasJoined: true,
    rawArchiveRecords: 12,
    activeConnections: 0,
    lastRawArchivedAt: "2026-06-28T10:00:00.000Z",
    nowMs,
    archiveCursorStable: true,
    realtimeReplayDrained: true,
    alreadyExported: false,
  });

  assert.strictEqual(DEFAULT_QUIET_WINDOW_MS, 300000);
  assert.deepStrictEqual(decision, {
    vrcode: "VR-1",
    state: "finalizable_by_inactivity",
    finalizable: true,
    quietWindowMs: 300000,
    inactiveForMs: 300000,
    reasons: [],
  });
});

test("raw archive finalization does not infer stopped while a recorder connection is active", () => {
  const decision = decideSendDataRawArchiveFinalization({
    vrcode: "VR-1",
    hasJoined: true,
    rawArchiveRecords: 12,
    activeConnections: 1,
    lastRawArchivedAt: "2026-06-28T10:00:00.000Z",
    nowMs: Date.parse("2026-06-28T10:10:00.000Z"),
    archiveCursorStable: true,
    realtimeReplayDrained: true,
    alreadyExported: false,
  });

  assert.strictEqual(decision.state, "open");
  assert.strictEqual(decision.finalizable, false);
  assert.deepStrictEqual(decision.reasons, ["active_connection_present"]);
});

test("raw archive finalization marks disconnected recorders as candidates before five minutes", () => {
  const decision = decideSendDataRawArchiveFinalization({
    vrcode: "VR-1",
    hasJoined: true,
    rawArchiveRecords: 12,
    activeConnections: 0,
    lastRawArchivedAt: "2026-06-28T10:00:00.000Z",
    nowMs: Date.parse("2026-06-28T10:04:59.000Z"),
    archiveCursorStable: true,
    realtimeReplayDrained: true,
    alreadyExported: false,
  });

  assert.strictEqual(decision.state, "inactive_candidate");
  assert.strictEqual(decision.finalizable, false);
  assert.deepStrictEqual(decision.reasons, ["quiet_window_not_elapsed"]);
});

test("raw archive finalization requires stable archive cursor and drained realtime replay", () => {
  const decision = decideSendDataRawArchiveFinalization({
    vrcode: "VR-1",
    hasJoined: true,
    rawArchiveRecords: 12,
    activeConnections: 0,
    lastRawArchivedAt: "2026-06-28T10:00:00.000Z",
    nowMs: Date.parse("2026-06-28T10:05:00.000Z"),
    archiveCursorStable: false,
    realtimeReplayDrained: false,
    alreadyExported: false,
  });

  assert.strictEqual(decision.state, "inactive_candidate");
  assert.strictEqual(decision.finalizable, false);
  assert.deepStrictEqual(decision.reasons, [
    "archive_cursor_not_stable",
    "realtime_replay_not_drained",
  ]);
});

test("raw archive finalization preserves not observed and already exported states", () => {
  const nowMs = Date.parse("2026-06-28T10:05:00.000Z");

  assert.deepStrictEqual(decideSendDataRawArchiveFinalization({
    vrcode: "VR-1",
    hasJoined: false,
    rawArchiveRecords: 12,
    activeConnections: 0,
    lastRawArchivedAt: "2026-06-28T10:00:00.000Z",
    nowMs,
    archiveCursorStable: true,
    realtimeReplayDrained: true,
    alreadyExported: false,
  }).reasons, ["recorder_not_observed"]);

  assert.deepStrictEqual(decideSendDataRawArchiveFinalization({
    vrcode: "VR-1",
    hasJoined: true,
    rawArchiveRecords: 12,
    activeConnections: 0,
    lastRawArchivedAt: "2026-06-28T10:00:00.000Z",
    nowMs,
    archiveCursorStable: true,
    realtimeReplayDrained: true,
    alreadyExported: true,
  }).reasons, ["already_exported"]);
});
