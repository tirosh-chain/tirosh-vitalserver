"use strict";

const { sendDataIngressModes } = require("./domain/send-data-ingress-contracts");

function loadConfig(env) {
  const sendDataMode = sendDataIngressModeEnv(env, "RECORDER_INGRESS_SEND_DATA_MODE", sendDataIngressModes.MIRROR_SPOOL);
  return {
    listenPort: numberEnv(env, "RECORDER_INGRESS_PORT", 8080),
    upstream: {
      host: env.RECORDER_INGRESS_UPSTREAM_HOST || "app",
      port: numberEnv(env, "RECORDER_INGRESS_UPSTREAM_PORT", 80),
      timeoutMs: numberEnv(env, "RECORDER_INGRESS_UPSTREAM_TIMEOUT_MS", 30000),
    },
    redis: {
      host: env.VITALSERVER_REDIS_HOST || env.RECORDER_INGRESS_REDIS_HOST || "redis",
      port: numberEnv(env, "VITALSERVER_REDIS_PORT", numberEnv(env, "RECORDER_INGRESS_REDIS_PORT", 6379)),
      timeoutMs: numberEnv(env, "RECORDER_INGRESS_REDIS_TIMEOUT_MS", 1500),
    },
    audit: {
      enabled: env.VITALSERVER_AUDIT_ENABLED !== "0",
      listKey: env.VITALSERVER_AUDIT_REDIS_LIST || "vitalserver:audit_events",
      maxLen: numberEnv(env, "VITALSERVER_AUDIT_REDIS_MAXLEN", 10000),
      maxBodyBytes: numberEnv(env, "RECORDER_INGRESS_MAX_BODY_BYTES", 5 * 1024 * 1024),
      log: {
        enabled: env.VITALSERVER_AUDIT_FILE_ENABLED !== "0",
        path: env.VITALSERVER_AUDIT_LOG_PATH || "/var/log/vitalserver-audit/audit-events.log",
        format: logFormatEnv(env, "VITALSERVER_AUDIT_LOG_FORMAT", "json"),
      },
      stdout: {
        enabled: env.VITALSERVER_AUDIT_STDOUT_ENABLED !== "0",
        format: logFormatEnv(env, "VITALSERVER_AUDIT_STDOUT_FORMAT", logFormatEnv(env, "VITALSERVER_AUDIT_LOG_FORMAT", "json")),
      },
    },
    spool: {
      enabled: sendDataMode !== sendDataIngressModes.PASSTHROUGH,
      mode: sendDataMode,
      storage: "redis_list",
      listKey: env.RECORDER_INGRESS_SEND_DATA_REDIS_LIST || "vitalserver:recorder_ingress:send_data:pending",
      maxPendingItems: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS", 10000),
      maxPendingBytes: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES", 512 * 1024 * 1024),
      maxPayloadBytes: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES", 10 * 1024 * 1024),
    },
    clientIp: {
      trustProxy: /^(1|true|yes)$/i.test(env.VITALSERVER_TRUST_PROXY || "1"),
    },
    vitalServer: {
      ipRewrite: {
        enabled: env.RECORDER_INGRESS_VR_IP_REWRITE_ENABLED !== "0",
        verifyDelaysMs: numberListEnv(env, "RECORDER_INGRESS_VR_IP_VERIFY_DELAYS_MS", [250, 1000]),
      },
    },
  };
}

function numberEnv(env, name, fallback) {
  const value = Number.parseInt(env[name] || "", 10);
  return Number.isFinite(value) ? value : fallback;
}

function logFormatEnv(env, name, fallback) {
  return env[name] === "logfmt" ? "logfmt" : fallback;
}

function sendDataIngressModeEnv(env, name, fallback) {
  const value = env[name] || fallback;
  return Object.values(sendDataIngressModes).includes(value) ? value : fallback;
}

function numberListEnv(env, name, fallback) {
  const raw = env[name];
  if (!raw) return fallback;
  const values = raw
    .split(",")
    .map((item) => Number.parseInt(item.trim(), 10));
  return values.every(Number.isFinite) ? values : fallback;
}

module.exports = { loadConfig };
