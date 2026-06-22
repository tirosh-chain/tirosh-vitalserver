"use strict";

const { createMetrics } = require("../src/observability/metrics");

function contextFor(vrcode) {
  return {
    request_id: "request-1",
    connection_id: "connection-1",
    joined_vrcode: vrcode || null,
    last_command: null,
    metrics_vrcode: null,
    pending_binary_event: null,
    ip: {
      selected_ip: "172.31.0.152",
      selected_source: "x-forwarded-for",
      remote_address: "192.168.97.1",
      trust_proxy: true,
    },
  };
}

function metrics() {
  return createMetrics();
}

module.exports = { contextFor, metrics };
