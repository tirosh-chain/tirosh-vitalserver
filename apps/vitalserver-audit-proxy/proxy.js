"use strict";

const { loadConfig } = require("./src/config");
const { createAuditProxyServer } = require("./src/infrastructure/http/proxy-server");

const config = loadConfig(process.env);
const server = createAuditProxyServer(config);

server.listen(config.listenPort, () => {
  console.log(
    `[audit-proxy] listening on :${config.listenPort}, upstream=${config.upstream.host}:${config.upstream.port}, redis=${config.redis.host}:${config.redis.port}`
  );
});
