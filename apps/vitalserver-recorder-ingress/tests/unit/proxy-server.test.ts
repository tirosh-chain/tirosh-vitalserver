"use strict";

const assert = require("assert");
const test = require("node:test");
const { createRecorderIngressHttpServer } = require("../../src/adapters/inbound/http/proxy-server");
const { createMetrics } = require("../../src/observability/metrics");

test("recorder ingress HTTP adapter starts and stops injected workers on server lifecycle", () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {
        calls.push("raw-start");
      },
      stop() {
        calls.push("raw-stop");
      },
      async runOnce() {
        return { ok: true, state: "disabled", disabled: true };
      },
      async requestFinalization() {
        return { ok: true, state: "accepted", requestIds: ["request-1"] };
      },
      finalizationStatus() {
        return finalizationStatus();
      },
    },
    sendDataReplayWorker: {
      start() {
        calls.push("replay-start");
      },
      stop() {
        calls.push("replay-stop");
      },
      async runOnce() {
        return { ok: true, processed: 0, disabled: true };
      },
    },
    socketIoAudit: {
      inspect() {},
      inspectBinary() {},
    },
  });

  server.emit("listening");
  server.emit("close");

  assert.deepStrictEqual(calls, ["replay-start", "raw-start", "replay-stop", "raw-stop"]);
});

test("recorder ingress HTTP adapter runs shutdown raw archive export trigger", async () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {
        calls.push("raw-start");
      },
      stop() {
        calls.push("raw-stop");
      },
      async runOnce(options) {
        calls.push(`raw-run:${options && options.trigger}`);
        return { ok: true, state: "uploaded" };
      },
      async requestFinalization() {
        return { ok: true, state: "accepted", requestIds: ["request-1"] };
      },
      finalizationStatus() {
        return finalizationStatus();
      },
    },
    sendDataReplayWorker: {
      start() {
        calls.push("replay-start");
      },
      stop() {
        calls.push("replay-stop");
      },
      async runOnce() {
        return { ok: true, processed: 0, disabled: true };
      },
    },
    socketIoAudit: {
      inspect() {},
      inspectBinary() {},
    },
  });

  const result = await server.prepareShutdown();

  assert.deepStrictEqual(result, { ok: true, state: "uploaded" });
  assert.deepStrictEqual(calls, ["replay-stop", "raw-stop", "raw-run:shutdown"]);
});

test("recorder ingress accepts explicit recorder archive finalization", async () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {},
      stop() {},
      async runOnce() { return { ok: true, state: "open" }; },
      async requestFinalization(input) {
        calls.push(input);
        return { ok: true, state: "accepted", requestIds: ["request-1"] };
      },
      finalizationStatus() {
        return finalizationStatus();
      },
    },
    sendDataReplayWorker: {
      start() {},
      stop() {},
      async runOnce() { return { ok: true, processed: 0 }; },
    },
    socketIoAudit: { inspect() {}, inspectBinary() {} },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const response = await fetch(`http://127.0.0.1:${address.port}/recorder-ingress/raw-archive/finalize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ vrcodes: ["LAB-VR-1"], reason: "lab_session_finished" }),
  });
  const body = await response.json();
  await new Promise((resolve) => server.close(resolve));

  assert.strictEqual(response.status, 202);
  assert.deepStrictEqual(body, { ok: true, state: "accepted", requestIds: ["request-1"] });
  assert.deepStrictEqual(calls, [{ vrcodes: ["LAB-VR-1"], reason: "lab_session_finished" }]);
});

test("recorder ingress exposes finalization progress by explicit request ID", async () => {
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {},
      stop() {},
      async runOnce() { return { ok: true, state: "open" }; },
      async requestFinalization() { return { ok: true, state: "accepted", requestIds: ["request-1"] }; },
      finalizationStatus(requestIds) {
        assert.deepStrictEqual(requestIds, ["request-1"]);
        return finalizationStatus();
      },
    },
    sendDataReplayWorker: {
      start() {},
      stop() {},
      async runOnce() { return { ok: true, processed: 0 }; },
    },
    socketIoAudit: { inspect() {}, inspectBinary() {} },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const response = await fetch(
    `http://127.0.0.1:${address.port}/recorder-ingress/raw-archive/finalizations?requestId=request-1`,
  );
  const body = await response.json();
  await new Promise((resolve) => server.close(resolve));

  assert.strictEqual(response.status, 200);
  assert.deepStrictEqual(body, finalizationStatus());
});

test("recorder ingress streams tracked native upload and records explicit bed metadata", async () => {
  const received = [];
  const upstreamServer = require("http").createServer((req, res) => {
    req.on("data", (chunk) => received.push(chunk));
    req.on("end", () => {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("success");
    });
  });
  await new Promise((resolve) => upstreamServer.listen(0, "127.0.0.1", resolve));
  const upstreamAddress = upstreamServer.address();
  const calls = [];
  const nativeVitalUploads = nativeUploadService(calls);
  const config = httpAdapterConfig();
  config.upstream = {
    host: "127.0.0.1",
    port: upstreamAddress.port,
    timeoutMs: 1000,
  };
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config,
    metrics: createMetrics(),
    nativeVitalUploads,
    sendDataRawArchiveExportWorker: inertRawArchiveWorker(),
    sendDataReplayWorker: inertReplayWorker(),
    socketIoAudit: { inspect() {}, inspectBinary() {} },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const requestBody = Buffer.from("--boundary\r\nbinary-vital-data\r\n--boundary--\r\n");

  const response = await fetch(`http://127.0.0.1:${address.port}/upload`, {
    method: "POST",
    headers: {
      "content-type": "multipart/form-data; boundary=boundary",
      "x-vital-upload-id": "upload-001",
      "x-vital-bed-name": "OR-01",
      "x-vital-filename": "OR-01_260723_100000.vital",
      "x-vital-file-size": "17",
    },
    body: requestBody,
  });
  const body = await response.text();
  await new Promise((resolve) => server.close(resolve));
  await new Promise((resolve) => upstreamServer.close(resolve));

  assert.strictEqual(response.status, 200);
  assert.strictEqual(body, "success");
  assert.strictEqual(response.headers.get("x-vital-upload-state"), "reconciling");
  assert.deepStrictEqual(Buffer.concat(received), requestBody);
  assert.deepStrictEqual(calls[0], ["begin", {
    uploadId: "upload-001",
    bedName: "OR-01",
    declaredVrcode: null,
    filename: "OR-01_260723_100000.vital",
    declaredSizeBytes: 17,
  }]);
  assert.deepStrictEqual(calls[1], ["upstream", "upload-001", {
    statusCode: 200,
    responseBody: "success",
  }]);
});

