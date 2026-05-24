"use strict";

const zlib = require("zlib");

function summarizeSendData(payload) {
  if (typeof payload !== "string") return { payload_type: typeof payload };
  const summary = { payload_type: "string", bytes: Buffer.byteLength(payload) };
  try {
    const decoded = zlib.inflateSync(Buffer.from(payload, "binary")).toString();
    const document = JSON.parse(decoded.replace("/[\0-\u001f\u007f]/u", "").replace("nan", '""'));
    summary.vrcode = document.vrcode;
    summary.version = document.ver;
    summary.rooms_count = document.rooms && typeof document.rooms === "object"
      ? Object.keys(document.rooms).length
      : 0;
  } catch (error) {
    summary.decode_error = error.message;
  }
  return summary;
}

module.exports = { summarizeSendData };
