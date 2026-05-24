"use strict";

const http = require("http");
const net = require("net");
const crypto = require("crypto");

const listenPort = numberEnv("AUDIT_PROXY_PORT", 8080);
const upstreamHost = process.env.AUDIT_PROXY_UPSTREAM_HOST || "app";
const upstreamPort = numberEnv("AUDIT_PROXY_UPSTREAM_PORT", 80);
const redisHost = process.env.VITALSERVER_REDIS_HOST || process.env.AUDIT_PROXY_REDIS_HOST || "redis";
const redisPort = numberEnv("VITALSERVER_REDIS_PORT", numberEnv("AUDIT_PROXY_REDIS_PORT", 6379));
const auditEnabled = process.env.VITALSERVER_AUDIT_ENABLED !== "0";
const auditListKey = process.env.VITALSERVER_AUDIT_REDIS_LIST || "vitalserver:audit_events";
const auditMaxLen = numberEnv("VITALSERVER_AUDIT_REDIS_MAXLEN", 10000);
const trustProxy = /^(1|true|yes)$/i.test(process.env.VITALSERVER_TRUST_PROXY || "1");
const ipWriteDelayMs = numberEnv("AUDIT_PROXY_IP_WRITE_DELAY_MS", 250);
const maxBodyBytes = numberEnv("AUDIT_PROXY_MAX_BODY_BYTES", 5 * 1024 * 1024);
const sensitiveKeyPattern = /(password|passwd|pw|token|secret|authorization|cookie|session|key)/i;

let auditWriteFailures = 0;
let redisIpWriteFailures = 0;
let activeWebSockets = 0;

function numberEnv(name, fallback) {
  const value = Number.parseInt(process.env[name] || "", 10);
  return Number.isFinite(value) ? value : fallback;
}

function normalizeIp(value) {
  if (!value) return "";
  let next = String(value).split(",")[0].trim();
  if (next.startsWith("for=")) {
    const match = next.match(/for="?\[?([^\]";,]+)\]?/i);
    next = match ? match[1] : next;
  }
  if (next.startsWith("::ffff:")) next = next.slice(7);
  if (next.startsWith("[") && next.endsWith("]")) next = next.slice(1, -1);
  return next;
}

function forwardedFor(headers) {
  const forwarded = headers.forwarded || "";
  if (!forwarded) return "";
  const match = String(forwarded).split(",")[0].match(/for="?\[?([^\]";,]+)\]?/i);
  return match ? match[1] : "";
}

function selectedIp(req) {
  const headers = req.headers || {};
  const remote = normalizeIp(req.socket && req.socket.remoteAddress);
  const candidates = [
    ["x-forwarded-for", headers["x-forwarded-for"]],
    ["x-real-ip", headers["x-real-ip"]],
    ["forwarded", forwardedFor(headers)],
    ["x-client-ip", headers["x-client-ip"]],
  ];

  if (trustProxy) {
    for (const [source, value] of candidates) {
      const ip = normalizeIp(value);
      if (ip) {
        return { selected_ip: ip, selected_source: source, remote_address: remote, trust_proxy: true };
      }
    }
  }

  return { selected_ip: remote, selected_source: "remote-address", remote_address: remote, trust_proxy: trustProxy };
}

function mask(value, depth = 0) {
  if (depth > 8) return "[depth-limit]";
  if (value == null) return value;
  if (Buffer.isBuffer(value)) return `[buffer:${value.length}]`;
  if (Array.isArray(value)) return value.map((item) => mask(item, depth + 1));
  if (typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value)) {
      out[key] = sensitiveKeyPattern.test(key) ? "[masked]" : mask(value[key], depth + 1);
    }
    return out;
  }
  if (typeof value === "string" && value.length > 2000) return `${value.slice(0, 2000)}...[truncated]`;
  return value;
}

function audit(eventType, fields) {
  if (!auditEnabled) return;
  const payload = {
    schema_version: 1,
    source: "vitalserver-audit-proxy",
    event_type: eventType,
    ts: new Date().toISOString(),
    ts_unix_ms: Date.now(),
    ...mask(fields || {}),
  };
  const line = JSON.stringify(payload);
  redisCommand(["RPUSH", auditListKey, line], (error) => {
    if (error) {
      auditWriteFailures += 1;
      console.error("[audit-proxy] audit redis write failed:", error.message);
      return;
    }
    if (auditMaxLen > 0) redisCommand(["LTRIM", auditListKey, String(-auditMaxLen), "-1"]);
  });
}

