import type { AuditRecorderPort } from "./ports/inbound/audit-recorder-port";
import type { AuditSinkPort } from "./ports/outbound/audit-sink-port";

"use strict";

const { createAuditEnvelope } = require("../domain/audit-envelope");

type AuditRecorderDependencies = {
  enabled: boolean;
};

function createAuditRecorder(config: AuditRecorderDependencies, sinks: AuditSinkPort[]): AuditRecorderPort {
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
