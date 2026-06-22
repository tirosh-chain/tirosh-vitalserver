"use strict";

const { commandRequestFromPayload } = require("../domain/command-request");
const { splitEngineIoPayload } = require("../domain/engine-io-payload");
const { summarizeSendData } = require("../domain/send-data-summary");
const {
  auditEventTypes,
  clientSocketEvents,
  serverDispatchEventNames,
} = require("../domain/audit-event-contracts");
const { recordRecorderJoin, recordSendDataObserved } = require("../observability/metrics");

const dispatchEvents = new Set(serverDispatchEventNames);

function createSocketIoAuditService({ audit, vrIdentityStore, metrics, config, sendDataIngress }) {
  return {
    inspect(payload, direction, context, options = {}) {
      if (!payload || typeof payload !== "string") return;
      for (const packet of splitEngineIoPayload(payload)) {
        inspectSocketIoPacket(packet, direction, context, options, { audit, vrIdentityStore, metrics, config, sendDataIngress });
      }
    },
    inspectBinary(payload, direction, context, options = {}) {
      if (direction !== "client" || !context.pending_binary_event) return;
      const pending = context.pending_binary_event;
      context.pending_binary_event = null;
      if (pending.event !== clientSocketEvents.SEND_DATA) return;
      recordSendData(socketIoBinaryAttachmentPayload(payload), context, options, { audit, metrics, sendDataIngress });
    },
  };
}

function inspectSocketIoPacket(packet, direction, context, options, dependencies) {
  const isBinaryEvent = packet.startsWith("45");
  if (!packet.startsWith("42") && !isBinaryEvent) return;
  const start = packet.indexOf("[");
  if (start < 0) return;

  let data;
  try {
    data = JSON.parse(packet.slice(start));
  } catch {
    dependencies.metrics.socketIoParseFailures += 1;
    return;
  }
  if (!Array.isArray(data) || typeof data[0] !== "string") return;

  dependencies.metrics.socketIoEventsSeen += 1;
  const event = data[0];
  const payload = data[1];

  if (direction === "client" && event === clientSocketEvents.JOIN_VR) {
    recordJoinVr(payload, context, options, dependencies);
    return;
  }

  if (direction === "client" && event === clientSocketEvents.SEND_DATA) {
    if (isBinaryEvent) {
      context.pending_binary_event = { event };
      return;
    }
    recordSendData(payload, context, options, dependencies);
    return;
  }

  if (direction === "client" && event === clientSocketEvents.REQ_CMD) {
    const command = commandRequestFromPayload(payload);
    context.last_command = command;
    dependencies.audit.record(auditEventTypes.REQ_CMD, {
      request_id: context.request_id,
      connection_id: context.connection_id,
      command_job: command.job,
      target_vrcode: command.target_vrcode,
      truncated: Boolean(options.truncated),
      payload,
    });
    return;
  }

  if (direction === "server" && dispatchEvents.has(event)) {
    dependencies.audit.record(auditEventTypes.COMMAND_DISPATCH, {
      request_id: context.request_id,
      connection_id: context.connection_id,
      target_vrcode: context.joined_vrcode || undefined,
      command_job: context.last_command ? context.last_command.job : undefined,
      dispatch_event: event,
      truncated: Boolean(options.truncated),
      payload,
    });
  }
}

function recordSendData(payload, context, options, { audit, metrics, sendDataIngress }) {
  const payloadSummary = summarizeSendData(payload);
  const vrcode = context.joined_vrcode || payloadSummary.vrcode || undefined;
  recordSendDataObserved(metrics, vrcode, payloadSummary);
  if (sendDataIngress) {
    Promise.resolve(sendDataIngress.record(payload, context, payloadSummary)).catch((error) => {
      console.error("[recorder-ingress] send_data spool failed unexpectedly:", error.message);
    });
  }
  audit.record(auditEventTypes.SEND_DATA, {
    request_id: context.request_id,
    connection_id: context.connection_id,
    vrcode,
    truncated: Boolean(options.truncated),
    payload_summary: payloadSummary,
  });
}

function socketIoBinaryAttachmentPayload(payload) {
  if (!Buffer.isBuffer(payload) || payload.length === 0) return payload;
  const engineIoMessagePacketType = 0x04;
  if (payload[0] !== engineIoMessagePacketType) return payload;
  return payload.subarray(1);
}

function recordJoinVr(payload, context, options, { audit, vrIdentityStore, metrics, config }) {
  const vrcode = String(payload || "");
  context.joined_vrcode = vrcode;
  recordRecorderJoin(metrics, context, vrcode, context.ip && context.ip.selected_ip);
  audit.record(auditEventTypes.JOIN_VR, {
    request_id: context.request_id,
    connection_id: context.connection_id,
    vrcode,
    truncated: Boolean(options.truncated),
    ...context.ip,
  });
  vrIdentityStore.setRecorderIp(vrcode, context.ip && context.ip.selected_ip, config.vitalServer.ipRewrite);
}

module.exports = { createSocketIoAuditService, socketIoBinaryAttachmentPayload };
