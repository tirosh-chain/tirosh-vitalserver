import type { IncomingMessage, Server } from "http";
import type { Socket } from "net";
import type { AuditRecorderPort } from "../../../application/ports/inbound/audit-recorder-port";
import type { SendDataRawArchiveExportWorkerPort } from "../../../application/ports/inbound/send-data-raw-archive-export-worker-port";
import type { SendDataReplayWorkerPort } from "../../../application/ports/inbound/send-data-replay-worker-port";
import type { SocketIoAuditPort } from "../../../application/ports/inbound/socketio-audit-port";
import type { NativeVitalUploadService } from "../../../application/native-vital-upload-service";
import type {
  createRecorderObservabilityIngressService,
} from "../../../application/recorder-observability-ingress-service";
import type { RecorderObservabilityRepositoryPort } from "../../../application/ports/outbound/recorder-observability-repository-port";

"use strict";

const http = require("http");
const net = require("net");
const crypto = require("crypto");
const { auditEventTypes } = require("../../../domain/audit-event-contracts");
const { metricsSnapshot, recordRecorderDisconnect } = require("../../../observability/metrics");
const { createBodyMirror } = require("./body-mirror");
const { createClientWebSocketRelay, shouldSuppressSendDataRelay } = require("./websocket-client-relay");
const { nativeVitalUploadMetadataFromHeaders } = require("./native-vital-upload-http");
const {
  receiveRecorderObservabilityExpectationCommand,
  recorderObservabilityExpectationCommandRoute,
} = require("./recorder-observability-expectation-http");
const {
  receiveRecorderObservability,
  recorderObservabilityRoute,
} = require("./recorder-observability-http");
const {
  readRecorderObservabilityQuery,
  recorderObservabilityQueryRoute,
} = require("./recorder-observability-query-http");
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
  observability: {
    maxRequestBytes: number;
    expectationCommandMaxBytes: number;
    expectationControl: {
      state: "loaded" | "unavailable";
      token: string | null;
      reason: string | null;
    };
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
  nativeVitalUploads?: NativeVitalUploadService;
  recorderObservability?: ReturnType<
    typeof createRecorderObservabilityIngressService
  >;
  recorderObservabilityRepository?: RecorderObservabilityRepositoryPort;
  recorderObservabilityProjector?: {
    start(): void;
    stop(): Promise<void>;
    runOnce(): Promise<number>;
  };
};

export type RecorderIngressHttpServer = Server & {
  prepareStartup?: () => Promise<unknown>;
  prepareShutdown?: () => Promise<unknown>;
};

function createRecorderIngressHttpServer({
  audit,
  clientIp,
  config,
  metrics,
  sendDataRawArchiveExportWorker,
  sendDataReplayWorker,
  socketIoAudit,
  nativeVitalUploads,
  recorderObservability,
  recorderObservabilityRepository,
  recorderObservabilityProjector,
}: RecorderIngressHttpServerDependencies): RecorderIngressHttpServer {
  let ready = !recorderObservabilityRepository;
  const dependencies = {
    audit,
    clientIp,
    config,
    metrics,
    nativeVitalUploads,
    recorderObservability,
    recorderObservabilityRepository,
    ready: () => ready,
    sendDataRawArchiveExportWorker,
    socketIoAudit,
  };
  const activeSockets = new Set<Socket>();
  const server: RecorderIngressHttpServer = http.createServer((req, res) => proxyHttp(req, res, dependencies));
  server.on("connection", (socket) => {
    activeSockets.add(socket);
    socket.on("close", () => activeSockets.delete(socket));
  });
  server.on("upgrade", (req, socket, head) => proxyUpgrade(req, socket, head, dependencies));
  server.on("listening", () => {
    nativeVitalUploads?.start();
    sendDataReplayWorker.start();
    sendDataRawArchiveExportWorker.start();
    recorderObservabilityProjector?.start();
  });
  server.on("close", () => {
    nativeVitalUploads?.stop();
    sendDataReplayWorker.stop();
    sendDataRawArchiveExportWorker.stop();
  });
  server.prepareStartup = async () => {
    if (!recorderObservabilityRepository) return { state: "disabled" };
    await recorderObservabilityRepository.ping();
    await recorderObservabilityProjector?.runOnce();
    ready = true;
    return { state: "ready" };
  };
  server.prepareShutdown = async () => {
    nativeVitalUploads?.stop();
    sendDataReplayWorker.stop();
    sendDataRawArchiveExportWorker.stop();
    await recorderObservabilityProjector?.stop();
    for (const socket of activeSockets) {
      socket.destroy();
    }
    await waitForActiveSocketsToClose(activeSockets, 250);
    const exportResult = await sendDataRawArchiveExportWorker.runOnce({
      trigger: "shutdown",
    });
    await recorderObservabilityRepository?.close();
    ready = false;
    return exportResult;
  };
  return server;
}

