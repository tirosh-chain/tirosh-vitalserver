"use strict";

const zlib = require("zlib");

const dispatchEvents = new Set(["update", "del_bed", "restart", "reboot", "add_event", "edit_bed", "edit_conf"]);

function createSocketIoAuditor({ audit, redis, metrics, config }) {
  return {
    inspect(payload, direction, context, options = {}) {
      if (!payload || typeof payload !== "string") return;
      for (const packet of splitEngineIoPayload(payload)) {
        inspectSocketIoPacket(packet, direction, context, options, { audit, redis, metrics, config });
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

  if (direction === "client" && event === "join_vr") {
    recordJoinVr(payload, context, options, dependencies);
    return;
  }

  if (direction === "client" && event === "send_data") {
    dependencies.audit.record("send_data", {
      request_id: context.request_id,
      connection_id: context.connection_id,
      vrcode: context.joined_vrcode || undefined,
      truncated: Boolean(options.truncated),
      payload_summary: summarizeSendData(payload),
    });
    return;
  }

  if (direction === "client" && event === "req_cmd") {
    const command = {
      job: commandJob(payload),
      target_vrcode: targetVrcode(payload),
    };
    context.last_command = command;
    dependencies.audit.record("req_cmd", {
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
    dependencies.audit.record("command_dispatch", {
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

function recordJoinVr(payload, context, options, { audit, redis, metrics, config }) {
  const vrcode = String(payload || "");
  context.joined_vrcode = vrcode;
  audit.record("join_vr", {
    request_id: context.request_id,
    connection_id: context.connection_id,
    vrcode,
    truncated: Boolean(options.truncated),
    ...context.ip,
  });
  writeVrIp(vrcode, context.ip, { redis, metrics, delayMs: config.vitalServer.ipWriteDelayMs });
}

function writeVrIp(vrcode, ipInfo, { redis, metrics, delayMs }) {
  if (!vrcode || !ipInfo || !ipInfo.selected_ip) return;
  setTimeout(() => {
    redis.command(["SET", `ip_${vrcode}`, ipInfo.selected_ip], (error) => {
      if (error) {
        metrics.redisIpWriteFailures += 1;
        console.error("[audit-proxy] ip write failed:", error.message);
      }
    });
  }, delayMs);
}

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

function commandJob(payload) {
  const parsed = parseMaybeQuery(payload);
  return parsed && parsed.job ? parsed.job : undefined;
}

function targetVrcode(payload) {
  const parsed = parseMaybeQuery(payload);
  return parsed && (parsed.vrcode || parsed["dev-setting-vrcode"]);
}

function parseMaybeQuery(value) {
  if (value && typeof value === "object") return value;
  if (typeof value !== "string") return {};
  const out = {};
  for (const part of value.split("&")) {
    const [rawKey, rawValue = ""] = part.split("=");
    if (!rawKey) continue;
    try {
      out[decodeURIComponent(rawKey.replace(/\+/g, " "))] = decodeURIComponent(rawValue.replace(/\+/g, " "));
    } catch {
      out[rawKey] = rawValue;
    }
  }
  return out;
}

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

module.exports = { createSocketIoAuditor };
