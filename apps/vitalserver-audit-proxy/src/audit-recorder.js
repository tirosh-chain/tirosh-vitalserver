"use strict";

const { mask } = require("./redaction");

function createAuditRecorder(config, redis, metrics) {
  return {
    record(eventType, fields) {
      if (!config.enabled) return;
      const payload = {
        schema_version: 1,
        source: "vitalserver-audit-proxy",
        event_type: eventType,
        ts: new Date().toISOString(),
        ts_unix_ms: Date.now(),
        ...mask(fields || {}),
      };
      const line = JSON.stringify(payload);
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

module.exports = { createAuditRecorder };
