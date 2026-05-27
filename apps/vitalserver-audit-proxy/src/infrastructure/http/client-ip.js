"use strict";

function createClientIpSelector(config) {
  return {
    select(req) {
      const headers = req.headers || {};
      const remote = normalizeIp(req.socket && req.socket.remoteAddress);
      const candidates = [
        ["x-forwarded-for", headers["x-forwarded-for"]],
        ["x-real-ip", headers["x-real-ip"]],
        ["forwarded", forwardedFor(headers)],
        ["x-client-ip", headers["x-client-ip"]],
      ];

      if (config.trustProxy) {
        for (const [source, value] of candidates) {
          const ip = normalizeIp(value);
          if (ip) {
            return { selected_ip: ip, selected_source: source, remote_address: remote, trust_proxy: true };
          }
        }
      }

      return {
        selected_ip: remote,
        selected_source: "remote-address",
        remote_address: remote,
        trust_proxy: config.trustProxy,
      };
    },
  };
}

function normalizeIp(value) {
  if (!value) return "";
  let next = String(value).split(",")[0].trim();
  if (next.startsWith("for=")) {
    const match = next.match(/for="?\[?([^\]";,]+)\]?/i);
    next = match ? match[1] : next;
  }
  if (next.startsWith("::ffff:")) next = next.slice(7);
  if (next.startsWith("[") && next.endsWith("]")) next = next.slice(1, -1);
  return next;
}

function forwardedFor(headers) {
  const forwarded = headers.forwarded || "";
  if (!forwarded) return "";
  const match = String(forwarded).split(",")[0].match(/for="?\[?([^\]";,]+)\]?/i);
  return match ? match[1] : "";
}

module.exports = { createClientIpSelector, normalizeIp };
