import { createServer } from "node:http";
import { parseArgs } from "node:util";

import { Server as SocketIoServer } from "socket.io";

const { values } = parseArgs({
  options: {
    listen: { type: "string" },
  },
});

const listen = values.listen;
if (listen === undefined) {
  throw new Error("--listen is required");
}
const address = parseLoopbackAddress(listen);
let acceptedPacketCount = 0;
const server = createServer((request, response) => {
  if (request.method !== "GET" || request.url !== "/healthz") {
    response.writeHead(404).end();
    return;
  }
  const document = Buffer.from(JSON.stringify({
    schemaVersion: "v1",
    state: "ready",
    acceptedPacketCount,
  }));
  response.writeHead(200, {
    "content-type": "application/json",
    "content-length": String(document.byteLength),
  });
  response.end(document);
});
const sockets = new SocketIoServer(server, { transports: ["websocket", "polling"] });
sockets.on("connection", (socket) => {
  socket.on("send_data", (payload: unknown, acknowledgement: unknown) => {
    if ((typeof payload !== "string" && !Buffer.isBuffer(payload)) || typeof acknowledgement !== "function") {
      return;
    }
    acceptedPacketCount += 1;
    (acknowledgement as (value: unknown) => void)({
      schemaVersion: "v1",
      state: "accepted",
    });
  });
});

server.listen(address.port, address.host);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    sockets.close(() => {
      server.close(() => process.exit(0));
    });
  });
}

function parseLoopbackAddress(value: string): { host: "127.0.0.1" | "::1"; port: number } {
  const separator = value.lastIndexOf(":");
  if (separator < 1) {
    throw new Error("--listen must be a loopback host and explicit port");
  }
  const host = value.slice(0, separator);
  const port = Number(value.slice(separator + 1));
  if ((host !== "127.0.0.1" && host !== "::1") || !Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("--listen must be a loopback host and explicit port");
  }
  return { host, port };
}
