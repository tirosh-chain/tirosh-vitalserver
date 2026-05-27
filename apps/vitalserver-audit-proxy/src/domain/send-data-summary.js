"use strict";

const zlib = require("zlib");

function summarizeSendData(payload) {
  const buffer = Buffer.isBuffer(payload)
    ? payload
    : typeof payload === "string"
      ? Buffer.from(payload, "binary")
      : null;
  if (!buffer) return { payload_type: typeof payload };

  const summary = {
    payload_type: Buffer.isBuffer(payload) ? "buffer" : "string",
    bytes: buffer.length,
  };
  try {
    const decoded = zlib.inflateSync(buffer).toString();
    const document = JSON.parse(
      decoded.replace(/[\0-\u001f\u007f]/gu, "").replace(/\bnan\b/g, '""')
    );
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
