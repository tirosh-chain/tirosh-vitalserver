import assert from "node:assert/strict";
import { createServer, type Server as HttpServer } from "node:http";
import { createServer as createNetServer } from "node:net";
import test from "node:test";

import { Server as SocketIoServer } from "socket.io";

import { SocketIoVitalServerPacketDeliveryPort } from "../../adapters/vitalserverpacketdeliverysocketio/socketio-vital-server-packet-delivery-port.js";

test("VitalServer Socket.IO transport unavailability is returned as unavailable, not delivery success", async () => {
  const port = await releasedPort();
  const deliveryPort = new SocketIoVitalServerPacketDeliveryPort({
    vitalServerDeliveryURL: `http://127.0.0.1:${port}`,
    acknowledgementTimeoutMs: 200,
    vitalServerProviderID: "external-vitalserver-fixture",
  });
  const outcome = await deliveryPort.deliverRecorderPacketToVitalServer({
    deliveryRequestId: "delivery-request-unavailable",
    ingressReceiptId: "ingress-receipt-unavailable",
    attempt: 1,
    payload: Buffer.from([1]),
    payloadEncoding: "binary",
  });
  assert.equal(outcome.state, "unavailable");
  assert.equal(outcome.issue?.code, "vitalserver-transport-unavailable");
  assert.equal(outcome.issue?.dependency, "external-vitalserver-fixture");
  assert.equal(outcome.issue?.retryable, true);
});

test("VitalServer delivery succeeds only after an explicit accepted acknowledgement", async (context) => {
  const server = createServer();
  const socketServer = new SocketIoServer(server, { transports: ["websocket", "polling"] });
  socketServer.on("connection", (socket) => {
    socket.on("send_data", (_payload: unknown, acknowledgement: unknown) => {
      if (typeof acknowledgement === "function") {
        (acknowledgement as (value: unknown) => void)({ schemaVersion: "v1", state: "accepted" });
      }
    });
  });
  const address = await listen(server);
  context.after(async () => {
    await new Promise<void>((resolve) => socketServer.close(() => resolve()));
    if (!server.listening) {
      return;
    }
    await closeRecorderGatewayControlHTTPServer(server);
  });
  const deliveryPort = new SocketIoVitalServerPacketDeliveryPort({
    vitalServerDeliveryURL: `http://127.0.0.1:${address.port}`,
    acknowledgementTimeoutMs: 1000,
    vitalServerProviderID: "bundled-vitalserver-fixture",
  });
  const outcome = await deliveryPort.deliverRecorderPacketToVitalServer({
    deliveryRequestId: "delivery-request-accepted",
    ingressReceiptId: "ingress-receipt-accepted",
    attempt: 1,
    payload: Buffer.from([1, 2, 3]),
    payloadEncoding: "binary",
  });
  assert.deepEqual(outcome, { state: "succeeded" });
});

function releasedPort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createNetServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("test listener did not expose a TCP port"));
        return;
      }
      const port = address.port;
      server.close((error) => {
        if (error === undefined) {
          resolve(port);
          return;
        }
        reject(error);
      });
    });
  });
}

function listen(server: HttpServer): Promise<{ port: number }> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("VitalServer fixture did not expose a TCP port"));
        return;
      }
      resolve({ port: address.port });
    });
  });
}

function closeRecorderGatewayControlHTTPServer(server: HttpServer): Promise<void> {
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