function waitForActiveSocketsToClose(activeSockets: Set<Socket>, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve) => {
    const poll = () => {
      if (activeSockets.size === 0 || Date.now() >= deadline) {
        resolve(null);
        return;
      }
      setTimeout(poll, 10);
    };
    poll();
  });
}

function proxyHttp(req, res, dependencies) {
  if (recorderObservabilityExpectationCommandRoute(req.url)) {
    receiveRecorderObservabilityExpectationCommand(req, res, {
      repository: dependencies.recorderObservabilityRepository,
      credential: dependencies.config.observability.expectationControl,
      maxRequestBytes:
        dependencies.config.observability.expectationCommandMaxBytes,
    });
    return;
  }
  const queryRoute = recorderObservabilityQueryRoute(req.url);
  if (queryRoute) {
    void readRecorderObservabilityQuery(
      req,
      res,
      queryRoute,
      dependencies.recorderObservabilityRepository,
    );
    return;
  }
  const observabilityRoute = recorderObservabilityRoute(req.url);
  if (observabilityRoute) {
    const selectedIp = dependencies.clientIp.select(req);
    receiveRecorderObservability(req, res, {
      route: observabilityRoute,
      ingress: dependencies.recorderObservability,
      maxRequestBytes: dependencies.config.observability.maxRequestBytes,
      metrics: dependencies.metrics.recorderObservability,
      sourceIp: typeof selectedIp.selected_ip === "string"
        ? selectedIp.selected_ip
        : "",
    });
    return;
  }
  if (req.url === "/recorder-ingress/health") {
    res.writeHead(dependencies.ready?.() === false ? 503 : 204);
    res.end();
    return;
  }
  if (req.url === "/recorder-ingress/status") {
    const body = JSON.stringify(metricsSnapshot(dependencies.metrics));
    res.writeHead(200, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
    res.end(body);
    return;
  }
  if (req.method === "POST" && req.url === "/recorder-ingress/raw-archive/finalize") {
    requestRawArchiveFinalization(req, res, dependencies.sendDataRawArchiveExportWorker);
    return;
  }
  if (req.method === "GET" && rawArchiveFinalizationStatusRequest(req.url)) {
    readRawArchiveFinalizationStatus(req, res, dependencies.sendDataRawArchiveExportWorker);
    return;
  }
  if (req.method === "GET" && nativeVitalUploadListRequest(req.url)) {
    readNativeVitalUploads(req, res, dependencies.nativeVitalUploads);
    return;
  }
  if (
    req.method === "POST"
    && (requestPath(req.url) === "/upload" || requestPath(req.url) === "/upload_vital.php")
  ) {
    let metadata;
    try {
      metadata = nativeVitalUploadMetadataFromHeaders(req.headers);
    } catch (error) {
      req.resume();
      writeJson(res, 400, {
        ok: false,
        state: "rejected",
        reason: "native_upload_metadata_invalid",
        message: errorMessage(error),
      });
      return;
    }
    if (metadata) {
      if (!dependencies.nativeVitalUploads) {
        req.resume();
        writeJson(res, 503, {
          ok: false,
          state: "failed",
          reason: "native_upload_tracking_unavailable",
          message: "Native vital upload tracking is unavailable.",
        });
        return;
      }
      proxyTrackedNativeVitalUpload(
        req,
        res,
        metadata,
        dependencies,
      );
      return;
    }
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

function nativeVitalUploadListRequest(requestURL) {
  return requestPath(requestURL)
    === "/recorder-ingress/vital-files/uploads";
}

function requestPath(requestURL) {
  return new URL(requestURL || "/", "http://recorder-ingress").pathname;
}

function readNativeVitalUploads(req, res, service) {
  if (!service) {
    writeJson(res, 503, {
      state: "readFailed",
      uploads: [],
      readError: "Native vital upload registry is unavailable.",
    });
    return;
  }
  try {
    const requestURL = new URL(req.url || "/", "http://recorder-ingress");
    const bedName = requestURL.searchParams.get("bedName");
    const declaredVrcode = requestURL.searchParams.get("declaredVrcode");
    const uploads = service.list().filter((upload) => (
      (bedName === null || upload.bedName === bedName)
      && (
        declaredVrcode === null
        || upload.declaredVrcode === declaredVrcode
      )
    ));
    writeJson(res, 200, {
      state: "loaded",
      uploads,
      readError: null,
    });
  } catch (error) {
    writeJson(res, 503, {
      state: "readFailed",
      uploads: [],
      readError: errorMessage(error),
    });
  }
}

function proxyTrackedNativeVitalUpload(
  req,
  res,
  metadata,
  { audit, clientIp, config, metrics, nativeVitalUploads },
) {
  let beginResult;
  try {
    beginResult = nativeVitalUploads.begin(metadata);
  } catch (error) {
    req.resume();
    writeJson(res, errorMessage(error).includes("conflict") ? 409 : 503, {
      ok: false,
      state: "rejected",
      reason: "native_upload_not_started",
      message: errorMessage(error),
    });
    return;
  }
  if (beginResult.kind === "alreadyIndexed") {
    req.resume();
    res.writeHead(200, {
      "content-type": "text/plain",
      "x-vital-upload-state": "indexed",
    });
    res.end("success");
    return;
  }

  const context = createRequestContext(req, clientIp);
  metrics.httpRequests += 1;
  const headers = {
    ...req.headers,
    host: req.headers.host || config.upstream.host,
  };
  let settled = false;
  const upstream = http.request(
    {
      host: config.upstream.host,
      port: config.upstream.port,
      method: req.method,
      path: req.url,
      headers,
    },
    (upstreamRes) => {
      const chunks: Buffer[] = [];
      let responseBytes = 0;
      upstreamRes.on("data", (chunk) => {
        responseBytes += chunk.length;
        if (responseBytes <= 65536) chunks.push(chunk);
      });
      upstreamRes.on("error", (error) => {
        completeUpstreamFailure(error);
      });
      upstreamRes.on("end", () => {
        if (settled) return;
        settled = true;
        if (responseBytes > 65536) {
          nativeVitalUploads.recordUpstreamFailure(
            metadata.uploadId,
            new Error("VitalServer upload response exceeds 65536 bytes"),
          );
          writeJson(res, 502, {
            ok: false,
            state: "failed",
            reason: "upstream_response_too_large",
            message: "VitalServer upload response exceeds 65536 bytes.",
          });
          return;
        }
        const responseBody = Buffer.concat(chunks).toString("utf8");
        try {
          const record = nativeVitalUploads.recordUpstreamResult(
            metadata.uploadId,
            {
              statusCode: upstreamRes.statusCode || 502,
              responseBody,
            },
          );
          res.writeHead(upstreamRes.statusCode || 502, {
            ...upstreamRes.headers,
            "x-vital-upload-state": record.state,
          });
          res.end(responseBody);
          if (record.state === "reconciling") {
            nativeVitalUploads.runReconciliationOnce().catch((error) => {
              console.error(
                "[recorder-ingress] immediate native upload reconciliation failed:",
                errorMessage(error),
              );
            });
          }
        } catch (error) {
          writeJson(res, 503, {
            ok: false,
            state: "failed",
            reason: "native_upload_registry_failed",
            message: errorMessage(error),
          });
        }
      });
    },
  );
  upstream.setTimeout(
    config.upstream.timeoutMs,
    () => upstream.destroy(new Error("upstream timeout")),
  );
  upstream.on("error", completeUpstreamFailure);
  req.on("aborted", () => {
    if (settled) return;
    settled = true;
    nativeVitalUploads.recordClientFailure(
      metadata.uploadId,
      new Error("Recorder upload request was aborted"),
    );
    upstream.destroy();
  });
  req.on("error", (error) => {
    if (settled) return;
    settled = true;
    nativeVitalUploads.recordClientFailure(metadata.uploadId, error);
    audit.record(auditEventTypes.PROXY_ERROR, {
      request_id: context.request_id,
      message: error.message,
      side: "client-request",
    });
    upstream.destroy(error);
  });
  req.pipe(upstream);

  function completeUpstreamFailure(error) {
    if (settled) return;
    settled = true;
    try {
      nativeVitalUploads.recordUpstreamFailure(metadata.uploadId, error);
    } catch (registryError) {
      console.error(
        "[recorder-ingress] native upload failure persistence failed:",
        errorMessage(registryError),
      );
    }
    audit.record(auditEventTypes.PROXY_ERROR, {
      request_id: context.request_id,
      message: errorMessage(error),
      side: "upstream-upload",
    });
    if (!res.headersSent) {
      writeJson(res, 502, {
        ok: false,
        state: "failed",
        reason: "upstream_upload_failed",
        message: errorMessage(error),
      });
    } else {
      res.end();
    }
  }
}

function rawArchiveFinalizationStatusRequest(requestURL) {
  return new URL(requestURL || "/", "http://recorder-ingress").pathname
    === "/recorder-ingress/raw-archive/finalizations";
}

function requestRawArchiveFinalization(req, res, worker) {
  const chunks: Buffer[] = [];
  let bytes = 0;
  req.on("data", (chunk) => {
    bytes += chunk.length;
    if (bytes <= 65536) chunks.push(chunk);
  });
  req.on("end", async () => {
    if (bytes > 65536) {
      writeJson(res, 413, { ok: false, state: "rejected", reason: "request_too_large", message: "raw archive finalization request exceeds 65536 bytes" });
      return;
    }
    let input;
    try {
      input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch (_error) {
      writeJson(res, 400, { ok: false, state: "rejected", reason: "invalid_json", message: "raw archive finalization request must be a JSON object" });
      return;
    }
    try {
      const result = await worker.requestFinalization(input);
      writeJson(res, result.ok ? 202 : 409, result);
    } catch (error) {
      writeJson(res, 503, {
        ok: false,
        state: "rejected",
        reason: "finalization_dependency_failed",
        message: error && error.message ? error.message : String(error),
      });
    }
  });
}

function readRawArchiveFinalizationStatus(req, res, worker) {
  const requestURL = new URL(req.url || "/", "http://recorder-ingress");
  try {
    const result = worker.finalizationStatus(requestURL.searchParams.getAll("requestId"));
    writeJson(res, result.ok ? 200 : 400, result);
  } catch (error) {
    writeJson(res, 503, {
      ok: false,
      state: "rejected",
      reason: "finalization_status_dependency_failed",
      message: error && error.message ? error.message : String(error),
    });
  }
}

function writeJson(res, statusCode, document) {
  const body = JSON.stringify(document);
  res.writeHead(statusCode, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
  res.end(body);
}

function errorMessage(error) {
  return error && error.message ? error.message : String(error);
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
