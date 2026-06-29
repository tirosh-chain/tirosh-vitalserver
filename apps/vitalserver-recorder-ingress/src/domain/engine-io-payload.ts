"use strict";

function splitEngineIoPayload(payload) {
  const packets = [];
  let i = 0;
  while (i < payload.length) {
    const colon = payload.indexOf(":", i);
    if (colon > i && /^\d+$/.test(payload.slice(i, colon))) {
      const len = Number.parseInt(payload.slice(i, colon), 10);
      const start = colon + 1;
      packets.push(payload.slice(start, start + len));
      i = start + len;
    } else {
      packets.push(payload.slice(i));
      break;
    }
  }
  return packets;
}

module.exports = { splitEngineIoPayload };
