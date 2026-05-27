"use strict";

function createRedisAuditEventStore(config, redis, metrics) {
  return {
    write(event) {
      const line = JSON.stringify(event);
      redis.command(["RPUSH", config.listKey, line], (error) => {
        if (error) {
          metrics.auditWriteFailures += 1;
          console.error("[audit-proxy] audit redis write failed:", error.message);
          return;
        }
        if (config.maxLen > 0) {
          redis.command(["LTRIM", config.listKey, String(-config.maxLen), "-1"]);
        }
      });
    },
  };
}

module.exports = { createRedisAuditEventStore };
