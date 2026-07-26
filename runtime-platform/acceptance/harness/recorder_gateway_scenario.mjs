// Black-box Recorder Gateway scenario. It uses the built Gateway process boundary and
// public Socket.IO/HTTP contracts only; Python validates its emitted C5/C13
// documents against the canonical contract schemas.
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../..", import.meta.url));
const gatewayRoot = join(root, "services", "recorder-gateway");
const requireGateway = createRequire(pathToFileURL(join(gatewayRoot, "package.json")));
const { Server: SocketIoServer } = requireGateway("socket.io");
const { createRecorderGatewayRuntime } = await import(pathToFileURL(join(gatewayRoot, "dist", "recorder-gateway-runtime-composition.js")).href);
const { SocketIoV2WireClient } = await import(pathToFileURL(join(gatewayRoot, "dist", "test", "support", "socketio-v2-wire-client.js")).href);

const vitalServer = await startVitalServer();
const stateDirectory = await mkdtemp(join(tmpdir(), "recorder-gateway-acceptance-"));
const runtime = await createRecorderGatewayRuntime({
  stateDirectory,
  vitalServerDeliveryURL: vitalServer.url,
  vitalServerDeliveryAcknowledgementTimeoutMs: 1000,
  replayIntervalMs: 60_000,
  ingressAdmission: { maxPendingItems: 1, maxPendingBytes: 1_000_000 },
  coldPathCapture: { maxRetainedPackets: 10, maxRetainedPayloadBytes: 1_000_000 },
  replay: { maxAttempts: 3, retryDelayMs: 10, leaseDurationMs: 1000 },
  provider: { kind: "vitalserver", id: "vitalserver-acceptance-fixture", capabilityRevision: 1 },
  guestRuntimeObservationCatalogEndpoint: "http://127.0.0.1:1",
  guestRuntimeObservationCatalogBearerToken: "acceptance-catalog-token",
  recorderVitalUploadMaximumBytes: 1_000_000,
  recorderVitalUploadRecoveryIntervalMs: 60_000,
  recorderVitalUploadRecoveryMaxItems: 10,
  guestRuntimeArchiveSourceAdmissionEndpoint: "http://127.0.0.1:1/internal/v1/archive/recorder-uploads",
  guestRuntimeArchiveSourceAdmissionBearerToken: "acceptance-archive-token",
  guestRuntimeArchiveSourceAdmissionRequestTimeoutMs: 1_000,
});
let first;
let second;
try {
  const address = await runtime.start("127.0.0.1", 0);
  const gatewayUrl = `http://127.0.0.1:${address.port}`;
  first = await SocketIoV2WireClient.connect(gatewayUrl);
  const joined = await acknowledgement(first.acknowledgeRecorderIngress("join_vr", "LAB-acceptance-v2"));
  const accepted = await acknowledgement(first.acknowledgeBinary("send_data", Buffer.from([0, 1, 2, 255])));
  const full = await acknowledgement(first.acknowledgeBinary("send_data", Buffer.from([3])));
  const replay = await runtime.ingressAndColdPathService.replayOneDueVitalServerDelivery();
  if (accepted.state !== "accepted" || accepted.receiptId === undefined || replay.deliveryReceipt === undefined) {
    throw new Error("Gateway did not produce an accepted ingress and delivery receipt");
  }
  const ingressResult = await readJson(gatewayUrl, `/v1/recorder-ingress/receipts/${accepted.receiptId}`);
  const deliveryResult = await readJson(gatewayUrl, `/v1/recorder-ingress/delivery-receipts/${replay.deliveryReceipt.id}`);

  await first.close();
  second = await SocketIoV2WireClient.connect(gatewayUrl);
  const beforeJoin = await acknowledgement(second.acknowledgeBinary("send_data", Buffer.from([9])));
  const rejoined = await acknowledgement(second.acknowledgeRecorderIngress("join_vr", "LAB-acceptance-v2"));
  const command = await acknowledgement(second.acknowledgeRecorderIngress("req_cmd", "job=restart&vrcode=LAB-acceptance-v2"));

  process.stdout.write(`${JSON.stringify({
    ingressResult,
    deliveryResult,
    full,
    beforeJoin,
    joined,
    rejoined,
    command,
    vitalServerReceivedByteCount: vitalServer.receivedByteCount,
  })}\n`);
} finally {
  if (first !== undefined) await first.close();
  if (second !== undefined) await second.close();
  await runtime.close();
  await vitalServer.close();
  await rm(stateDirectory, { recursive: true, force: true });
}

async function startVitalServer() {
  const server = createServer();
  const socketServer = new SocketIoServer(server, { transports: ["websocket", "polling"] });
  let receivedByteCount = 0;
  socketServer.on("connection", (socket) => {
    socket.on("send_data", (payload, acknowledgement) => {
      if (typeof payload === "string") receivedByteCount += Buffer.byteLength(payload, "binary");
      else if (Buffer.isBuffer(payload) || payload instanceof Uint8Array) receivedByteCount += payload.byteLength;
      if (typeof acknowledgement === "function") acknowledgement({ schemaVersion: "v1", state: "accepted" });
    });
  });
  const address = await listen(server);
  return {
    url: `http://127.0.0.1:${address.port}`,
    get receivedByteCount() { return receivedByteCount; },
    async close() {
      await new Promise((resolve) => socketServer.close(resolve));
      if (!server.listening) return;
      await new Promise((resolve, reject) => server.close((error) => error === undefined ? resolve() : reject(error)));
    },
  };
}

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("VitalServer acceptance fixture did not expose a TCP address"));
        return;
      }
      resolve(address);
    });
  });
}

async function acknowledgement(result) {
  const value = await result;
  if (typeof value !== "object" || value === null) throw new Error("Socket.IO v2 acknowledgement was not an object");
  return value;
}

async function readJson(gatewayUrl, path) {
  const response = await fetch(`${gatewayUrl}${path}`);
  if (response.status !== 200) throw new Error(`Gateway control read failed: ${response.status}`);
  return response.json();
}
