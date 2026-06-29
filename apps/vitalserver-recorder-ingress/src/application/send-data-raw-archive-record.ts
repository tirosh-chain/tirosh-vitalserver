import type { SendDataSpoolItem } from "../domain/send-data-spool-types";

"use strict";

const crypto = require("crypto");

function createSendDataRawArchiveRecord(item: SendDataSpoolItem, archivedAt = new Date().toISOString()) {
  return {
    schemaVersion: 1,
    kind: "send_data_raw_payload",
    archivedAt,
    itemId: item.id,
    state: item.state,
    vrcode: item.vrcode,
    connectionId: item.connectionId,
    requestId: item.requestId,
    receivedAt: item.receivedAt,
    payloadEncoding: item.payloadEncoding,
    payloadBytes: item.payloadBytes,
    payloadSha256: payloadSha256(item),
    payloadBase64: item.payloadBase64,
    payloadSummary: item.payloadSummary,
  };
}

function payloadSha256(item: SendDataSpoolItem) {
  if (!item || !item.payloadBase64) return null;
  try {
    return crypto.createHash("sha256").update(Buffer.from(item.payloadBase64, "base64")).digest("hex");
  } catch (_error) {
    return null;
  }
}

module.exports = { createSendDataRawArchiveRecord };
