import type { AuditSinkPort } from "../../src/application/ports/outbound/audit-sink-port";
import type { SendDataReplayTargetPort } from "../../src/application/ports/outbound/send-data-replay-target-port";
import type { SendDataSpoolStorePort } from "../../src/application/ports/outbound/send-data-spool-store-port";
import type { VrIdentityStorePort } from "../../src/application/ports/outbound/vr-identity-store-port";
import type { SendDataSpoolItem } from "../../src/domain/send-data-spool-types";

"use strict";

const assert = require("assert");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { createAuditLogWriter } = require("../../src/adapters/outbound/file/audit-log-writer");
const { createAuditStdoutWriter } = require("../../src/adapters/outbound/process/audit-stdout-writer");
const { createRedisAuditEventStore } = require("../../src/adapters/outbound/redis/audit-event-store");
const { createRedisSendDataSpoolStore } = require("../../src/adapters/outbound/redis/send-data-spool-store");
const { createVrIdentityStore } = require("../../src/adapters/outbound/redis/vr-identity-store");
const { createSocketIoSendDataReplayTarget } = require("../../src/adapters/outbound/socketio/send-data-replay-target");
const { createMetrics } = require("../../src/observability/metrics");

test("outbound adapters expose the application port methods they implement", () => {
  const metrics = createMetrics();
  const redis = redisStub();

  const auditLog: AuditSinkPort = createAuditLogWriter({
    enabled: false,
    format: "json",
    path: path.join(os.tmpdir(), "recorder-ingress-port-conformance", "audit.log"),
  }, metrics);
  const auditStdout: AuditSinkPort = createAuditStdoutWriter({
    enabled: false,
    format: "json",
  }, metrics, { write() {} });
  const redisAudit: AuditSinkPort = createRedisAuditEventStore({
    listKey: "vitalserver:audit_events",
    maxLen: 0,
  }, redis, metrics);
  const spoolStore: SendDataSpoolStorePort = createRedisSendDataSpoolStore(spoolConfig(), redis);
  const vrIdentityStore: VrIdentityStorePort = createVrIdentityStore(redis, metrics);
  const replayTarget: SendDataReplayTargetPort = createSocketIoSendDataReplayTarget(replayTargetConfig());

  assertPortMethods(auditLog, ["write"]);
  assertPortMethods(auditStdout, ["write"]);
  assertPortMethods(redisAudit, ["write"]);
  assertPortMethods(spoolStore, ["append", "claim", "requeue", "markReplayed", "deadLetter"]);
  assertPortMethods(vrIdentityStore, ["setRecorderIp"]);
  assertPortMethods(replayTarget, ["send"]);
});

test("send_data replay target port reports invalid spool item without probing upstream", async () => {
  const replayTarget: SendDataReplayTargetPort = createSocketIoSendDataReplayTarget(replayTargetConfig());

  const result = await replayTarget.send({ id: "senddata_missing_payload" });

  assert.deepStrictEqual(result, {
    ok: false,
    reason: "invalid_payload",
    message: "send_data spool item has no payloadBase64",
  });
});

test("redis spool store port preserves append dependency failure as explicit failure", async () => {
  const spoolStore: SendDataSpoolStorePort = createRedisSendDataSpoolStore(spoolConfig(), {
    command(args, callback) {
      callback(new Error(`redis ${args[0]} failed`));
    },
  });

  const result = await spoolStore.append(spoolItem());

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.error.message, "redis RPUSH failed");
});

function assertPortMethods(port, methodNames) {
  for (const methodName of methodNames) {
    assert.strictEqual(typeof port[methodName], "function", `${methodName} must be a function`);
  }
}

function redisStub() {
  return {
    command(args, callback = (_error, _reply) => {}) {
      callback(null, args[0] === "GET" ? "127.0.0.1" : 1);
    },
  };
}

function replayTargetConfig() {
  return {
    upstream: { host: "127.0.0.1", port: 1 },
    spool: {
      replay: {
        targetTimeoutMs: 1,
      },
    },
  };
}

function spoolConfig() {
  return {
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    inFlightListKey: "vitalserver:recorder_ingress:send_data:in_flight",
    replayedListKey: "vitalserver:recorder_ingress:send_data:replayed",
    deadLetterListKey: "vitalserver:recorder_ingress:send_data:dead_letter",
  };
}

function spoolItem(): SendDataSpoolItem {
  return {
    schemaVersion: 1,
    id: "senddata_test",
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
