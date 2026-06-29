"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  filterClientSocketIoSendDataPayload,
  sendDataPacketInfo,
} = require("../../src/domain/socketio-send-data-filter");

test("socket.io send_data filter passes non send_data client event", () => {
  const payload = '42["join_vr","VR_A"]';

  assert.deepStrictEqual(filterClientSocketIoSendDataPayload(payload), {
    action: "pass",
    payload,
    dropBinaryAttachments: 0,
  });
});

test("socket.io send_data filter drops text send_data event", () => {
  assert.deepStrictEqual(filterClientSocketIoSendDataPayload('42["send_data","payload"]'), {
    action: "drop",
    payload: null,
    dropBinaryAttachments: 0,
  });
});

test("socket.io send_data filter drops binary send_data placeholder and asks relay to drop attachment", () => {
  assert.deepStrictEqual(filterClientSocketIoSendDataPayload('451-["send_data",{"_placeholder":true,"num":0}]'), {
    action: "drop",
    payload: null,
    dropBinaryAttachments: 1,
  });
});

test("socket.io send_data filter removes send_data from composite Engine.IO payload", () => {
  const join = '42["join_vr","VR_A"]';
  const sendData = '42["send_data","payload"]';
  const reqCmd = '42["req_cmd","job=restart_vr&vrcode=VR_A"]';
  const payload = `${join.length}:${join}${sendData.length}:${sendData}${reqCmd.length}:${reqCmd}`;

  const result = filterClientSocketIoSendDataPayload(payload);

  assert.strictEqual(result.action, "replace");
  assert.strictEqual(result.payload, `${join.length}:${join}${reqCmd.length}:${reqCmd}`);
  assert.strictEqual(result.dropBinaryAttachments, 0);
});

test("socket.io send_data packet info counts binary attachments explicitly", () => {
  assert.deepStrictEqual(sendDataPacketInfo('452-["send_data",{"_placeholder":true,"num":0}]'), {
    isSendData: true,
    binaryAttachmentCount: 2,
  });
});
