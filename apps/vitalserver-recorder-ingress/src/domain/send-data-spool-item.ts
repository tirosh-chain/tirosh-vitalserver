"use strict";

const crypto = require("crypto");
const {
  sendDataFailureReasons,
  sendDataSpoolItemStates,
} = require("./send-data-ingress-contracts");

type SendDataSpoolItemOptions = {
  now?: () => Date;
  idFactory?: () => string;
};

function createSendDataSpoolItem(payload, context, payloadSummary, options: SendDataSpoolItemOptions = {}) {
  const buffer = payloadBuffer(payload);
  if (!buffer) {
    return invalid("send_data payload is not a string or buffer");
  }

  const vrcode = recorderCode(context, payloadSummary);
  if (!vrcode) {
    return invalid("send_data payload has no vrcode and no joined recorder context");
  }

  const now = options.now || (() => new Date());
  const idFactory = options.idFactory || (() => `senddata_${crypto.randomUUID()}`);

  return {
    ok: true,
    item: {
      schemaVersion: 1,
      id: idFactory(),
      state: sendDataSpoolItemStates.PENDING,
      vrcode,
      connectionId: context && context.connection_id,
      requestId: context && context.request_id,
      receivedAt: now().toISOString(),
      payloadEncoding: Buffer.isBuffer(payload) ? "binary" : "string",
      payloadBytes: buffer.length,
      payloadBase64: buffer.toString("base64"),
      payloadSummary: payloadSummary || null,
      attemptCount: 0,
      lastAttemptAt: null,
      lastFailure: null,
    },
  };
}

function payloadBuffer(payload) {
  if (Buffer.isBuffer(payload)) return payload;
  if (typeof payload === "string") return Buffer.from(payload, "binary");
  return null;
}

function recorderCode(context, payloadSummary) {
  if (payloadSummary && payloadSummary.vrcode) return String(payloadSummary.vrcode);
  if (context && context.joined_vrcode) return String(context.joined_vrcode);
  return "";
}

function invalid(message) {
  return {
    ok: false,
    reason: sendDataFailureReasons.INVALID_PAYLOAD,
    message,
  };
}

module.exports = { createSendDataSpoolItem, payloadBuffer };
