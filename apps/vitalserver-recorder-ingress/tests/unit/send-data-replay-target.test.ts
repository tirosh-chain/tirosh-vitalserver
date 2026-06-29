"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  createSocketIoSendDataReplayTarget,
  payloadFromSpoolItem,
} = require("../../src/adapters/outbound/socketio/send-data-replay-target");

test("send_data replay target restores binary payload from spool item", () => {
  const result = payloadFromSpoolItem({
    payloadEncoding: "binary",
    payloadBase64: Buffer.from("payload").toString("base64"),
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(Buffer.isBuffer(result.value), true);
  assert.strictEqual(result.value.toString(), "payload");
});

test("send_data replay target restores binary-string payload from spool item", () => {
  const result = payloadFromSpoolItem({
    payloadEncoding: "string",
    payloadBase64: Buffer.from("payload", "binary").toString("base64"),
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.value, "payload");
});

test("send_data replay target rejects unsupported payload encoding", () => {
  const result = payloadFromSpoolItem({
    payloadEncoding: "json",
    payloadBase64: Buffer.from("payload").toString("base64"),
  });

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
  assert.match(result.message, /unsupported/);
});

test("send_data replay target reuses connected upstream Socket.IO session", async () => {
  const socketIoClient = createFakeSocketIoClient();
  const target = createSocketIoSendDataReplayTarget(replayTargetConfig(), socketIoClient);

  const first = await target.send(spoolItem("payload-1"));
  const second = await target.send(spoolItem("payload-2"));

  assert.strictEqual(first.ok, true);
  assert.strictEqual(second.ok, true);
  assert.strictEqual(socketIoClient.sockets.length, 1);
  assert.strictEqual(socketIoClient.sockets[0].closed, false);
  assert.deepStrictEqual(socketIoClient.sockets[0].emittedEvents.map((event) => event.name), [
    "send_data",
    "send_data",
  ]);
  assert.strictEqual(socketIoClient.sockets[0].emittedEvents[0].value.toString(), "payload-1");
  assert.strictEqual(socketIoClient.sockets[0].emittedEvents[1].value.toString(), "payload-2");
});

test("send_data replay target reconnects after upstream disconnect", async () => {
  const socketIoClient = createFakeSocketIoClient();
  const target = createSocketIoSendDataReplayTarget(replayTargetConfig(), socketIoClient);

  const first = await target.send(spoolItem("payload-1"));
  socketIoClient.sockets[0].trigger("disconnect");
  const second = await target.send(spoolItem("payload-2"));

  assert.strictEqual(first.ok, true);
  assert.strictEqual(second.ok, true);
  assert.strictEqual(socketIoClient.sockets.length, 2);
  assert.strictEqual(socketIoClient.sockets[1].emittedEvents[0].value.toString(), "payload-2");
});

test("send_data replay target reports connection failure explicitly", async () => {
  const socketIoClient = createFakeSocketIoClient({ connectError: "upstream down" });
  const target = createSocketIoSendDataReplayTarget(replayTargetConfig(), socketIoClient);

  const result = await target.send(spoolItem("payload"));

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "upstream_unavailable");
  assert.match(result.message, /upstream down/);
  assert.strictEqual(socketIoClient.sockets.length, 1);
  assert.strictEqual(socketIoClient.sockets[0].closed, true);
});

test("send_data replay target does not connect upstream for invalid spool item", async () => {
  const socketIoClient = createFakeSocketIoClient();
  const target = createSocketIoSendDataReplayTarget(replayTargetConfig(), socketIoClient);

  const result = await target.send({ id: "missing_payload" });

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
  assert.strictEqual(socketIoClient.sockets.length, 0);
});

function replayTargetConfig() {
  return {
    upstream: {
      host: "127.0.0.1",
      port: 3000,
    },
    replay: {
      targetTimeoutMs: 50,
    },
  };
}

function spoolItem(payload) {
  return {
    payloadEncoding: "binary",
    payloadBase64: Buffer.from(payload).toString("base64"),
  };
}

function createFakeSocketIoClient(options: { connectError?: string } = {}) {
  const sockets = [];
  const client = (url, config) => {
    const handlers = new Map();
    const socket = {
      url,
      config,
      connected: false,
      closed: false,
      emittedEvents: [],
      on(eventName, handler) {
        handlers.set(eventName, handler);
        return socket;
      },
      emit(name, value) {
        socket.emittedEvents.push({ name, value });
      },
      close() {
        socket.closed = true;
        socket.connected = false;
      },
      trigger(eventName, value = undefined) {
        if (eventName === "connect") socket.connected = true;
        if (eventName === "disconnect") socket.connected = false;
        const handler = handlers.get(eventName);
        if (handler) handler(value);
      },
    };

    sockets.push(socket);
    if (options.connectError) {
      setImmediate(() => socket.trigger("connect_error", new Error(options.connectError)));
    } else {
      setImmediate(() => socket.trigger("connect"));
    }
    return socket;
  };

  client.sockets = sockets;
  return client;
}
