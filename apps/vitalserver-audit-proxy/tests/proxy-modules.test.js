"use strict";

const assert = require("assert");
const test = require("node:test");
const zlib = require("zlib");
const { auditEventTypes } = require("../src/audit-events");
const { createClientIpSelector } = require("../src/client-ip");
const { createSocketIoAuditor } = require("../src/socketio-auditor");

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
  const auditor = createSocketIoAuditor({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    redis: { command: (args, callback) => { commands.push(args); if (callback) callback(); } },
    metrics: metrics(),
    config: { vitalServer: { ipWriteDelayMs: 0 } },
  });
  const context = contextFor("VR_A");

  auditor.inspect('42["join_vr","VR_A"]', "client", context);
  await new Promise((resolve) => setTimeout(resolve, 5));

  assert.strictEqual(context.joined_vrcode, "VR_A");
  assert.strictEqual(records[0].eventType, auditEventTypes.JOIN_VR);
  assert.strictEqual(records[0].fields.vrcode, "VR_A");
  assert.deepStrictEqual(commands[0], ["SET", "ip_VR_A", "172.31.0.152"]);
});

test("socket.io auditor summarizes send_data payload", () => {
  const records = [];
  const auditor = createSocketIoAuditor({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    redis: { command: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipWriteDelayMs: 0 } },
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
    bytes: Buffer.byteLength(payload),
    vrcode: "VR_A",
    version: "2.3.4",
    rooms_count: 2,
  });
});

test("socket.io auditor correlates req_cmd and dispatch", () => {
  const records = [];
  const auditor = createSocketIoAuditor({
    audit: { record: (eventType, fields) => records.push({ eventType, fields }) },
    redis: { command: () => {} },
    metrics: metrics(),
    config: { vitalServer: { ipWriteDelayMs: 0 } },
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
  return {
    socketIoEventsSeen: 0,
    socketIoParseFailures: 0,
    redisIpWriteFailures: 0,
  };
}
