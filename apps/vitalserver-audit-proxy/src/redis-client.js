"use strict";

const net = require("net");

function createRedisClient(config) {
  return {
    command(args, callback) {
      const socket = net.createConnection({ host: config.host, port: config.port });
      let settled = false;
      let data = "";
      const done = (error) => {
        if (settled) return;
        settled = true;
        socket.destroy();
        if (callback) callback(error || null);
      };

      socket.setTimeout(config.timeoutMs);
      socket.on("connect", () => socket.write(encodeResp(args)));
      socket.on("data", (chunk) => {
        data += chunk.toString("utf8");
        if (data[0] === "-") done(new Error(data.slice(1).trim()));
        else if (data.length > 0) done();
      });
      socket.on("error", done);
      socket.on("timeout", () => done(new Error("redis command timeout")));
    },
  };
}

function encodeResp(args) {
  return `*${args.length}\r\n${args.map((arg) => {
    const value = Buffer.from(String(arg));
    return `$${value.length}\r\n${value.toString()}\r\n`;
  }).join("")}`;
}

module.exports = { createRedisClient };