function redisCommand(args, callback) {
  const socket = net.createConnection({ host: redisHost, port: redisPort });
  let settled = false;
  let data = "";
  const done = (error) => {
    if (settled) return;
    settled = true;
    socket.destroy();
    if (callback) callback(error || null);
  };
  socket.setTimeout(1500);
  socket.on("connect", () => socket.write(encodeResp(args)));
  socket.on("data", (chunk) => {
    data += chunk.toString("utf8");
    if (data[0] === "-") done(new Error(data.slice(1).trim()));
    else if (data.length > 0) done();
  });
  socket.on("error", done);
  socket.on("timeout", () => done(new Error("redis command timeout")));
}

function encodeResp(args) {
  return `*${args.length}\r\n${args.map((arg) => {
    const value = Buffer.from(String(arg));
    return `$${value.length}\r\n${value.toString()}\r\n`;
  }).join("")}`;
}

function writeVrIp(vrcode, ipInfo) {
  if (!vrcode || !ipInfo || !ipInfo.selected_ip) return;
  setTimeout(() => {
    redisCommand(["SET", `ip_${vrcode}`, ipInfo.selected_ip], (error) => {
      if (error) {
        redisIpWriteFailures += 1;
        console.error("[audit-proxy] ip write failed:", error.message);
      }
    });
  }, ipWriteDelayMs);
}

function requestContext(req) {
  return {
    request_id: crypto.randomUUID(),
    method: req.method,
    url: req.url,
    ip: selectedIp(req),
  };
}

function proxyHttp(req, res) {
  if (req.url === "/audit-proxy/health") {
    res.writeHead(204);
    res.end();
    return;
  }
  if (req.url === "/audit-proxy/status") {
    const body = JSON.stringify({ activeWebSockets, auditWriteFailures, redisIpWriteFailures });
    res.writeHead(200, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
    res.end(body);
    return;
  }

  const context = requestContext(req);
  const chunks = [];
  let size = 0;
  req.on("data", (chunk) => {
    size += chunk.length;
    if (size <= maxBodyBytes) chunks.push(chunk);
  });
  req.on("end", () => {
    const body = Buffer.concat(chunks);
    inspectEngineIoPayload(body.toString("utf8"), "client", context);
    const headers = { ...req.headers, host: req.headers.host || upstreamHost };
    const upstream = http.request(
      { host: upstreamHost, port: upstreamPort, method: req.method, path: req.url, headers },
      (upstreamRes) => {
        const responseChunks = [];
        let responseSize = 0;
        upstreamRes.on("data", (chunk) => {
          responseSize += chunk.length;
          if (responseSize <= maxBodyBytes) responseChunks.push(chunk);
          res.write(chunk);
        });
        upstreamRes.on("end", () => {
          inspectEngineIoPayload(Buffer.concat(responseChunks).toString("utf8"), "server", context);
          res.end();
        });
        res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);
      }
    );
    upstream.on("error", (error) => {
      res.writeHead(502, { "content-type": "text/plain" });
      res.end("upstream error\n");
      audit("proxy_error", { request_id: context.request_id, message: error.message });
    });
    if (body.length > 0) upstream.write(body);
    upstream.end();
  });
}

function proxyUpgrade(req, socket, head) {
  const context = requestContext(req);
  const upstream = net.createConnection({ host: upstreamHost, port: upstreamPort }, () => {
    upstream.write(upgradeRequestBytes(req));
    if (head && head.length > 0) upstream.write(head);
    activeWebSockets += 1;
    socket.pipe(upstream);
    upstream.pipe(socket);
  });
  const clientParser = createWebSocketParser((message) => inspectEngineIoPayload(message, "client", context));
  const serverParser = createWebSocketParser((message) => inspectEngineIoPayload(message, "server", context));
  let serverHandshake = Buffer.alloc(0);
  let serverHandshakeDone = false;
  socket.on("data", (chunk) => clientParser.push(chunk));
  upstream.on("data", (chunk) => {
    if (serverHandshakeDone) {
      serverParser.push(chunk);
      return;
    }
    serverHandshake = Buffer.concat([serverHandshake, chunk]);
    const headerEnd = serverHandshake.indexOf("\r\n\r\n");
    if (headerEnd < 0) return;
    serverHandshakeDone = true;
    const rest = serverHandshake.slice(headerEnd + 4);
    serverHandshake = Buffer.alloc(0);
    if (rest.length > 0) serverParser.push(rest);
  });
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    activeWebSockets = Math.max(0, activeWebSockets - 1);
    socket.destroy();
    upstream.destroy();
  };
  socket.on("error", close);
  upstream.on("error", close);
  socket.on("close", close);
  upstream.on("close", close);
}

