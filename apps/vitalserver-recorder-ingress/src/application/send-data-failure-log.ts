import type { SendDataFailureLogEvent, SendDataFailureSinkPort } from "./ports/outbound/send-data-failure-sink-port";
import type { SendDataContext, SendDataPayloadSummary, SendDataSpoolItem } from "../domain/send-data-spool-types";

"use strict";

const crypto = require("crypto");

function recordSendDataFailure(
  sink: SendDataFailureSinkPort | null | undefined,
  input: {
    kind: string;
    reason: string;
    message: string;
    item?: SendDataSpoolItem | null;
    context?: SendDataContext | null;
    payloadSummary?: SendDataPayloadSummary | null;
    rawDocument?: string | null;
  }
) {
  if (!sink) return;
  try {
    sink.record(createSendDataFailureLogEvent(input));
  } catch (error) {
    console.error(
      "[recorder-ingress] send_data failure sink failed:",
      error && error.message ? error.message : String(error)
    );
  }
}

function createSendDataFailureLogEvent(input): SendDataFailureLogEvent {
  const item = input.item || null;
  const context = input.context || {};
  const payloadSummary = input.payloadSummary || {};
  const rawDocument = typeof input.rawDocument === "string"
    ? input.rawDocument
    : (item && typeof item.rawDocument === "string" ? item.rawDocument : null);
  const event: SendDataFailureLogEvent = {
    schemaVersion: 1,
    observedAt: new Date().toISOString(),
    kind: input.kind,
    reason: input.reason,
    message: input.message,
    itemId: item ? item.id : null,
    state: item ? item.state : null,
    vrcode: item ? item.vrcode : recorderCode(context, payloadSummary),
    connectionId: item ? item.connectionId : context.connection_id,
    requestId: item ? item.requestId : context.request_id,
    receivedAt: item ? item.receivedAt : null,
    payloadEncoding: item ? item.payloadEncoding : null,
    payloadBytes: item ? item.payloadBytes : numericPayloadBytes(payloadSummary),
    payloadSha256: item ? payloadSha256(item) : null,
    attemptCount: item ? item.attemptCount : undefined,
    lastAttemptAt: item ? item.lastAttemptAt : undefined,
    replayedAt: item ? item.replayedAt : undefined,
    deadLetteredAt: item ? item.deadLetteredAt : undefined,
  };
  if (rawDocument !== null) {
    event.rawDocumentBytes = Buffer.byteLength(rawDocument);
    event.rawDocumentSha256 = sha256(Buffer.from(rawDocument));
  }
  return event;
}

function payloadSha256(item: SendDataSpoolItem) {
  if (!item || !item.payloadBase64) return null;
  try {
    return sha256(Buffer.from(item.payloadBase64, "base64"));
  } catch (_error) {
    return null;
  }
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function numericPayloadBytes(payloadSummary) {
  return Number.isFinite(payloadSummary && payloadSummary.bytes)
    ? Math.floor(payloadSummary.bytes)
    : 0;
}

function recorderCode(context: SendDataContext, payloadSummary: SendDataPayloadSummary) {
  if (payloadSummary && payloadSummary.vrcode) return String(payloadSummary.vrcode);
  if (context && context.joined_vrcode) return String(context.joined_vrcode);
  return null;
}

module.exports = {
  createSendDataFailureLogEvent,
  recordSendDataFailure,
};
