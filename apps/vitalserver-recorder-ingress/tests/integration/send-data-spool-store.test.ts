"use strict";

const assert = require("assert");
const test = require("node:test");
const { createRedisSendDataSpoolStore } = require("../../src/infrastructure/redis/send-data-spool-store");

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
