"use strict";

const assert = require("assert");
const http = require("http");
const test = require("node:test");
const {
  receiveRecorderObservabilityExpectationCommand,
  recorderObservabilityExpectationCommandRoute,
} = require("../../src/adapters/inbound/http/recorder-observability-expectation-http");

test("expectation command endpoint authenticates and returns an accepted receipt", async () => {
  const calls = [];
  const server = testServer({
    async applyExpectationCommand(command) {
      calls.push(command);
      return {
        kind: "accepted",
        currentRevision: 1,
        event: { eventId: "30000000-0000-4000-8000-000000000001" },
        projection: {},
      };
    },
  });
  await listen(server);

  const response = await request(server, expectationCommand());
  const body = await response.json();
  await close(server);

  assert.strictEqual(response.status, 201);
  assert.deepStrictEqual(body, {
    state: "accepted",
    commandId: "20000000-0000-4000-8000-000000000001",
    vrcode: "VR_A",
    currentRevision: 1,
    eventId: "30000000-0000-4000-8000-000000000001",
    failure: null,
  });
  assert.deepStrictEqual(calls, [expectationCommand()]);
});

test("expectation command endpoint preserves revision conflict", async () => {
  const server = testServer({
    async applyExpectationCommand() {
      return {
        kind: "revisionConflict",
        currentRevision: 4,
        failure: "revisionConflict",
      };
    },
  });
  await listen(server);

  const response = await request(server, expectationCommand());
  const body = await response.json();
  await close(server);

  assert.strictEqual(response.status, 409);
  assert.strictEqual(body.state, "revisionConflict");
  assert.strictEqual(body.currentRevision, 4);
  assert.strictEqual(body.failure, "revisionConflict");
});

test("expectation command endpoint does not hide unavailable or invalid credentials", async () => {
  const unavailable = testServer(
    { applyExpectationCommand() { throw new Error("must not run"); } },
    {
      state: "unavailable",
      token: null,
      reason: "expectation_control_credential_missing",
    },
  );
  await listen(unavailable);
  const unavailableResponse = await request(unavailable, expectationCommand());
  const unavailableBody = await unavailableResponse.json();
  await close(unavailable);

  const unauthorized = testServer({
    applyExpectationCommand() { throw new Error("must not run"); },
  });
  await listen(unauthorized);
  const unauthorizedResponse = await request(
    unauthorized,
    expectationCommand(),
    "wrong-secret",
  );
  await close(unauthorized);

  assert.strictEqual(unavailableResponse.status, 503);
  assert.deepStrictEqual(unavailableBody, {
    state: "unavailable",
    failure: "expectationControlCredentialUnavailable",
    detail: "expectation_control_credential_missing",
  });
  assert.strictEqual(unauthorizedResponse.status, 401);
});

test("expectation command endpoint rejects incomplete command contracts before persistence", async () => {
  const server = testServer({
    applyExpectationCommand() { throw new Error("must not run"); },
  });
  await listen(server);

  const command = expectationCommand();
  delete command.evidenceDocument;
  const response = await request(server, command);
  const body = await response.json();
  await close(server);

  assert.strictEqual(response.status, 400);
  assert.strictEqual(body.failure, "commandContractInvalid");
  assert.match(body.detail, /missing=evidenceDocument/);
});

function testServer(
  repository,
  credential = { state: "loaded", token: "control-secret", reason: null },
) {
  return http.createServer((req, res) => {
    if (!recorderObservabilityExpectationCommandRoute(req.url)) {
      res.writeHead(404);
      res.end();
      return;
    }
    receiveRecorderObservabilityExpectationCommand(req, res, {
      repository,
      credential,
      maxRequestBytes: 64 * 1024,
    });
  });
}

function request(server, command, token = "control-secret") {
  return fetch(
    url(server, "/internal/recorder-observability/expectations"),
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(command),
    },
  );
}

function expectationCommand() {
  return {
    commandId: "20000000-0000-4000-8000-000000000001",
    vrcode: "VR_A",
    expectedRevision: 0,
    action: "set",
    supportState: "supported",
    source: "deployment_assignment",
    recorderVersion: "1.20.0",
    producerVersion: "2.0.0",
    protocolVersion: "1",
    catalogRevision: null,
    expectedSince: "2026-07-24T01:00:00Z",
    evidenceDocument: { deploymentId: "deployment-1" },
    decidedAt: "2026-07-24T01:00:00Z",
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
