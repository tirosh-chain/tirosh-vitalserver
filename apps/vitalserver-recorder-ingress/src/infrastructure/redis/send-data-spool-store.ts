"use strict";

function createRedisSendDataSpoolStore(config, redis) {
  return {
    append(item) {
      return new Promise((resolve) => {
        redis.command(["RPUSH", config.listKey, JSON.stringify(item)], (error, reply) => {
          if (error) {
            resolve({ ok: false, error });
            return;
          }
          resolve({ ok: true, depth: Number.isFinite(reply) ? reply : null });
        });
      });
    },
  };
}

module.exports = { createRedisSendDataSpoolStore };
