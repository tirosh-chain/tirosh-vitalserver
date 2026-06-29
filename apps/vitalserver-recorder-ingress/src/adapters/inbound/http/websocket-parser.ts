"use strict";

type WebSocketFrameEncodeOptions = {
  mask?: boolean;
  maskKey?: Buffer;
};

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

  return {
    opcode,
    payload,
    rawFrame: buffer.slice(0, offset + len),
    nextOffset: offset + len,
  };
}

function encodeWebSocketFrame(payload, opcode, options: WebSocketFrameEncodeOptions = {}) {
  const buffer = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload), "utf8");
  const mask = Boolean(options.mask);
  const length = buffer.length;
  const lengthBytes = length < 126 ? 0 : length <= 0xffff ? 2 : 8;
  const headerLength = 2 + lengthBytes + (mask ? 4 : 0);
  const frame = Buffer.alloc(headerLength + length);
  frame[0] = 0x80 | (opcode & 0x0f);

  let offset = 2;
  if (length < 126) {
    frame[1] = length | (mask ? 0x80 : 0);
  } else if (length <= 0xffff) {
    frame[1] = 126 | (mask ? 0x80 : 0);
    frame.writeUInt16BE(length, offset);
    offset += 2;
  } else {
    frame[1] = 127 | (mask ? 0x80 : 0);
    frame.writeUInt32BE(Math.floor(length / 2 ** 32), offset);
    frame.writeUInt32BE(length >>> 0, offset + 4);
    offset += 8;
  }

  if (mask) {
    const maskKey = options.maskKey || Buffer.from([0x12, 0x34, 0x56, 0x78]);
    maskKey.copy(frame, offset);
    offset += 4;
    for (let index = 0; index < length; index += 1) {
      frame[offset + index] = buffer[index] ^ maskKey[index % 4];
    }
  } else {
    buffer.copy(frame, offset);
  }

  return frame;
}

module.exports = { createWebSocketParser, encodeWebSocketFrame, readFrame };
