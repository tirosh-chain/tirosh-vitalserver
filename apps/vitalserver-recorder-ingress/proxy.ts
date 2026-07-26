"use strict";

const { loadConfig } = require("./src/config");
const { createRecorderIngressServer } = require("./src/composition/recorder-ingress-composition");

const config = loadConfig(process.env);
const server = createRecorderIngressServer(config);
let shuttingDown = false;

start().catch((error) => {
  console.error(`[recorder-ingress] startup failed: ${errorMessage(error)}`);
  process.exit(1);
});

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

async function start() {
  if (typeof server.prepareStartup === "function") {
    await server.prepareStartup();
  }
  server.listen(config.listenPort, () => {
    console.log(
      `[recorder-ingress] listening on :${config.listenPort}, upstream=${config.upstream.host}:${config.upstream.port}, redis=${config.redis.host}:${config.redis.port}`
    );
  });
}

async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[recorder-ingress] ${signal} received, preparing shutdown`);

  const closed = closeServer(server);
  try {
    if (typeof server.prepareShutdown === "function") {
      const result = await server.prepareShutdown();
      console.log(`[recorder-ingress] shutdown raw archive export result=${JSON.stringify(result)}`);
    }
  } catch (error) {
    console.error(`[recorder-ingress] shutdown raw archive export failed: ${errorMessage(error)}`);
  }
  await Promise.race([closed, delay(1000)]);
  process.exit(0);
}

function closeServer(server) {
  return new Promise((resolve) => {
    try {
      server.close(() => resolve(null));
    } catch (_error) {
      resolve(null);
    }
  });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function errorMessage(error) {
  return error && error.message ? error.message : String(error);
}
