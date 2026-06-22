"use strict";

const assert = require("assert");
const test = require("node:test");
const zlib = require("zlib");
const { createAuditRecorder } = require("../src/application/audit-recorder");
const { createSocketIoAuditService } = require("../src/application/socketio-audit-service");
const { loadConfig } = require("../src/config");
const { auditEventTypes } = require("../src/domain/audit-event-contracts");
const { formatAuditLogLine } = require("../src/infrastructure/file/audit-log-format");
const { createClientIpSelector } = require("../src/infrastructure/http/client-ip");
const { createAuditStdoutWriter } = require("../src/infrastructure/process/audit-stdout-writer");
const { parseRespReply } = require("../src/infrastructure/redis/client");
const { createVrIdentityStore } = require("../src/infrastructure/redis/vr-identity-store");
const {
  createMetrics,
  metricsSnapshot,
  recordRecorderDisconnect,
} = require("../src/observability/metrics");

test("client ip selector trusts forwarded headers only when enabled", () => {
  const req = {
    headers: { "x-forwarded-for": "172.31.0.152, 10.0.0.1" },
    socket: { remoteAddress: "::ffff:192.168.97.1" },
  };

  assert.deepStrictEqual(createClientIpSelector({ trustProxy: true }).select(req), {
    selected_ip: "172.31.0.152",
    selected_source: "x-forwarded-for",
    remote_address: "192.168.97.1",
    trust_proxy: true,
  });

  assert.deepStrictEqual(createClientIpSelector({ trustProxy: false }).select(req), {
    selected_ip: "192.168.97.1",
    selected_source: "remote-address",
    remote_address: "192.168.97.1",
    trust_proxy: false,
  });
});

test("socket.io auditor records join_vr and rewrites redis ip", async () => {
  const records = [];
  const commands = [];
  const metricState = metrics();
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: (vrcode, selectedIp) => commands.push(["SET", `ip_${vrcode}`, selectedIp]) },
    metrics: metricState,
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });
  const context = contextFor("VR_A");

  auditor.inspect('42["join_vr","VR_A"]', "client", context);
  await new Promise((resolve) => setTimeout(resolve, 5));

  assert.strictEqual(context.joined_vrcode, "VR_A");
  assert.strictEqual(records[0].eventType, auditEventTypes.JOIN_VR);
  assert.strictEqual(records[0].fields.vrcode, "VR_A");
  assert.deepStrictEqual(commands[0], ["SET", "ip_VR_A", "172.31.0.152"]);
  assert.strictEqual(metricsSnapshot(metricState).activeRecorderConnections, 1);
  const recorder = metricsSnapshot(metricState).recorders[0];
  assert.strictEqual(recorder.vrcode, "VR_A");
  assert.strictEqual(recorder.selectedIp, "172.31.0.152");
  assert.strictEqual(recorder.ipSource, "x-forwarded-for");
});

test("recorder metrics track active joins and disconnects", () => {
  const metricState = metrics();
  const context = contextFor();
  const auditor = createSocketIoAuditService({
    audit: { record: () => {} },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metricState,
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });

  auditor.inspect('42["join_vr","VR_A"]', "client", context);
  assert.strictEqual(metricsSnapshot(metricState).activeRecorderConnections, 1);

  recordRecorderDisconnect(metricState, context);
  const snapshot = metricsSnapshot(metricState);

  assert.strictEqual(snapshot.activeRecorderConnections, 0);
  assert.strictEqual(snapshot.recorders[0].activeConnections, 0);
});

test("socket.io auditor summarizes send_data payload", () => {
  const records = [];
  const metricState = metrics();
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metricState,
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";
  const payload = zlib.deflateSync(JSON.stringify({
    vrcode: "VR_A",
    ver: "2.3.4",
    rooms: { a: {}, b: {} },
  })).toString("binary");

  auditor.inspect(`42["send_data",${JSON.stringify(payload)}]`, "client", context);

  assert.strictEqual(records[0].eventType, auditEventTypes.SEND_DATA);
  assert.deepStrictEqual(records[0].fields.payload_summary, {
    payload_type: "string",
    bytes: Buffer.from(payload, "binary").length,
    vrcode: "VR_A",
    version: "2.3.4",
    rooms_count: 2,
  });
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.sendDataEventsObserved, 1);
  assert.strictEqual(snapshot.sendDataBytesObserved, Buffer.from(payload, "binary").length);
  assert.ok(snapshot.lastSendDataObservedAt);
  assert.strictEqual(snapshot.recorders[0].vrcode, "VR_A");
  assert.strictEqual(snapshot.recorders[0].sendDataEventsObserved, 1);
  assert.strictEqual(snapshot.recorders[0].sendDataBytesObserved, Buffer.from(payload, "binary").length);
  assert.ok(snapshot.recorders[0].lastSendDataObservedAt);
});

