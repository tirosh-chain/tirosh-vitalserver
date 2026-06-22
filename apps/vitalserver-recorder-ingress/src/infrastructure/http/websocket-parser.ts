"use strict";

function createWebSocketParser(onFrame) {
  let buffer = Buffer.alloc(0);

  return {
    push(chunk) {
      buffer = Buffer.concat([buffer, chunk]);
      while (buffer.length >= 2) {
        const frame = readFrame(buffer);
        if (!frame) return;
        if (frame.opcode === 1 || frame.opcode === 2) {
          onFrame(frame.payload, frame.opcode);
        }
        buffer = buffer.slice(frame.nextOffset);
      }
    },
  };
}

function readFrame(buffer) {
  const first = buffer[0];
  const second = buffer[1];
  const opcode = first & 0x0f;
  const masked = Boolean(second & 0x80);
  let len = second & 0x7f;
  let offset = 2;

  if (len === 126) {
    if (buffer.length < offset + 2) return null;
    len = buffer.readUInt16BE(offset);
    offset += 2;
  } else if (len === 127) {
    if (buffer.length < offset + 8) return null;
    const high = buffer.readUInt32BE(offset);
    const low = buffer.readUInt32BE(offset + 4);
    len = high * 2 ** 32 + low;
    offset += 8;
  }

  const maskOffset = offset;
  if (masked) offset += 4;
  if (buffer.length < offset + len) return null;

  let payload = buffer.slice(offset, offset + len);
  if (masked) {
    const maskKey = buffer.slice(maskOffset, maskOffset + 4);
    payload = Buffer.from(payload.map((byte, index) => byte ^ maskKey[index % 4]));
  }

  return { opcode, payload, nextOffset: offset + len };
}

module.exports = { createWebSocketParser };
