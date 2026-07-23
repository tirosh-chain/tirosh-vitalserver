"use strict";

const assert = require("assert");
const http = require("http");
const test = require("node:test");
const {
  receiveRecorderObservability,
  recorderObservabilityRoute,
} = require("../../src/adapters/inbound/http/recorder-observability-http");

test("HTTP adapter accepts NDJSON at the VRCODE-scoped API path", async () => {
  const calls = [];
  const metrics = observabilityMetrics();
  const server = testServer({
    admit(input) {
      calls.push(input);
      return {
        state: "admitted",
        requestId: "request-1",
        accepted: 1,
        duplicates: 0,
        quarantined: 0,
      };
    },
  }, 5 * 1024 * 1024, metrics);
  await listen(server);

  const document = observation();
  const response = await fetch(url(server, "/api/v1/recorders/BRMH-OR1/observations"), {
    method: "POST",
    headers: {
      "content-type": "application/x-ndjson",
      "x-device-id": "vr-brmh-15",
    },
    body: `${JSON.stringify(document)}\n`,
  });
  const body = await response.json();
  await close(server);

  assert.strictEqual(response.status, 202);
  assert.strictEqual(body.accepted, 1);
  assert.strictEqual(calls[0].vrcode, "BRMH-OR1");
  assert.strictEqual(calls[0].resourceType, "observation");
  assert.strictEqual(calls[0].requestDeviceId, "vr-brmh-15");
  assert.deepStrictEqual(calls[0].lines[0].document, document);
  assert.strictEqual(metrics.requests, 1);
  assert.strictEqual(metrics.accepted, 1);
  assert.strictEqual(metrics.admissionFailures, 0);
  assert.ok(metrics.lastAdmittedAt);
});

test("HTTP adapter rejects request-level contract failures", async () => {
  const server = testServer({ admit() { throw new Error("must not run"); } });
  await listen(server);

  const invalidVrcode = await fetch(
    url(server, "/api/v1/recorders/bad%2Fcode/observations"),
    {
      method: "POST",
      headers: {
        "content-type": "application/x-ndjson",
        "x-device-id": "vr-brmh-15",
      },
      body: `${JSON.stringify(observation())}\n`,
    },
  );
  const invalidContentType = await fetch(
    url(server, "/api/v1/recorders/BRMH-OR1/observations"),
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "vr-brmh-15",
      },
      body: `${JSON.stringify(observation())}\n`,
    },
  );
  const emptyNDJSON = await fetch(
    url(server, "/api/v1/recorders/BRMH-OR1/observations"),
    {
      method: "POST",
      headers: {
        "content-type": "application/x-ndjson",
        "x-device-id": "vr-brmh-15",
      },
      body: "\n",
    },
  );
  await close(server);

  assert.strictEqual(invalidVrcode.status, 404);
  assert.strictEqual(invalidContentType.status, 415);
  assert.strictEqual(emptyNDJSON.status, 400);
});

test("HTTP adapter returns 413 above the configured chunk limit", async () => {
  const server = testServer(
    { admit() { throw new Error("must not run"); } },
    32,
  );
  await listen(server);

  const response = await fetch(
    url(server, "/api/v1/recorders/BRMH-OR1/observations"),
    {
      method: "POST",
      headers: {
        "content-type": "application/x-ndjson",
        "x-device-id": "vr-brmh-15",
      },
      body: `${JSON.stringify(observation())}\n`,
    },
  );
  await close(server);

  assert.strictEqual(response.status, 413);
});

test("HTTP adapter returns 503 when durable admission fails", async () => {
  const server = testServer({
    admit() {
      throw new Error("disk unavailable");
    },
  });
  await listen(server);

  const response = await fetch(
    url(server, "/api/v1/recorders/BRMH-OR1/observations"),
    {
      method: "POST",
      headers: {
        "content-type": "application/x-ndjson",
        "x-device-id": "vr-brmh-15",
      },
      body: `${JSON.stringify(observation())}\n`,
    },
  );
  await close(server);

  assert.strictEqual(response.status, 503);
});

function testServer(
  ingress,
  maxRequestBytes = 5 * 1024 * 1024,
  metrics = observabilityMetrics(),
) {
  return http.createServer((req, res) => {
    const route = recorderObservabilityRoute(req.url);
    if (!route) {
      res.writeHead(404);
      res.end();
      return;
    }
    receiveRecorderObservability(req, res, {
      route,
      ingress,
      maxRequestBytes,
      metrics,
      sourceIp: "172.31.0.157",
    });
  });
}

function observabilityMetrics() {
  return {
    requests: 0,
    accepted: 0,
    duplicates: 0,
    quarantined: 0,
    admissionFailures: 0,
    lastAdmittedAt: null,
    lastFailure: null,
  };
}

function observation() {
  return {
    schemaVersion: "v1",
    eventId: "vr-brmh-15:boot-1:42",
    deviceId: "vr-brmh-15",
    bootId: "boot-1",
    sequence: 42,
    kind: "device-health",
    collectionState: "ok",
    deviceObservedAt: "2026-07-23T01:00:00Z",
    uptimeSeconds: { state: "ok", value: 42 },
    ntpState: "synchronized",
    payload: {},
    readIssues: [],
  };
}

function listen(server) {
  return new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
}

function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

function url(server, pathname) {
  return `http://127.0.0.1:${server.address().port}${pathname}`;
}