test("socket.io auditor summarizes binary send_data attachments", () => {
  const records = [];
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";
  const payload = zlib.deflateSync(JSON.stringify({
    vrcode: "VR_A",
    ver: "2.3.4",
    rooms: { a: {}, b: {}, c: {} },
  }));

  auditor.inspect('451-["send_data",{"_placeholder":true,"num":0}]', "client", context);
  auditor.inspectBinary(payload, "client", context);

  assert.strictEqual(records[0].eventType, auditEventTypes.SEND_DATA);
  assert.deepStrictEqual(records[0].fields.payload_summary, {
    payload_type: "buffer",
    bytes: payload.length,
    vrcode: "VR_A",
    version: "2.3.4",
    rooms_count: 3,
  });
});

test("socket.io auditor removes engine.io message prefix from binary send_data attachments", () => {
  const records = [];
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";
  const payload = zlib.deflateSync(JSON.stringify({
    vrcode: "VR_A",
    ver: "2.3.4",
    rooms: { a: {}, b: {}, c: {}, d: {} },
  }));
  const engineIoMessagePayload = Buffer.concat([Buffer.from([0x04]), payload]);

  auditor.inspect('451-["send_data",{"_placeholder":true,"num":0}]', "client", context);
  auditor.inspectBinary(engineIoMessagePayload, "client", context);

  assert.strictEqual(records[0].eventType, auditEventTypes.SEND_DATA);
  assert.deepStrictEqual(records[0].fields.payload_summary, {
    payload_type: "buffer",
    bytes: payload.length,
    vrcode: "VR_A",
    version: "2.3.4",
    rooms_count: 4,
  });
});

test("socket.io auditor preserves non-engine.io binary send_data decode failures", () => {
  const records = [];
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";
  const invalidPayload = Buffer.concat([Buffer.from([0x05]), Buffer.from("not-zlib")]);

  auditor.inspect('451-["send_data",{"_placeholder":true,"num":0}]', "client", context);
  auditor.inspectBinary(invalidPayload, "client", context);

  assert.strictEqual(records[0].eventType, auditEventTypes.SEND_DATA);
  assert.deepStrictEqual(records[0].fields.payload_summary, {
    payload_type: "buffer",
    bytes: invalidPayload.length,
    decode_error: "incorrect header check",
  });
});

test("socket.io auditor correlates req_cmd and dispatch", () => {
  const records = [];
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";

  auditor.inspect('42["req_cmd","job=restart_vr&vrcode=VR_A"]', "client", context);
  auditor.inspect('42["restart"]', "server", context);

  assert.strictEqual(records[0].eventType, auditEventTypes.REQ_CMD);
  assert.strictEqual(records[0].fields.command_job, "restart_vr");
  assert.strictEqual(records[1].eventType, auditEventTypes.COMMAND_DISPATCH);
  assert.strictEqual(records[1].fields.command_job, "restart_vr");
  assert.strictEqual(records[1].fields.target_vrcode, "VR_A");
});

test("redis parser returns bulk string values for verification", () => {
  assert.deepStrictEqual(parseRespReply("+OK\r\n"), { complete: true, value: "OK" });
  assert.deepStrictEqual(parseRespReply("$12\r\n172.31.0.152\r\n"), {
    complete: true,
    value: "172.31.0.152",
  });
  assert.deepStrictEqual(parseRespReply("$-1\r\n"), { complete: true, value: null });
  assert.deepStrictEqual(parseRespReply("$12\r\n172.31"), { complete: false });
});

test("config loads explicit redis ip rewrite policy", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_VR_IP_REWRITE_ENABLED: "0",
    RECORDER_INGRESS_VR_IP_VERIFY_DELAYS_MS: "10,250",
  }).vitalServer.ipRewrite, {
    enabled: false,
    verifyDelaysMs: [10, 250],
  });
});

test("vr identity store records disabled policy without writing redis", () => {
  const metricState = metrics();
  const calls = [];
  const redis = {
    command(args) {
      calls.push(args);
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: false, verifyDelaysMs: [0] });

  assert.deepStrictEqual(calls, []);
  const sync = metricsSnapshot(metricState).recorders[0].redisIpSync;
  assert.strictEqual(sync.status, "disabled");
  assert.strictEqual(sync.redisKey, "ip_VR_A");
  assert.strictEqual(sync.selectedIp, "172.31.0.152");
});

