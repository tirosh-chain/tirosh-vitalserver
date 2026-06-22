"use strict";

const assert = require("assert");
const test = require("node:test");
const zlib = require("zlib");
const { createSocketIoAuditService } = require("../../src/application/socketio-audit-service");
const { auditEventTypes } = require("../../src/domain/audit-event-contracts");
const {
  metricsSnapshot,
  recordRecorderDisconnect,
} = require("../../src/observability/metrics");
const { contextFor, metrics } = require("../helpers");

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

test("socket.io auditor mirrors text send_data to ingress service", async () => {
  const records = [];
  const spooled = [];
  const auditor = createSocketIoAuditService({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
    sendDataIngress: {
      record: (payload, context, payloadSummary) => {
        spooled.push({ payload, context, payloadSummary });
        return Promise.resolve({ ok: true, outcome: "spooled" });
      },
    },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";
  const payload = zlib.deflateSync(JSON.stringify({
    vrcode: "VR_A",
    ver: "2.3.4",
    rooms: { a: {} },
  })).toString("binary");

  auditor.inspect(`42["send_data",${JSON.stringify(payload)}]`, "client", context);
  await new Promise((resolve) => setImmediate(resolve));

  assert.strictEqual(records[0].eventType, auditEventTypes.SEND_DATA);
  assert.strictEqual(spooled.length, 1);
  assert.strictEqual(spooled[0].payload, payload);
  assert.strictEqual(spooled[0].context.connection_id, "connection-1");
  assert.strictEqual(spooled[0].payloadSummary.vrcode, "VR_A");
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

test("socket.io auditor mirrors binary send_data attachments to ingress service", async () => {
  const spooled = [];
  const auditor = createSocketIoAuditService({
    audit: { record: () => {} },
    vrIdentityStore: { setRecorderIp: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipRewrite: { enabled: true, verifyDelaysMs: [] } } },
    sendDataIngress: {
      record: (payload, context, payloadSummary) => {
        spooled.push({ payload, context, payloadSummary });
        return Promise.resolve({ ok: true, outcome: "spooled" });
      },
    },
  });
  const context = contextFor("VR_A");
  context.joined_vrcode = "VR_A";
  const payload = zlib.deflateSync(JSON.stringify({
    vrcode: "VR_A",
    ver: "2.3.4",
    rooms: { a: {}, b: {} },
  }));

  auditor.inspect('451-["send_data",{"_placeholder":true,"num":0}]', "client", context);
  auditor.inspectBinary(payload, "client", context);
  await new Promise((resolve) => setImmediate(resolve));

  assert.strictEqual(spooled.length, 1);
  assert.strictEqual(spooled[0].payload, payload);
  assert.strictEqual(spooled[0].payloadSummary.payload_type, "buffer");
  assert.strictEqual(spooled[0].payloadSummary.rooms_count, 2);
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
