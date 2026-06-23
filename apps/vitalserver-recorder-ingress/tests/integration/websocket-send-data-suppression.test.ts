"use strict";

const assert = require("assert");
const crypto = require("crypto");
const net = require("net");
const test = require("node:test");
const { createRecorderIngressServer } = require("../../src/composition/recorder-ingress-composition");
const { encodeWebSocketFrame, readFrame } = require("../../src/adapters/inbound/http/websocket-parser");

test("recorder ingress suppresses client send_data frames in spool_only mode", { timeout: 2000 }, async () => {
  const fixture = await startProxyFixture("spool_only");
  let client = null;
  try {
    client = await sendClientFrames(fixture.ingressPort, [
      clientFrame('42["join_vr","VR_A"]', 1),
      clientFrame('42["send_data","payload"]', 1),
    ]);
    await waitFor(() => fixture.upstreamPayloads.length >= 1);

    assert.deepStrictEqual(fixture.upstreamPayloads, ['42["join_vr","VR_A"]']);
  } finally {
    if (client) client.destroy();
    await fixture.close();
  }
});

test("recorder ingress keeps client send_data frames in mirror_spool mode", { timeout: 2000 }, async () => {
  const fixture = await startProxyFixture("mirror_spool");
  let client = null;
  try {
    client = await sendClientFrames(fixture.ingressPort, [
      clientFrame('42["join_vr","VR_A"]', 1),
      clientFrame('42["send_data","payload"]', 1),
    ]);
    await waitFor(() => fixture.upstreamPayloads.length >= 2);

    assert.deepStrictEqual(fixture.upstreamPayloads, [
      '42["join_vr","VR_A"]',
      '42["send_data","payload"]',
    ]);
  } finally {
    if (client) client.destroy();
    await fixture.close();
  }
});

async function startProxyFixture(mode) {
  const sockets = [];
  const redis: any = await listenServer(net.createServer((socket) => {
    sockets.push(socket);
    socket.on("data", () => socket.write(":1\r\n"));
  }));
  const upstreamPayloads = [];
  const upstream: any = await listenServer(net.createServer((socket) => {
    sockets.push(socket);
    let handshake = Buffer.alloc(0);
    let upgraded = false;
    let frameBuffer = Buffer.alloc(0);

    socket.on("data", (chunk) => {
      if (!upgraded) {
        handshake = Buffer.concat([handshake, chunk]);
        const headerEnd = handshake.indexOf("\r\n\r\n");
        if (headerEnd < 0) return;
        upgraded = true;
        socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
        const rest = handshake.slice(headerEnd + 4);
        if (rest.length > 0) collectFrames(rest);
        return;
      }
      collectFrames(chunk);
    });

    function collectFrames(chunk) {
      frameBuffer = Buffer.concat([frameBuffer, chunk]);
      while (frameBuffer.length >= 2) {
        const frame = readFrame(frameBuffer);
        if (!frame) return;
        if (frame.opcode === 1) upstreamPayloads.push(frame.payload.toString("utf8"));
        frameBuffer = frameBuffer.slice(frame.nextOffset);
      }
    }
  }));

  const ingress = createRecorderIngressServer(configFor(mode, upstream.port, redis.port));
  await listenHttpServer(ingress);

  return {
    ingressPort: ingress.address().port,
    upstreamPayloads,
    close: async () => {
      if (typeof ingress.closeAllConnections === "function") ingress.closeAllConnections();
      for (const socket of sockets) socket.destroy();
      await closeServer(ingress);
      await closeServer(upstream.server);
      await closeServer(redis.server);
    },
  };
}

function configFor(mode, upstreamPort, redisPort) {
  return {
    listenPort: 0,
    upstream: { host: "127.0.0.1", port: upstreamPort, timeoutMs: 1000 },
    redis: { host: "127.0.0.1", port: redisPort, timeoutMs: 1000 },
    audit: {
      enabled: false,
      listKey: "audit",
      maxLen: 0,
      maxBodyBytes: 1024,
      log: { enabled: false, path: "/tmp/unused.log", format: "json" },
      stdout: { enabled: false, format: "json" },
    },
    spool: {
      enabled: mode !== "passthrough",
      mode,
      storage: "redis_list",
      listKey: "send_data:pending",
      inFlightListKey: "send_data:in_flight",
      replayedListKey: "send_data:replayed",
      deadLetterListKey: "send_data:dead_letter",
      maxPendingItems: 100,
      maxPendingBytes: 1024 * 1024,
      maxPayloadBytes: 1024 * 1024,
      replay: {
        enabled: false,
        intervalMs: 1000,
        batchSize: 1,
        maxAttempts: 3,
        rateLimitPerSecond: 1,
        targetTimeoutMs: 1000,
      },
    },
    clientIp: { trustProxy: true },
    vitalServer: { ipRewrite: { enabled: false, verifyDelaysMs: [] } },
  };
}

function sendClientFrames(port, frames) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const socket = net.createConnection({ host: "127.0.0.1", port }, () => {
      socket.write([
        "GET /socket.io/?EIO=3&transport=websocket HTTP/1.1",
        "Host: 127.0.0.1",
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString("base64")}`,
        "Sec-WebSocket-Version: 13",
        "\r\n",
      ].join("\r\n"));
    });
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      socket.destroy();
      reject(new Error("websocket handshake response was not received"));
    }, 500);

    let response = Buffer.alloc(0);
    socket.on("data", (chunk) => {
      if (settled) return;
      response = Buffer.concat([response, chunk]);
      if (response.includes(Buffer.from("\r\n\r\n"))) {
        settled = true;
        clearTimeout(timeout);
        for (const frame of frames) socket.write(frame);
        resolve(socket);
      }
    });
    socket.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
  });
}

function clientFrame(payload, opcode) {
  return encodeWebSocketFrame(payload, opcode, {
    mask: true,
    maskKey: Buffer.from([0x0a, 0x0b, 0x0c, 0x0d]),
  });
}

function listenServer(server) {
  return new Promise((resolve, reject) => {
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      resolve({ server, port: server.address().port });
    });
  });
}

function listenHttpServer(server) {
  return new Promise((resolve, reject) => {
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(null));
  });
}

function closeServer(server) {
  return new Promise((resolve) => server.close(() => resolve(null)));
}

async function waitFor(predicate) {
  const started = Date.now();
  while (!predicate()) {
    if (Date.now() - started > 500) throw new Error("condition was not met");
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
