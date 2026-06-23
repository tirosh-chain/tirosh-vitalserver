"use strict";

const { sendDataFailureReasons } = require("../../../domain/send-data-ingress-contracts");

function createSocketIoSendDataReplayTarget(config) {
  const socketIoClient = require("socket.io-client");
  const replayConfig = config.replay || (config.spool && config.spool.replay) || {};
  const targetTimeoutMs = replayConfig.targetTimeoutMs || 5000;

  return {
    send(item) {
      const payload = payloadFromSpoolItem(item);
      if (!payload.ok) return Promise.resolve(payload);

      return new Promise((resolve) => {
        let settled = false;
        const done = (result, socket) => {
          if (settled) return;
          settled = true;
          if (socket) socket.close();
          resolve(result);
        };

        const socket = socketIoClient(`http://${config.upstream.host}:${config.upstream.port}`, {
          transports: ["websocket", "polling"],
          forceNew: true,
          reconnection: false,
          timeout: targetTimeoutMs,
        });

        const timeout = setTimeout(() => {
          done({
            ok: false,
            reason: sendDataFailureReasons.UPSTREAM_TIMEOUT,
            message: "send_data replay timed out",
          }, socket);
        }, targetTimeoutMs);

        socket.on("connect", () => {
          clearTimeout(timeout);
          socket.emit("send_data", payload.value);
          done({ ok: true }, socket);
        });
        socket.on("connect_error", (error) => {
          clearTimeout(timeout);
          done({
            ok: false,
            reason: sendDataFailureReasons.UPSTREAM_UNAVAILABLE,
            message: error && error.message ? error.message : "upstream Socket.IO connection failed",
          }, socket);
        });
        socket.on("connect_timeout", () => {
          clearTimeout(timeout);
          done({
            ok: false,
            reason: sendDataFailureReasons.UPSTREAM_TIMEOUT,
            message: "upstream Socket.IO connection timed out",
          }, socket);
        });
      });
    },
  };
}

function payloadFromSpoolItem(item) {
  if (!item || typeof item.payloadBase64 !== "string") {
    return {
      ok: false,
      reason: sendDataFailureReasons.INVALID_PAYLOAD,
      message: "send_data spool item has no payloadBase64",
    };
  }

  let buffer;
  try {
    buffer = Buffer.from(item.payloadBase64, "base64");
  } catch (error) {
    return {
      ok: false,
      reason: sendDataFailureReasons.INVALID_PAYLOAD,
      message: error.message,
    };
  }

  if (item.payloadEncoding === "binary") return { ok: true, value: buffer };
  if (item.payloadEncoding === "string") return { ok: true, value: buffer.toString("binary") };
  return {
    ok: false,
    reason: sendDataFailureReasons.INVALID_PAYLOAD,
    message: `unsupported send_data payload encoding ${item.payloadEncoding}`,
  };
}

module.exports = { createSocketIoSendDataReplayTarget, payloadFromSpoolItem };
