"use strict";

const assert = require("assert");
const test = require("node:test");
const { createClientWebSocketRelay } = require("../../src/infrastructure/http/websocket-client-relay");
const { encodeWebSocketFrame, readFrame } = require("../../src/infrastructure/http/websocket-parser");

test("websocket client relay passes all frames in mirror_spool mode", () => {
  const observed = [];
  const relay = createClientWebSocketRelay({
    mode: "mirror_spool",
    onFrame: (payload, opcode) => observed.push({ payload: payload.toString("utf8"), opcode }),
  });
  const frame = clientFrame('42["send_data","payload"]', 1);

  const writes = relay.push(frame);

  assert.strictEqual(writes.length, 1);
  assert.deepStrictEqual(writes[0], frame);
  assert.deepStrictEqual(observed, [{ payload: '42["send_data","payload"]', opcode: 1 }]);
});

test("websocket client relay drops text send_data in spool_and_replay mode", () => {
  const observed = [];
  const relay = createClientWebSocketRelay({
    mode: "spool_and_replay",
    onFrame: (payload, opcode) => observed.push({ payload: payload.toString("utf8"), opcode }),
  });

  const writes = relay.push(clientFrame('42["send_data","payload"]', 1));

  assert.deepStrictEqual(writes, []);
  assert.deepStrictEqual(observed, [{ payload: '42["send_data","payload"]', opcode: 1 }]);
});

test("websocket client relay drops binary send_data placeholder and following binary attachment", () => {
  const observed = [];
  const relay = createClientWebSocketRelay({
    mode: "spool_only",
    onFrame: (payload, opcode) => observed.push({ payload, opcode }),
  });

  const writes = relay.push(Buffer.concat([
    clientFrame('451-["send_data",{"_placeholder":true,"num":0}]', 1),
    clientFrame(Buffer.from("binary-payload"), 2),
    clientFrame('42["join_vr","VR_A"]', 1),
  ]));

  assert.strictEqual(writes.length, 1);
  assert.strictEqual(readFrame(writes[0]).payload.toString("utf8"), '42["join_vr","VR_A"]');
  assert.strictEqual(observed.length, 3);
  assert.strictEqual(observed[0].payload.toString("utf8"), '451-["send_data",{"_placeholder":true,"num":0}]');
  assert.strictEqual(observed[1].payload.toString("utf8"), "binary-payload");
});

test("websocket client relay rewrites composite Engine.IO payload without send_data", () => {
  const relay = createClientWebSocketRelay({
    mode: "spool_and_replay",
    onFrame: () => {},
  });
  const join = '42["join_vr","VR_A"]';
  const sendData = '42["send_data","payload"]';
  const reqCmd = '42["req_cmd","job=restart_vr&vrcode=VR_A"]';
  const payload = `${join.length}:${join}${sendData.length}:${sendData}${reqCmd.length}:${reqCmd}`;

  const writes = relay.push(clientFrame(payload, 1));

  assert.strictEqual(writes.length, 1);
  const relayed = readFrame(writes[0]);
  assert.strictEqual(relayed.opcode, 1);
  assert.strictEqual(relayed.payload.toString("utf8"), `${join.length}:${join}${reqCmd.length}:${reqCmd}`);
});

test("websocket client relay buffers partial frames", () => {
  const relay = createClientWebSocketRelay({
    mode: "spool_and_replay",
    onFrame: () => {},
  });
  const frame = clientFrame('42["join_vr","VR_A"]', 1);

  assert.deepStrictEqual(relay.push(frame.slice(0, 3)), []);
  const writes = relay.push(frame.slice(3));

  assert.strictEqual(writes.length, 1);
  assert.strictEqual(readFrame(writes[0]).payload.toString("utf8"), '42["join_vr","VR_A"]');
});

function clientFrame(payload, opcode) {
  return encodeWebSocketFrame(payload, opcode, {
    mask: true,
    maskKey: Buffer.from([0x01, 0x02, 0x03, 0x04]),
  });
}