test("vr identity store verifies redis ip after writing", async () => {
  const metricState = metrics();
  const calls = [];
  const redis = {
    command(args, callback) {
      calls.push(args);
      if (args[0] === "GET") {
        callback(null, "172.31.0.152");
        return;
      }
      callback(null, "OK");
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: true, verifyDelaysMs: [0] });
  await new Promise((resolve) => setTimeout(resolve, 5));

  assert.deepStrictEqual(calls, [
    ["SET", "ip_VR_A", "172.31.0.152"],
    ["GET", "ip_VR_A"],
  ]);
  const sync = metricsSnapshot(metricState).recorders[0].redisIpSync;
  assert.strictEqual(sync.status, "verified");
  assert.strictEqual(sync.redisValue, "172.31.0.152");
});

test("vr identity store preserves verify failure state", async () => {
  const metricState = metrics();
  const redis = {
    command(args, callback) {
      if (args[0] === "GET") {
        callback(new Error("redis read failed"));
        return;
      }
      callback(null, "OK");
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: true, verifyDelaysMs: [0] });
  await new Promise((resolve) => setTimeout(resolve, 5));

  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.redisIpVerifyFailures, 1);
  assert.strictEqual(snapshot.recorders[0].redisIpSync.status, "verify_failed");
  assert.strictEqual(snapshot.recorders[0].redisIpSync.lastFailure, "redis read failed");
});

test("vr identity store rewrites mismatch and records bounded failure", async () => {
  const metricState = metrics();
  const calls = [];
  const redis = {
    command(args, callback) {
      calls.push(args);
      if (args[0] === "GET") {
        callback(null, "172.18.0.4");
        return;
      }
      callback(null, "OK");
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: true, verifyDelaysMs: [0, 1] });
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.deepStrictEqual(calls, [
    ["SET", "ip_VR_A", "172.31.0.152"],
    ["GET", "ip_VR_A"],
    ["SET", "ip_VR_A", "172.31.0.152"],
    ["GET", "ip_VR_A"],
    ["SET", "ip_VR_A", "172.31.0.152"],
  ]);
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.redisIpVerifyMismatches, 2);
  assert.strictEqual(snapshot.recorders[0].redisIpSync.status, "mismatch");
  assert.strictEqual(snapshot.recorders[0].redisIpSync.redisValue, "172.18.0.4");
});

test("audit recorder fans out masked event envelopes to sinks", () => {
  const events = [];
  const recorder = createAuditRecorder(
    { enabled: true },
    [{ write: (event) => events.push(event) }]
  );

  recorder.record(auditEventTypes.REQ_CMD, {
    request_id: "request-1",
    token: "secret",
    payload: { password: "secret", ok: true },
  });

  assert.strictEqual(events.length, 1);
  assert.strictEqual(events[0].schema_version, 1);
  assert.strictEqual(events[0].source, "vitalserver-recorder-ingress");
  assert.strictEqual(events[0].event_type, auditEventTypes.REQ_CMD);
  assert.strictEqual(events[0].token, "[masked]");
  assert.deepStrictEqual(events[0].payload, { password: "[masked]", ok: true });
});

test("audit file formatter supports json and logfmt", () => {
  const event = {
    schema_version: 1,
    event_type: "req_cmd",
    command_job: "restart_vr",
    payload: { vrcode: "VR_A" },
    message: "hello world",
  };

  assert.strictEqual(JSON.parse(formatAuditLogLine(event, "json")).event_type, "req_cmd");
  assert.strictEqual(
    formatAuditLogLine(event, "logfmt"),
    'command_job=restart_vr event_type=req_cmd message="hello world" payload="{\\"vrcode\\":\\"VR_A\\"}" schema_version=1\n'
  );
});

test("audit stdout writer emits collector-compatible lines", () => {
  const writes = [];
  const writer = createAuditStdoutWriter(
    { enabled: true, format: "logfmt" },
    { auditStdoutWriteFailures: 0 },
    { write: (line, callback) => { writes.push(line); callback(); } }
  );

  writer.write({ event_type: "join_vr", vrcode: "VR_A" });

  assert.deepStrictEqual(writes, ["event_type=join_vr vrcode=VR_A\n"]);
});

function contextFor(vrcode) {
  return {
    request_id: "request-1",
    connection_id: "connection-1",
    joined_vrcode: vrcode || null,
    last_command: null,
    ip: {
      selected_ip: "172.31.0.152",
      selected_source: "x-forwarded-for",
      remote_address: "192.168.97.1",
      trust_proxy: true,
    },
  };
}

function metrics() {
  return createMetrics();
}
