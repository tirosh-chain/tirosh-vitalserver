"use strict";

const { commandRequestFromPayload } = require("../domain/command-request");
const { splitEngineIoPayload } = require("../domain/engine-io-payload");
const { summarizeSendData } = require("../domain/send-data-summary");
const {
  auditEventTypes,
  clientSocketEvents,
  serverDispatchEventNames,
} = require("../domain/audit-event-contracts");
const { recordRecorderJoin } = require("../observability/metrics");

const dispatchEvents = new Set(serverDispatchEventNames);

function createSocketIoAuditService({ audit, vrIdentityStore, metrics, config }) {
  return {
    inspect(payload, direction, context, options = {}) {
      if (!payload || typeof payload !== "string") return;
      for (const packet of splitEngineIoPayload(payload)) {
        inspectSocketIoPacket(packet, direction, context, options, { audit, vrIdentityStore, metrics, config });
      }
    },
  };
}

function inspectSocketIoPacket(packet, direction, context, options, dependencies) {
  if (!packet.startsWith("42")) return;
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
    dependencies.audit.record(auditEventTypes.SEND_DATA, {
      request_id: context.request_id,
      connection_id: context.connection_id,
      vrcode: context.joined_vrcode || undefined,
      truncated: Boolean(options.truncated),
      payload_summary: summarizeSendData(payload),
    });
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
  vrIdentityStore.setRecorderIp(vrcode, context.ip && context.ip.selected_ip, config.vitalServer.ipWriteDelayMs);
}

module.exports = { createSocketIoAuditService };
