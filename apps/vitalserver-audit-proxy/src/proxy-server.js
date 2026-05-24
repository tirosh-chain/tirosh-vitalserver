"use strict";

const http = require("http");
const net = require("net");
const crypto = require("crypto");
const { auditEventTypes } = require("./audit-events");
const { createAuditRecorder } = require("./audit-recorder");
const { createBodyMirror } = require("./body-mirror");
const { createClientIpSelector } = require("./client-ip");
const { createMetrics, metricsSnapshot } = require("./metrics");
const { createRedisClient } = require("./redis-client");
const { createSocketIoAuditor } = require("./socketio-auditor");
const { createWebSocketParser } = require("./websocket-parser");

function createAuditProxyServer(config) {
  const metrics = createMetrics();
  const redis = createRedisClient(config.redis);
  const audit = createAuditRecorder(config.audit, redis, metrics);
  const clientIp = createClientIpSelector(config.clientIp);
  const socketIoAuditor = createSocketIoAuditor({ audit, redis, metrics, config });

  const dependencies = { audit, clientIp, config, metrics, socketIoAuditor };
  const server = http.createServer((req, res) => proxyHttp(req, res, dependencies));
  server.on("upgrade", (req, socket, head) => proxyUpgrade(req, socket, head, dependencies));
  return server;
}

function proxyHttp(req, res, dependencies) {
  if (req.url === "/audit-proxy/health") {
    res.writeHead(204);
    res.end();
    return;
  }
  if (req.url === "/audit-proxy/status") {
    const body = JSON.stringify(metricsSnapshot(dependencies.metrics));
    res.writeHead(200, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
    res.end(body);
    return;
  }

  const context = createRequestContext(req, dependencies.clientIp);
  dependencies.metrics.httpRequests += 1;

  const requestMirror = createBodyMirror(dependencies.config.audit.maxBodyBytes, (body, truncated) => {
    dependencies.socketIoAuditor.inspect(body.toString("utf8"), "client", context, { truncated });
  });
  const responseMirror = createBodyMirror(dependencies.config.audit.maxBodyBytes, (body, truncated) => {
    dependencies.socketIoAuditor.inspect(body.toString("utf8"), "server", context, { truncated });
  });

  const upstream = createUpstreamRequest(req, res, context, responseMirror, dependencies);
  req.on("data", (chunk) => {
    requestMirror.push(chunk);
    upstream.write(chunk);
  });
  req.on("end", () => {
    requestMirror.end();
    upstream.end();
  });
  req.on("error", (error) => {
    dependencies.audit.record(auditEventTypes.PROXY_ERROR, {
      request_id: context.request_id,
      message: error.message,
      side: "client-request",
    });
    upstream.destroy(error);
  });
}

function createUpstreamRequest(req, res, context, responseMirror, { audit, config }) {
  const headers = { ...req.headers, host: req.headers.host || config.upstream.host };
  const upstream = http.request(
    {
      host: config.upstream.host,
      port: config.upstream.port,
      method: req.method,
      path: req.url,
      headers,
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);
      upstreamRes.on("data", (chunk) => {
        responseMirror.push(chunk);
        res.write(chunk);
      });
      upstreamRes.on("end", () => {
        responseMirror.end();
        res.end();
      });
    }
  );
  upstream.setTimeout(config.upstream.timeoutMs, () => upstream.destroy(new Error("upstream timeout")));
  upstream.on("error", (error) => {
    audit.record(auditEventTypes.PROXY_ERROR, { request_id: context.request_id, message: error.message });
    if (!res.headersSent) {
      res.writeHead(502, { "content-type": "text/plain" });
    }
    res.end("upstream error\n");
  });
  return upstream;
}

function proxyUpgrade(req, socket, head, dependencies) {
  const context = createRequestContext(req, dependencies.clientIp);
  const upstream = net.createConnection(
    { host: dependencies.config.upstream.host, port: dependencies.config.upstream.port },
    () => {
      upstream.write(upgradeRequestBytes(req));
      if (head && head.length > 0) upstream.write(head);
      dependencies.metrics.activeWebSockets += 1;
      socket.pipe(upstream);
      upstream.pipe(socket);
    }
  );

  const clientParser = createWebSocketParser((message) => {
    dependencies.socketIoAuditor.inspect(message, "client", context);
  });
  const serverParser = createWebSocketParser((message) => {
    dependencies.socketIoAuditor.inspect(message, "server", context);
  });
  if (head && head.length > 0) clientParser.push(head);
  observeServerFramesAfterHandshake(upstream, serverParser);
  socket.on("data", (chunk) => clientParser.push(chunk));
  closeSocketsTogether(socket, upstream, dependencies.metrics);
}

function createRequestContext(req, clientIp) {
  return {
    request_id: crypto.randomUUID(),
    connection_id: crypto.randomUUID(),
    method: req.method,
    url: req.url,
    ip: clientIp.select(req),
    joined_vrcode: null,
    last_command: null,
  };
}

function upgradeRequestBytes(req) {
  const lines = [`${req.method} ${req.url} HTTP/${req.httpVersion}`];
  for (const [name, value] of Object.entries(req.headers)) {
    if (Array.isArray(value)) for (const item of value) lines.push(`${name}: ${item}`);
    else lines.push(`${name}: ${value}`);
  }
  return `${lines.join("\r\n")}\r\n\r\n`;
}

function observeServerFramesAfterHandshake(upstream, serverParser) {
  let handshake = Buffer.alloc(0);
  let done = false;
  upstream.on("data", (chunk) => {
    if (done) {
      serverParser.push(chunk);
      return;
    }
    handshake = Buffer.concat([handshake, chunk]);
    const headerEnd = handshake.indexOf("\r\n\r\n");
    if (headerEnd < 0) return;
    done = true;
    const rest = handshake.slice(headerEnd + 4);
    handshake = Buffer.alloc(0);
    if (rest.length > 0) serverParser.push(rest);
  });
}

function closeSocketsTogether(client, upstream, metrics) {
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    metrics.activeWebSockets = Math.max(0, metrics.activeWebSockets - 1);
    client.destroy();
    upstream.destroy();
  };
  client.on("error", close);
  upstream.on("error", close);
  client.on("close", close);
  upstream.on("close", close);
}

module.exports = { createAuditProxyServer };
