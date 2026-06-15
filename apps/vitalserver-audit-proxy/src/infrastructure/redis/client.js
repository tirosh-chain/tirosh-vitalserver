"use strict";

const net = require("net");

function createRedisClient(config) {
  return {
    command(args, callback) {
      const socket = net.createConnection({ host: config.host, port: config.port });
      let settled = false;
      let data = "";
      const done = (error, reply) => {
        if (settled) return;
        settled = true;
        socket.destroy();
        if (callback) callback(error || null, reply);
      };

      socket.setTimeout(config.timeoutMs);
      socket.on("connect", () => socket.write(encodeResp(args)));
      socket.on("data", (chunk) => {
        data += chunk.toString("utf8");
        const reply = parseRespReply(data);
        if (!reply.complete) return;
        done(reply.error || null, reply.value);
      });
      socket.on("error", done);
      socket.on("timeout", () => done(new Error("redis command timeout")));
    },
  };
}

function parseRespReply(data) {
  if (!data) return { complete: false };
  const prefix = data[0];
  if (prefix === "-") {
    const end = data.indexOf("\r\n");
    if (end < 0) return { complete: false };
    return { complete: true, error: new Error(data.slice(1, end)) };
  }
  if (prefix === "+" || prefix === ":") {
    const end = data.indexOf("\r\n");
    if (end < 0) return { complete: false };
    const value = data.slice(1, end);
    return { complete: true, value: prefix === ":" ? Number.parseInt(value, 10) : value };
  }
  if (prefix === "$") {
    const end = data.indexOf("\r\n");
    if (end < 0) return { complete: false };
    const byteLength = Number.parseInt(data.slice(1, end), 10);
    if (!Number.isFinite(byteLength)) {
      return { complete: true, error: new Error("invalid redis bulk string length") };
    }
    if (byteLength < 0) return { complete: true, value: null };
    const valueStart = end + 2;
    const valueEnd = valueStart + byteLength;
    if (data.length < valueEnd + 2) return { complete: false };
    return { complete: true, value: data.slice(valueStart, valueEnd) };
  }
  return { complete: true, error: new Error("unsupported redis reply") };
}

function encodeResp(args) {
  return `*${args.length}\r\n${args.map((arg) => {
    const value = Buffer.from(String(arg));
    return `$${value.length}\r\n${value.toString()}\r\n`;
  }).join("")}`;
}

module.exports = { createRedisClient, parseRespReply };
