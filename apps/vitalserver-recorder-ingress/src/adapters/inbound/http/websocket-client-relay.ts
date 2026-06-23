"use strict";

const { sendDataIngressModes } = require("../../../domain/send-data-ingress-contracts");
const { filterClientSocketIoSendDataPayload } = require("../../../domain/socketio-send-data-filter");
const { encodeWebSocketFrame, readFrame } = require("./websocket-parser");

function createClientWebSocketRelay({ mode, onFrame }) {
  let buffer = Buffer.alloc(0);
  let suppressedBinaryAttachments = 0;
  const suppressSendData = mode === sendDataIngressModes.SPOOL_ONLY
    || mode === sendDataIngressModes.SPOOL_AND_REPLAY;

  return {
    push(chunk) {
      buffer = Buffer.concat([buffer, chunk]);
      const writes = [];
      while (buffer.length >= 2) {
        const frame = readFrame(buffer);
        if (!frame) break;
        if (frame.opcode === 1 || frame.opcode === 2) {
          onFrame(frame.payload, frame.opcode);
        }
        const relayed = relayFrame(frame, suppressSendData, {
          get suppressedBinaryAttachments() {
            return suppressedBinaryAttachments;
          },
          set suppressedBinaryAttachments(value) {
            suppressedBinaryAttachments = value;
          },
        });
        if (relayed) writes.push(relayed);
        buffer = buffer.slice(frame.nextOffset);
      }
      return writes;
    },
  };
}

function relayFrame(frame, suppressSendData, state) {
  if (!suppressSendData) return frame.rawFrame;
  if (frame.opcode === 1) {
    const filtered = filterClientSocketIoSendDataPayload(frame.payload.toString("utf8"));
    state.suppressedBinaryAttachments += filtered.dropBinaryAttachments;
    if (filtered.action === "drop") return null;
    if (filtered.action === "replace") {
      return encodeWebSocketFrame(filtered.payload, frame.opcode, { mask: true });
    }
    return frame.rawFrame;
  }
  if (frame.opcode === 2 && state.suppressedBinaryAttachments > 0) {
    state.suppressedBinaryAttachments -= 1;
    return null;
  }
  return frame.rawFrame;
}

function shouldSuppressSendDataRelay(mode) {
  return mode === sendDataIngressModes.SPOOL_ONLY
    || mode === sendDataIngressModes.SPOOL_AND_REPLAY;
}

module.exports = {
  createClientWebSocketRelay,
  shouldSuppressSendDataRelay,
};
