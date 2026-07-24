import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { createRecorderGatewayRuntime } from "../../recorder-gateway-runtime-composition.js";

test("public Recorder upload succeeds only after authenticated Guest Archive admission", async () => {
  let receivedCommand: Record<string, unknown> | undefined;
  let receivedContent = Buffer.alloc(0);
  let authorization: string | undefined;
  const guest = createServer((request, response) => {
    void (async () => {
      authorization = request.headers.authorization;
      const encodedCommand = request.headers["x-vital-archive-source-command"];
      if (typeof encodedCommand !== "string") {
        throw new Error("Archive source command header is missing");
      }
      receivedCommand = JSON.parse(
        Buffer.from(encodedCommand, "base64url").toString("utf8"),
      ) as Record<string, unknown>;
      const chunks: Buffer[] = [];
      for await (const chunk of request) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      }
      receivedContent = Buffer.concat(chunks);
      const requestId = receivedCommand.requestId;
      response.statusCode = 202;
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({
        schemaVersion: "v1",
        requestId,
        outcome: "accepted",
        artifactReference: {
          resourceType: "archive-artifact",
          resourceId: "archive-artifact-e2e",
        },
        receivedAt: (receivedCommand.source as { receivedAt: string }).receivedAt,
        persistedAt: "2026-07-24T14:00:01.000Z",
      }));
    })();
  });
  const guestEndpoint = await listenTestServer(guest);
  const stateDirectory = await mkdtemp(join(tmpdir(), "recorder-vital-upload-e2e-"));
  const runtime = await createRecorderGatewayRuntime({
    stateDirectory,
    vitalServerDeliveryURL: "http://127.0.0.1:65530",
    vitalServerDeliveryAcknowledgementTimeoutMs: 100,
    replayIntervalMs: 60_000,
    ingressAdmission: { maxPendingItems: 1, maxPendingBytes: 1024 },
    coldPathCapture: { maxRetainedPackets: 1, maxRetainedPayloadBytes: 1024 },
    replay: { maxAttempts: 1, retryDelayMs: 100, leaseDurationMs: 100 },
    provider: { kind: "test-provider", id: "test-provider", capabilityRevision: 1 },
    guestRuntimeObservationCatalogEndpoint: "http://127.0.0.1:18443",
    guestRuntimeObservationCatalogBearerToken: "test-catalog-token",
    recorderVitalUploadMaximumBytes: 1024,
    recorderVitalUploadRecoveryIntervalMs: 60_000,
    recorderVitalUploadRecoveryMaxItems: 10,
    guestRuntimeArchiveSourceAdmissionEndpoint: `${guestEndpoint}/internal/v1/archive/recorder-uploads`,
    guestRuntimeArchiveSourceAdmissionBearerToken: "test-archive-token",
    guestRuntimeArchiveSourceAdmissionRequestTimeoutMs: 1000,
  });
  try {
    const gateway = await runtime.start("127.0.0.1", 0);
    const form = new FormData();
    form.set("bedname", "OR-01");
    form.set("vrcode", "VR-01");
    const content = Buffer.from("complete-vital-content");
    form.set(
      "vitalfile",
      new Blob([content], { type: "application/x-vital" }),
      "OR-01.vital",
    );
    const response = await fetch(`http://127.0.0.1:${gateway.port}/upload`, {
      method: "POST",
      headers: { "x-vital-upload-id": "e2e-upload-1" },
      body: form,
    });
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "success");
    assert.equal(authorization, "Bearer test-archive-token");
    assert.deepEqual(receivedContent, content);
    assert.equal(receivedCommand?.schemaVersion, "v1");
    assert.equal(
      (receivedCommand?.source as { reportedBedName: string }).reportedBedName,
      "OR-01",
    );
    const dispatchResponse = await fetch(
      `http://127.0.0.1:${gateway.port}/v1/recorder-vital-uploads/recorder-vital-upload-e2e-upload-1`,
    );
    const dispatch = await dispatchResponse.json() as { state: string };
    assert.equal(dispatchResponse.status, 200);
    assert.equal(dispatch.state, "archive-admitted");
  } finally {
    await runtime.close();
    await closeTestServer(guest);
    await rm(stateDirectory, { recursive: true, force: true });
  }
});

async function listenTestServer(server: Server): Promise<string> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("test server did not expose a TCP address");
  }
  return `http://127.0.0.1:${address.port}`;
}

async function closeTestServer(server: Server): Promise<void> {
  if (!server.listening) {
    return;
  }
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
