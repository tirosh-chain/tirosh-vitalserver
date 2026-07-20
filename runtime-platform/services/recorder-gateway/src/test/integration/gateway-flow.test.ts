import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createServer, type Server as HttpServer } from "node:http";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { Server as SocketIoServer } from "socket.io";

import type {
  RecorderColdPathCapture,
  RecorderColdPathCaptureFinalizationReceipt,
  RecorderGatewayReadResult,
  RecorderIngressAcknowledgement,
  RecorderIngressReceipt,
  VitalServerDeliveryReceipt,
} from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";
import { createRecorderGatewayRuntime } from "../../recorder-gateway-runtime-composition.js";
import { SocketIoV2WireClient } from "../support/socketio-v2-wire-client.js";

interface StartedVitalServer {
  url: string;
  receivedPayloads: Uint8Array[];
  close(): Promise<void>;
}

test("Socket.IO v2 recorder flow keeps ingress and delivery state distinct", async (context) => {
  const vitalServer = await startVitalServer();
  const stateDirectory = await mkdtemp(join(tmpdir(), "recorder-gateway-flow-"));
  const runtime = await createRecorderGatewayRuntime({
    stateDirectory,
    vitalServerDeliveryURL: vitalServer.url,
    vitalServerDeliveryAcknowledgementTimeoutMs: 1000,
    replayIntervalMs: 60_000,
    ingressAdmission: { maxPendingItems: 10, maxPendingBytes: 1_000_000 },
    coldPathCapture: { maxRetainedPackets: 10, maxRetainedPayloadBytes: 1_000_000 },
    replay: { maxAttempts: 3, retryDelayMs: 10, leaseDurationMs: 1000 },
    provider: { kind: "vitalserver", id: "vitalserver-fixture", capabilityRevision: 1 },
  });
  const address = await runtime.start("127.0.0.1", 0);
  const gatewayUrl = `http://127.0.0.1:${address.port}`;
  const clients: SocketIoV2WireClient[] = [];
  context.after(async () => {
    for (const client of clients) {
      await client.close();
    }
    await runtime.close();
    await vitalServer.close();
    await rm(stateDirectory, { recursive: true, force: true });
  });

  const first = await SocketIoV2WireClient.connect(gatewayUrl);
  clients.push(first);
  const firstJoin = await acknowledgement(first.acknowledgeRecorderIngress("join_vr", "LAB-v2-fixture"));
  assert.equal(firstJoin.state, "accepted");
  assert.ok(firstJoin.sessionId);
  assert.ok(firstJoin.coldPathCaptureId);
  const repeatedJoin = await acknowledgement(first.acknowledgeRecorderIngress("join_vr", "LAB-v2-fixture"));
  assert.equal(repeatedJoin.state, "rejected");
  assert.equal(repeatedJoin.issue?.code, "recorder-session-already-joined");

  const textAdmission = await acknowledgement(first.acknowledgeRecorderIngress("send_data", "binary\u0000text"));
  assert.equal(textAdmission.state, "accepted");
  assert.ok(textAdmission.receiptId);
  const binaryAdmission = await acknowledgement(first.acknowledgeBinary("send_data", Buffer.from([0, 1, 2, 255])));
  assert.equal(binaryAdmission.state, "accepted");
  assert.ok(binaryAdmission.receiptId);

  const textDelivery = await runtime.ingressAndColdPathService.replayOneDueVitalServerDelivery();
  const binaryDelivery = await runtime.ingressAndColdPathService.replayOneDueVitalServerDelivery();
  assert.equal(textDelivery.state, "completed");
  assert.equal(textDelivery.deliveryReceipt?.outcome.state, "succeeded");
  assert.equal(binaryDelivery.state, "completed");
  assert.equal(binaryDelivery.deliveryReceipt?.outcome.state, "succeeded");
  assert.deepEqual(vitalServer.receivedPayloads, [Buffer.from("binary\u0000text", "binary"), Buffer.from([0, 1, 2, 255])]);

  const ingressRead = await fetchReadResult<RecorderIngressReceipt>(gatewayUrl, `/v1/recorder-ingress/receipts/${textAdmission.receiptId}`);
  assert.equal(ingressRead.state, "available");
  assert.equal(ingressRead.value?.ingressState, "accepted");
  assert.equal(ingressRead.value?.connection.protocolVersion, "v2");
  const deliveryRead = await fetchReadResult<VitalServerDeliveryReceipt>(
    gatewayUrl,
    `/v1/recorder-ingress/delivery-receipts/${textDelivery.deliveryReceipt?.id}`,
  );
  assert.equal(deliveryRead.state, "available");
  assert.equal(deliveryRead.value?.outcome.state, "succeeded");

  const finalizationCommand = {
    schemaVersion: "v1",
    requestId: "cold-path-finalization-request-v2-flow",
    coldPathCaptureId: firstJoin.coldPathCaptureId,
    expectedCaptureRevision: 1,
  };
  const finalizationResponse = await fetch(`${gatewayUrl}/v1/recorder-cold-path/captures/${firstJoin.coldPathCaptureId}:finalize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(finalizationCommand),
  });
  assert.equal(finalizationResponse.status, 201);
  const finalizationReceipt = (await finalizationResponse.json()) as RecorderColdPathCaptureFinalizationReceipt;
  assert.equal(finalizationReceipt.captureReference.resourceId, firstJoin.coldPathCaptureId);
  assert.equal(finalizationReceipt.finalizedPacketSequence.packetCount, 2);
  const packetSequenceResponse = await fetch(`${gatewayUrl}/v1/recorder-cold-path/captures/${firstJoin.coldPathCaptureId}:packet-sequence`);
  assert.equal(packetSequenceResponse.status, 200);
  assert.equal(packetSequenceResponse.headers.get("content-type"), "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl");
  const packetSequence = new Uint8Array(await packetSequenceResponse.arrayBuffer());
  assert.equal(createHash("sha256").update(packetSequence).digest("hex"), finalizationReceipt.finalizedPacketSequence.sha256);
  assert.match(Buffer.from(packetSequence).toString("utf8"), /"payloadBase64"/);
  const coldPathCaptureRead = await fetchReadResult<RecorderColdPathCapture>(gatewayUrl, `/v1/recorder-cold-path/captures/${firstJoin.coldPathCaptureId}`);
  assert.equal(coldPathCaptureRead.state, "available");
  assert.equal(coldPathCaptureRead.value?.state, "finalized");
  assert.equal(coldPathCaptureRead.value?.finalizationReceipt?.id, finalizationReceipt.id);
  const finalizedCaptureAdmission = await acknowledgement(first.acknowledgeBinary("send_data", Buffer.from([10])));
  assert.equal(finalizedCaptureAdmission.state, "rejected");
  assert.equal(finalizedCaptureAdmission.issue?.code, "recorder-cold-path-capture-not-active-for-connection");

  await first.close();
  const reconnected = await SocketIoV2WireClient.connect(gatewayUrl);
  clients.push(reconnected);
  const beforeJoin = await acknowledgement(reconnected.acknowledgeBinary("send_data", Buffer.from([9])));
  assert.equal(beforeJoin.state, "rejected");
  assert.equal(beforeJoin.issue?.code, "recorder-session-not-joined");
  const secondJoin = await acknowledgement(reconnected.acknowledgeRecorderIngress("join_vr", "LAB-v2-fixture"));
  assert.equal(secondJoin.state, "accepted");
  assert.notEqual(secondJoin.sessionId, firstJoin.sessionId);
  assert.notEqual(secondJoin.coldPathCaptureId, firstJoin.coldPathCaptureId);
  const command = await acknowledgement(reconnected.acknowledgeRecorderIngress("req_cmd", "job=restart&vrcode=LAB-v2-fixture"));
  assert.equal(command.state, "unsupported");
  assert.equal(command.issue?.code, "recorder-command-dispatch-not-enabled");
});

async function startVitalServer(): Promise<StartedVitalServer> {
  const server = createServer();
  const socketServer = new SocketIoServer(server, { transports: ["websocket", "polling"] });
  const receivedPayloads: Uint8Array[] = [];
  socketServer.on("connection", (socket) => {
    socket.on("send_data", (payload: unknown, acknowledgement: unknown) => {
      if (typeof payload === "string") {
        receivedPayloads.push(Buffer.from(payload, "binary"));
      } else if (Buffer.isBuffer(payload) || payload instanceof Uint8Array) {
        receivedPayloads.push(Buffer.from(payload));
      }
      if (typeof acknowledgement === "function") {
        (acknowledgement as (value: unknown) => void)({ schemaVersion: "v1", state: "accepted" });
      }
    });
  });
  const address = await listen(server);
  return {
    url: `http://127.0.0.1:${address.port}`,
    receivedPayloads,
    close: async () => {
      await new Promise<void>((resolve) => socketServer.close(() => resolve()));
      await closeRecorderGatewayControlHTTPServer(server);
    },
  };
}

async function acknowledgement(result: Promise<unknown>): Promise<RecorderIngressAcknowledgement> {
  const value = await result;
  if (typeof value !== "object" || value === null) {
    throw new Error("Socket.IO v2 acknowledgement was not an object");
  }
  return value as RecorderIngressAcknowledgement;
}

async function fetchReadResult<T>(gatewayUrl: string, path: string): Promise<RecorderGatewayReadResult<T>> {
  const response = await fetch(`${gatewayUrl}${path}`);
  assert.equal(response.status, 200);
  return (await response.json()) as RecorderGatewayReadResult<T>;
}

function listen(server: HttpServer): Promise<{ port: number }> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("test upstream did not expose a TCP port"));
        return;
      }
      resolve({ port: address.port });
    });
  });
}

function closeRecorderGatewayControlHTTPServer(server: HttpServer): Promise<void> {
  if (!server.listening) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error === undefined) {
        resolve();
        return;
      }
      reject(error);
    });
  });
}
