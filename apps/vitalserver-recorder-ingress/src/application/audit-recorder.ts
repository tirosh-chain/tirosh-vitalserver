"use strict";

const { createAuditEnvelope } = require("../domain/audit-envelope");

function createAuditRecorder(config, sinks) {
  return {
    record(eventType, fields) {
      if (!config.enabled) return;
      const event = createAuditEnvelope(eventType, fields);
      for (const sink of sinks) {
        sink.write(event);
      }
    },
  };
}

module.exports = { createAuditRecorder };