test("recorder ingress rejects tracked upload when tracking owner is unavailable", async () => {
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: inertRawArchiveWorker(),
    sendDataReplayWorker: inertReplayWorker(),
    socketIoAudit: { inspect() {}, inspectBinary() {} },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();

  const response = await fetch(`http://127.0.0.1:${address.port}/upload`, {
    method: "POST",
    headers: {
      "content-type": "multipart/form-data; boundary=boundary",
      "x-vital-upload-id": "upload-001",
      "x-vital-bed-name": "OR-01",
      "x-vital-filename": "OR-01_260723_100000.vital",
      "x-vital-file-size": "17",
    },
    body: Buffer.from("--boundary--\r\n"),
  });
  const body = await response.json();
  await new Promise((resolve) => server.close(resolve));

  assert.strictEqual(response.status, 503);
  assert.deepStrictEqual(body, {
    ok: false,
    state: "failed",
    reason: "native_upload_tracking_unavailable",
    message: "Native vital upload tracking is unavailable.",
  });
});

test("recorder ingress lists native upload receipts without creating recorder identity", async () => {
  const nativeVitalUploads = nativeUploadService([]);
  nativeVitalUploads.list = () => [{
    schemaVersion: 1,
    origin: "nativeRecorderUpload",
    uploadId: "upload-001",
    bedName: "OR-01",
    declaredVrcode: null,
    filename: "OR-01_260723_100000.vital",
    declaredSizeBytes: 17,
    state: "reconciling",
    receivedAt: "2026-07-23T10:00:00.000Z",
    upstreamAcceptedAt: "2026-07-23T10:00:01.000Z",
    indexedAt: null,
    reconciliationAttempts: 0,
    lastReconciliationAt: null,
    indexEvidence: null,
    failure: null,
  }];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    nativeVitalUploads,
    sendDataRawArchiveExportWorker: inertRawArchiveWorker(),
    sendDataReplayWorker: inertReplayWorker(),
    socketIoAudit: { inspect() {}, inspectBinary() {} },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();

  const response = await fetch(
    `http://127.0.0.1:${address.port}/recorder-ingress/vital-files/uploads?bedName=OR-01`,
  );
  const body = await response.json();
  await new Promise((resolve) => server.close(resolve));

  assert.strictEqual(response.status, 200);
  assert.strictEqual(body.state, "loaded");
  assert.strictEqual(body.uploads.length, 1);
  assert.strictEqual(body.uploads[0].declaredVrcode, null);
  assert.strictEqual(body.readError, null);
});

function finalizationStatus() {
  return {
    ok: true,
    state: "loaded",
    finalization: {
      state: "processing",
      requests: [{
        requestId: "request-1",
        vrcode: "LAB-VR-1",
        state: "processing",
        attempts: 1,
        maxAttempts: 3,
        requestedAt: "2026-07-16T05:00:00.000Z",
        updatedAt: "2026-07-16T05:00:01.000Z",
        startedAt: "2026-07-16T05:00:01.000Z",
        completedAt: null,
        nextAttemptAt: null,
        failure: null,
      }],
      updatedAt: "2026-07-16T05:00:01.000Z",
    },
  };
}

function httpAdapterConfig() {
  return {
    upstream: { host: "127.0.0.1", port: 1, timeoutMs: 1000 },
    audit: { maxBodyBytes: 1024 },
    spool: { mode: "mirror_spool" },
  };
}

function inertRawArchiveWorker() {
  return {
    start() {},
    stop() {},
    async runOnce() { return { ok: true, state: "open" }; },
    async requestFinalization() {
      return { ok: true, state: "accepted", requestIds: [] };
    },
    finalizationStatus() {
      return finalizationStatus();
    },
  };
}

function inertReplayWorker() {
  return {
    start() {},
    stop() {},
    async runOnce() { return { ok: true, processed: 0 }; },
  };
}

function nativeUploadService(calls) {
  return {
    start() {},
    stop() {},
    begin(metadata) {
      calls.push(["begin", metadata]);
      return {
        kind: "started",
        record: { state: "receiving" },
      };
    },
    recordClientFailure(uploadId, error) {
      calls.push(["client-failure", uploadId, error.message]);
      return { state: "failed" };
    },
    recordUpstreamFailure(uploadId, error) {
      calls.push(["upstream-failure", uploadId, error.message]);
      return { state: "failed" };
    },
    recordUpstreamResult(uploadId, result) {
      calls.push(["upstream", uploadId, result]);
      return { state: "reconciling" };
    },
    async runReconciliationOnce() {},
    list() {
      return [];
    },
  };
}
