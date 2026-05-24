"use strict";

function createVrIdentityStore(redis, metrics) {
  return {
    setRecorderIp(vrcode, selectedIp, delayMs) {
      if (!vrcode || !selectedIp) return;
      setTimeout(() => {
        redis.command(["SET", `ip_${vrcode}`, selectedIp], (error) => {
          if (error) {
            metrics.redisIpWriteFailures += 1;
            console.error("[audit-proxy] ip write failed:", error.message);
          }
        });
      }, delayMs);
    },
  };
}

module.exports = { createVrIdentityStore };
