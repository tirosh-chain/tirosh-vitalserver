"use strict";

const { loadConfig } = require("./src/config");
const { createRecorderIngressServer } = require("./src/composition/recorder-ingress-composition");

const config = loadConfig(process.env);
const server = createRecorderIngressServer(config);

server.listen(config.listenPort, () => {
  console.log(
    `[recorder-ingress] listening on :${config.listenPort}, upstream=${config.upstream.host}:${config.upstream.port}, redis=${config.redis.host}:${config.redis.port}`
  );
});
