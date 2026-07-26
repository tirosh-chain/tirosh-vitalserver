import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import test from "node:test";

import { RecorderGatewayObservationCatalogClient } from "../../adapters/recorder-gateway-observation-catalog/recorder-gateway-observation-catalog-client.js";
import type { RecorderObservationPublishCommand } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

test("the Recorder Gateway catalog client publishes the Recorder-owned C19 envelope only after C20 succeeds", async () => {
  let requestMethod: string | undefined;
  let requestPath: string | undefined;
  let receivedBody: unknown;
  const server = createServer((request, response) => {
    requestMethod = request.method;
    requestPath = request.url;
    let body = "";
    request.setEncoding("utf8");
    request.on("data", (chunk: string) => {
      body += chunk;
    });
    request.on("end", () => {
      receivedBody = JSON.parse(body) as unknown;
      response.writeHead(202, { "content-type": "application/json" });
      response.end(JSON.stringify({ schemaVersion: "v1", outcome: "accepted" }));
    });
  });
  const endpoint = await listenOnLoopback(server);
  try {
    const command = recorderObservationCommand();
    const client = RecorderGatewayObservationCatalogClient.create(endpoint);

    assert.deepEqual(await client.publishRecorderObservation(command), { state: "published", observationId: command.observationId });
    assert.equal(requestMethod, "POST");
    assert.equal(requestPath, "/internal/v1/recorder-observations");
    assert.deepEqual(receivedBody, command);
  } finally {
    await close(server);
  }
});

test("the Recorder Gateway catalog client preserves a rejected catalog submission as an explicit Runner delivery failure", async () => {
  const server = createServer((_request, response) => {
    response.writeHead(503, { "content-type": "application/json" });
    response.end(JSON.stringify({ schemaVersion: "v1", state: "unavailable" }));
  });
  const endpoint = await listenOnLoopback(server);
  try {
    const result = await RecorderGatewayObservationCatalogClient.create(endpoint).publishRecorderObservation(recorderObservationCommand());
    assert.deepEqual(result, {
      state: "failed",
      issue: {
        code: "recorder-gateway-observation-catalog-rejected",
        message: "Recorder Gateway did not accept Recorder observation (HTTP 503)",
        retryable: true,
        dependency: "recorder-gateway-observation-catalog",
      },
    });
  } finally {
    await close(server);
  }
});

function recorderObservationCommand(): RecorderObservationPublishCommand {
  return {
    schemaVersion: "v1",
    requestId: "recording-start-1",
    observationId: "recorder-observation-1",
    envelope: {
      schemaVersion: "v1",
      protocolVersion: "v1",
      recorderId: "recorder-virtual-1",
      bootId: "runner-boot-1",
      sequence: 1,
      occurredAt: "2026-07-19T00:00:00.000Z",
      time: { state: "not-reported" },
      runtime: { state: "ready", version: "lab-recorder-runner-0.1.0" },
    },
  };
}

async function listenOnLoopback(server: Server): Promise<string> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("loopback HTTP test server did not expose a TCP address");
  }
  return `http://127.0.0.1:${address.port}`;
}

async function close(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