function upgradeRequestBytes(req) {
  const lines = [`${req.method} ${req.url} HTTP/${req.httpVersion}`];
  for (const [name, value] of Object.entries(req.headers)) {
    if (Array.isArray(value)) for (const item of value) lines.push(`${name}: ${item}`);
    else lines.push(`${name}: ${value}`);
  }
  return `${lines.join("\r\n")}\r\n\r\n`;
}

function createWebSocketParser(onText) {
  let buffer = Buffer.alloc(0);
  return {
    push(chunk) {
      buffer = Buffer.concat([buffer, chunk]);
      while (buffer.length >= 2) {
        const first = buffer[0];
        const second = buffer[1];
        const opcode = first & 0x0f;
        const masked = Boolean(second & 0x80);
        let len = second & 0x7f;
        let offset = 2;
        if (len === 126) {
          if (buffer.length < offset + 2) return;
          len = buffer.readUInt16BE(offset);
          offset += 2;
        } else if (len === 127) {
          if (buffer.length < offset + 8) return;
          const high = buffer.readUInt32BE(offset);
          const low = buffer.readUInt32BE(offset + 4);
          len = high * 2 ** 32 + low;
          offset += 8;
        }
        const maskOffset = offset;
        if (masked) offset += 4;
        if (buffer.length < offset + len) return;
        let payload = buffer.slice(offset, offset + len);
        if (masked) {
          const maskKey = buffer.slice(maskOffset, maskOffset + 4);
          payload = Buffer.from(payload.map((byte, index) => byte ^ maskKey[index % 4]));
        }
        if (opcode === 1) onText(payload.toString("utf8"));
        buffer = buffer.slice(offset + len);
      }
    },
  };
}

function inspectEngineIoPayload(payload, direction, context) {
  if (!payload || typeof payload !== "string") return;
  for (const packet of splitEngineIoPayload(payload)) {
    inspectSocketIoPacket(packet, direction, context);
  }
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

function inspectSocketIoPacket(packet, direction, context) {
  if (!packet.startsWith("42")) return;
  const start = packet.indexOf("[");
  if (start < 0) return;
  let data;
  try {
    data = JSON.parse(packet.slice(start));
  } catch {
    return;
  }
  if (!Array.isArray(data) || typeof data[0] !== "string") return;
  const event = data[0];
  const payload = data[1];

  if (direction === "client" && event === "join_vr") {
    const vrcode = String(payload || "");
    audit("join_vr", { request_id: context.request_id, vrcode, ...context.ip });
    writeVrIp(vrcode, context.ip);
    return;
  }

  if (direction === "client" && event === "send_data") {
    audit("send_data", { request_id: context.request_id, payload_summary: summarizeSendData(payload) });
    return;
  }

  if (direction === "client" && event === "req_cmd") {
    audit("req_cmd", {
      request_id: context.request_id,
      command_job: commandJob(payload),
      target_vrcode: targetVrcode(payload),
      payload,
    });
    return;
  }

  if (direction === "server" && isDispatchEvent(event)) {
    audit("command_dispatch", {
      request_id: context.request_id,
      dispatch_event: event,
      payload,
    });
  }
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
    out[decodeURIComponent(rawKey.replace(/\+/g, " "))] = decodeURIComponent(rawValue.replace(/\+/g, " "));
  }
  return out;
}

function summarizeSendData(payload) {
  if (typeof payload !== "string") return { payload_type: typeof payload };
  return { payload_type: "string", bytes: Buffer.byteLength(payload) };
}

function isDispatchEvent(event) {
  return ["update", "del_bed", "restart", "reboot", "add_event", "edit_bed", "edit_conf"].includes(event);
}

const server = http.createServer(proxyHttp);
server.on("upgrade", proxyUpgrade);
server.listen(listenPort, () => {
  console.log(`[audit-proxy] listening on :${listenPort}, upstream=${upstreamHost}:${upstreamPort}, redis=${redisHost}:${redisPort}`);
});
