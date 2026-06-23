"use strict";

const assert = require("assert");
const test = require("node:test");
const { createRedisSendDataSpoolStore } = require("../../src/adapters/outbound/redis/send-data-spool-store");

test("redis send_data spool store appends JSON item to configured list", async () => {
  const calls = [];
  const store = createRedisSendDataSpoolStore(
    { listKey: "vitalserver:recorder_ingress:send_data:pending" },
    {
      command(args, callback) {
        calls.push(args);
        callback(null, 3);
      },
    }
  );

  const result = await store.append({ id: "senddata_test", state: "pending" });

  assert.deepStrictEqual(result, { ok: true, depth: 3 });
  assert.strictEqual(calls.length, 1);
  assert.strictEqual(calls[0][0], "RPUSH");
  assert.strictEqual(calls[0][1], "vitalserver:recorder_ingress:send_data:pending");
  assert.deepStrictEqual(JSON.parse(calls[0][2]), { id: "senddata_test", state: "pending" });
});

test("redis send_data spool store reports command failure explicitly", async () => {
  const store = createRedisSendDataSpoolStore(
    { listKey: "vitalserver:recorder_ingress:send_data:pending" },
    {
      command(args, callback) {
        callback(new Error("redis write failed"));
      },
    }
  );

  const result = await store.append({ id: "senddata_test" });

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.error.message, "redis write failed");
});

test("redis send_data spool store claims pending item into in_flight list", async () => {
  const calls = [];
  const item = {
    id: "senddata_test",
    state: "pending",
    vrcode: "VR_A",
    payloadBase64: Buffer.from("payload").toString("base64"),
    attemptCount: 0,
  };
  const store = createRedisSendDataSpoolStore(spoolConfig(), {
    command(args, callback) {
      calls.push(args);
      if (args[0] === "RPOPLPUSH") callback(null, JSON.stringify(item));
      else if (args[0] === "LREM") callback(null, 1);
      else if (args[0] === "RPUSH") callback(null, 1);
      else callback(new Error(`unexpected command ${args[0]}`));
    },
  });

  const result = await store.claim({ now: () => new Date("2026-06-22T10:00:00.000Z") });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.item.state, "in_flight");
  assert.strictEqual(result.item.attemptCount, 1);
  assert.strictEqual(result.item.lastAttemptAt, "2026-06-22T10:00:00.000Z");
  assert.deepStrictEqual(calls[0], [
    "RPOPLPUSH",
    "vitalserver:recorder_ingress:send_data:pending",
    "vitalserver:recorder_ingress:send_data:in_flight",
  ]);
  assert.strictEqual(calls[1][0], "LREM");
  assert.strictEqual(calls[2][0], "RPUSH");
  assert.strictEqual(JSON.parse(calls[2][2]).state, "in_flight");
});

test("redis send_data spool store reports invalid claimed JSON explicitly", async () => {
  const store = createRedisSendDataSpoolStore(spoolConfig(), {
    command(args, callback) {
      callback(null, "{bad");
    },
  });

  const result = await store.claim();

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
  assert.strictEqual(result.raw, "{bad");
});

test("redis send_data spool store moves claimed item to replayed list", async () => {
  const calls = [];
  const store = createRedisSendDataSpoolStore(spoolConfig(), {
    command(args, callback) {
      calls.push(args);
      callback(null, 1);
    },
  });

  const result = await store.markReplayed({ id: "senddata_test", state: "replayed" }, {
    inFlightKey: "vitalserver:recorder_ingress:send_data:in_flight",
    raw: '{"id":"senddata_test","state":"in_flight"}',
  });

  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(calls[0], [
    "LREM",
    "vitalserver:recorder_ingress:send_data:in_flight",
    "1",
    '{"id":"senddata_test","state":"in_flight"}',
  ]);
  assert.strictEqual(calls[1][0], "RPUSH");
  assert.strictEqual(calls[1][1], "vitalserver:recorder_ingress:send_data:replayed");
  assert.deepStrictEqual(JSON.parse(calls[1][2]), { id: "senddata_test", state: "replayed" });
});

function spoolConfig() {
  return {
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    inFlightListKey: "vitalserver:recorder_ingress:send_data:in_flight",
    replayedListKey: "vitalserver:recorder_ingress:send_data:replayed",
    deadLetterListKey: "vitalserver:recorder_ingress:send_data:dead_letter",
  };
}
