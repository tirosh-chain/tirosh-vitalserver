"use strict";

const assert = require("assert");
const test = require("node:test");
const { createAuditRecorder } = require("../../src/application/audit-recorder");
const { auditEventTypes } = require("../../src/domain/audit-event-contracts");
const { formatAuditLogLine } = require("../../src/infrastructure/file/audit-log-format");
const { createAuditStdoutWriter } = require("../../src/infrastructure/process/audit-stdout-writer");

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
