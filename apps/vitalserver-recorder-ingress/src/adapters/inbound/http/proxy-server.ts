import type { IncomingMessage, Server } from "http";
import type { AuditRecorderPort } from "../../../application/ports/inbound/audit-recorder-port";
import type { SendDataRawArchiveExportWorkerPort } from "../../../application/ports/inbound/send-data-raw-archive-export-worker-port";
import type { SendDataReplayWorkerPort } from "../../../application/ports/inbound/send-data-replay-worker-port";
import type { SocketIoAuditPort } from "../../../application/ports/inbound/socketio-audit-port";

"use strict";

const http = require("http");
const net = require("net");
const crypto = require("crypto");
const { auditEventTypes } = require("../../../domain/audit-event-contracts");
const { metricsSnapshot, recordRecorderDisconnect } = require("../../../observability/metrics");
const { createBodyMirror } = require("./body-mirror");
const { createClientWebSocketRelay, shouldSuppressSendDataRelay } = require("./websocket-client-relay");
const { createWebSocketParser } = require("./websocket-parser");

type ClientIpSelectorPort = {
  select(req: IncomingMessage): Record<string, unknown>;
};

type RecorderIngressHttpConfig = {
  upstream: {
    host: string;
    port: number;
    timeoutMs: number;
  };
  audit: {
    maxBodyBytes: number;
  };
  spool: {
    mode: string;
  };
};

type RecorderIngressHttpMetrics = {
  httpRequests: number;
  activeWebSockets: number;
  [key: string]: unknown;
};

type RecorderIngressHttpServerDependencies = {
  audit: AuditRecorderPort;
  clientIp: ClientIpSelectorPort;
  config: RecorderIngressHttpConfig;
  metrics: RecorderIngressHttpMetrics;
  sendDataRawArchiveExportWorker: SendDataRawArchiveExportWorkerPort;
  sendDataReplayWorker: SendDataReplayWorkerPort;
  socketIoAudit: SocketIoAuditPort;
};

function createRecorderIngressHttpServer({
  audit,
  clientIp,
  config,
  metrics,
  sendDataRawArchiveExportWorker,
  sendDataReplayWorker,
  socketIoAudit,
}: RecorderIngressHttpServerDependencies): Server {
  const dependencies = { audit, clientIp, config, metrics, socketIoAudit };
  const server = http.createServer((req, res) => proxyHttp(req, res, dependencies));
  server.on("upgrade", (req, socket, head) => proxyUpgrade(req, socket, head, dependencies));
  server.on("listening", () => {
    sendDataReplayWorker.start();
    sendDataRawArchiveExportWorker.start();
  });
  server.on("close", () => {
    sendDataReplayWorker.stop();
    sendDataRawArchiveExportWorker.stop();
  });
  return server;
}

function proxyHttp(req, res, dependencies) {
  if (req.url === "/recorder-ingress/health") {
    res.writeHead(204);
    res.end();
    return;
  }
  if (req.url === "/recorder-ingress/status") {
    const body = JSON.stringify(metricsSnapshot(dependencies.metrics));
    res.writeHead(200, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
    res.end(body);
    return;
  }

  const context = createRequestContext(req, dependencies.clientIp);
  dependencies.metrics.httpRequests += 1;

  const requestMirror = createBodyMirror(dependencies.config.audit.maxBodyBytes, (body, truncated) => {
    dependencies.socketIoAudit.inspect(body.toString("utf8"), "client", context, { truncated });
  });
  const responseMirror = createBodyMirror(dependencies.config.audit.maxBodyBytes, (body, truncated) => {
    dependencies.socketIoAudit.inspect(body.toString("utf8"), "server", context, { truncated });
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
  const suppressSendDataRelay = shouldSuppressSendDataRelay(dependencies.config.spool.mode);
  const upstream = net.createConnection(
    { host: dependencies.config.upstream.host, port: dependencies.config.upstream.port },
    () => {
      dependencies.metrics.activeWebSockets += 1;
      if (!suppressSendDataRelay) {
        socket.pipe(upstream);
      }
      upstream.pipe(socket);
      upstream.write(upgradeRequestBytes(req));
      if (head && head.length > 0) {
        if (suppressSendDataRelay) {
          for (const chunk of clientRelay.push(head)) upstream.write(chunk);
        } else {
          upstream.write(head);
        }
      }
    }
  );

  const inspectClientFrame = (payload, opcode) => {
    if (opcode === 1) {
      dependencies.socketIoAudit.inspect(payload.toString("utf8"), "client", context);
    } else if (opcode === 2) {
      dependencies.socketIoAudit.inspectBinary(payload, "client", context);
    }
  };
  const clientParser = createWebSocketParser(inspectClientFrame);
  const clientRelay = createClientWebSocketRelay({
    mode: dependencies.config.spool.mode,
    onFrame: inspectClientFrame,
  });
  const serverParser = createWebSocketParser((payload, opcode) => {
    if (opcode === 1) {
      dependencies.socketIoAudit.inspect(payload.toString("utf8"), "server", context);
    } else if (opcode === 2) {
      dependencies.socketIoAudit.inspectBinary(payload, "server", context);
    }
  });
  if (head && head.length > 0 && !suppressSendDataRelay) {
    clientParser.push(head);
  }
  observeServerFramesAfterHandshake(upstream, serverParser);
  if (suppressSendDataRelay) {
    socket.on("data", (chunk) => {
      for (const relayed of clientRelay.push(chunk)) upstream.write(relayed);
    });
  } else {
    socket.on("data", (chunk) => clientParser.push(chunk));
  }
  closeSocketsTogether(socket, upstream, dependencies.metrics, context);
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
    metrics_vrcode: null,
    pending_binary_event: null,
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

function closeSocketsTogether(client, upstream, metrics, context) {
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    metrics.activeWebSockets = Math.max(0, metrics.activeWebSockets - 1);
    recordRecorderDisconnect(metrics, context);
    client.destroy();
    upstream.destroy();
  };
  client.on("error", close);
  upstream.on("error", close);
  client.on("close", close);
  upstream.on("close", close);
}

module.exports = { createRecorderIngressHttpServer };
