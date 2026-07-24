import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createRecorderGatewayRuntime } from "../../recorder-gateway-runtime-composition.js";

test("Recorder observations reach Guest Runtime only through the authenticated Gateway hop", async () => {
  let authorization: string | undefined;
  let guestPath: string | undefined;
  let receivedCommand: unknown;
  const guest = createServer((request, response) => {
    authorization = request.headers.authorization;
    guestPath = request.url;
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => chunks.push(chunk));
    request.on("end", () => {
      receivedCommand = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
      response.writeHead(202, { "content-type": "application/json" });
      response.end(JSON.stringify({
        schemaVersion: "v1",
        requestId: "catalog-forward-1",
        outcome: "accepted",
        observationReference: { resourceType: "catalog-observation", resourceId: "catalog-observation-1" },
        receivedAt: "2026-07-24T01:02:03Z",
        persistedAt: "2026-07-24T01:02:03Z",
      }));
    });
  });
  const guestEndpoint = await listen(guest);
  const stateDirectory = await mkdtemp(join(tmpdir(), "recorder-gateway-catalog-forward-"));
  const runtime = await createRecorderGatewayRuntime({
    stateDirectory,
    vitalServerDeliveryURL: "http://127.0.0.1:65530",
    vitalServerDeliveryAcknowledgementTimeoutMs: 100,
    replayIntervalMs: 60_000,
    ingressAdmission: { maxPendingItems: 1, maxPendingBytes: 1024 },
    coldPathCapture: { maxRetainedPackets: 1, maxRetainedPayloadBytes: 1024 },
    replay: { maxAttempts: 1, retryDelayMs: 100, leaseDurationMs: 100 },
    provider: { kind: "test-provider", id: "test-provider", capabilityRevision: 1 },
    guestRuntimeObservationCatalogEndpoint: guestEndpoint,
    guestRuntimeObservationCatalogBearerToken: "catalog-forward-token",
    recorderVitalUploadMaximumBytes: 1_000_000,
    recorderVitalUploadRecoveryIntervalMs: 60_000,
    recorderVitalUploadRecoveryMaxItems: 10,
    guestRuntimeArchiveSourceAdmissionEndpoint: "http://127.0.0.1:18444/internal/v1/archive/recorder-uploads",
    guestRuntimeArchiveSourceAdmissionBearerToken: "test-only-archive-token",
    guestRuntimeArchiveSourceAdmissionRequestTimeoutMs: 1000,
  });
  try {
    const gatewayAddress = await runtime.start("127.0.0.1", 0);
    const command = { schemaVersion: "v1", requestId: "catalog-forward-1", observationId: "catalog-observation-1", envelope: {} };
    const response = await fetch(`http://127.0.0.1:${gatewayAddress.port}/internal/v1/recorder-observations`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(command),
    });
    const receipt = await response.json() as Record<string, unknown>;
    assert.equal(response.status, 202);
    assert.equal(receipt.outcome, "accepted");
    assert.equal(guestPath, "/internal/v1/recorder-catalog/observations");
    assert.equal(authorization, "Bearer catalog-forward-token");
    assert.deepEqual(receivedCommand, command);
  } finally {
    await runtime.close();
    await close(guest);
    await rm(stateDirectory, { recursive: true, force: true });
  }
});

async function listen(server: Server): Promise<string> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("Guest Runtime Catalog fixture did not expose a TCP address");
  }
  return `http://127.0.0.1:${address.port}`;
}

async function close(server: Server): Promise<void> {
  if (!server.listening) {
    return;
  }
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
