import type { SendDataReplayTargetPort } from "../../../application/ports/outbound/send-data-replay-target-port";

"use strict";

const { sendDataFailureReasons } = require("../../../domain/send-data-ingress-contracts");

type SendDataReplayPayloadResult =
  | {
      ok: true;
      value: Buffer | string;
    }
  | {
      ok: false;
      reason: string;
      message: string;
    };

function createSocketIoSendDataReplayTarget(config, socketIoClientOverride = null): SendDataReplayTargetPort {
  const socketIoClient = socketIoClientOverride || require("socket.io-client");
  const replayConfig = config.replay || (config.spool && config.spool.replay) || {};
  const targetTimeoutMs = replayConfig.targetTimeoutMs || 5000;
  const upstreamUrl = `http://${config.upstream.host}:${config.upstream.port}`;
  let socket = null;
  let connecting = null;

  return {
    async send(item) {
      const payload = payloadFromSpoolItem(item);
      if (!payload.ok) return Promise.resolve(payload);

      const connection = await connectedSocket();
      if (!connection.ok) return connection;

      try {
        connection.socket.emit("send_data", payload.value);
        return { ok: true as const };
      } catch (error) {
        closeSocket(connection.socket);
        return {
          ok: false as const,
          reason: sendDataFailureReasons.UPSTREAM_UNAVAILABLE,
          message: error && error.message ? error.message : "upstream Socket.IO emit failed",
        };
      }
    },
  };

  function connectedSocket() {
    if (socket && socket.connected) return Promise.resolve({ ok: true as const, socket });
    if (connecting) return connecting;

    connecting = new Promise((resolve) => {
      let settled = false;
      const candidate = socketIoClient(upstreamUrl, {
        transports: ["websocket", "polling"],
        forceNew: true,
        reconnection: false,
        timeout: targetTimeoutMs,
      });

      const done = (result) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        connecting = null;
        if (result.ok) {
          socket = candidate;
        } else {
          closeSocket(candidate);
        }
        resolve(result);
      };

      const timeout = setTimeout(() => {
        done({
          ok: false as const,
          reason: sendDataFailureReasons.UPSTREAM_TIMEOUT,
          message: "send_data replay timed out",
        });
      }, targetTimeoutMs);

      candidate.on("connect", () => {
        done({ ok: true as const, socket: candidate });
      });
      candidate.on("connect_error", (error) => {
        done({
          ok: false as const,
          reason: sendDataFailureReasons.UPSTREAM_UNAVAILABLE,
          message: error && error.message ? error.message : "upstream Socket.IO connection failed",
        });
      });
      candidate.on("connect_timeout", () => {
        done({
          ok: false as const,
          reason: sendDataFailureReasons.UPSTREAM_TIMEOUT,
          message: "upstream Socket.IO connection timed out",
        });
      });
      candidate.on("disconnect", () => {
        if (socket === candidate) socket = null;
      });
    });

    return connecting;
  }

  function closeSocket(socketToClose) {
    if (socket === socketToClose) socket = null;
    if (socketToClose && typeof socketToClose.close === "function") socketToClose.close();
  }
}

function payloadFromSpoolItem(item): SendDataReplayPayloadResult {
  if (!item || typeof item.payloadBase64 !== "string") {
    return {
      ok: false as const,
      reason: sendDataFailureReasons.INVALID_PAYLOAD,
      message: "send_data spool item has no payloadBase64",
    };
  }

  let buffer;
  try {
    buffer = Buffer.from(item.payloadBase64, "base64");
  } catch (error) {
    return {
      ok: false as const,
      reason: sendDataFailureReasons.INVALID_PAYLOAD,
      message: error.message,
    };
  }

  if (item.payloadEncoding === "binary") return { ok: true as const, value: buffer };
  if (item.payloadEncoding === "string") return { ok: true as const, value: buffer.toString("binary") };
  return {
    ok: false as const,
    reason: sendDataFailureReasons.INVALID_PAYLOAD,
    message: `unsupported send_data payload encoding ${item.payloadEncoding}`,
  };
}

module.exports = { createSocketIoSendDataReplayTarget, payloadFromSpoolItem };
