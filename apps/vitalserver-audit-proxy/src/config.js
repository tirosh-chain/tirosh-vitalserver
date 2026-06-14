"use strict";

function loadConfig(env) {
  return {
    listenPort: numberEnv(env, "AUDIT_PROXY_PORT", 8080),
    upstream: {
      host: env.AUDIT_PROXY_UPSTREAM_HOST || "app",
      port: numberEnv(env, "AUDIT_PROXY_UPSTREAM_PORT", 80),
      timeoutMs: numberEnv(env, "AUDIT_PROXY_UPSTREAM_TIMEOUT_MS", 30000),
    },
    redis: {
      host: env.VITALSERVER_REDIS_HOST || env.AUDIT_PROXY_REDIS_HOST || "redis",
      port: numberEnv(env, "VITALSERVER_REDIS_PORT", numberEnv(env, "AUDIT_PROXY_REDIS_PORT", 6379)),
      timeoutMs: numberEnv(env, "AUDIT_PROXY_REDIS_TIMEOUT_MS", 1500),
    },
    audit: {
      enabled: env.VITALSERVER_AUDIT_ENABLED !== "0",
      listKey: env.VITALSERVER_AUDIT_REDIS_LIST || "vitalserver:audit_events",
      maxLen: numberEnv(env, "VITALSERVER_AUDIT_REDIS_MAXLEN", 10000),
      maxBodyBytes: numberEnv(env, "AUDIT_PROXY_MAX_BODY_BYTES", 5 * 1024 * 1024),
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
    clientIp: {
      trustProxy: /^(1|true|yes)$/i.test(env.VITALSERVER_TRUST_PROXY || "1"),
    },
    vitalServer: {
      ipRewrite: {
        enabled: env.AUDIT_PROXY_VR_IP_REWRITE_ENABLED !== "0",
        verifyDelaysMs: numberListEnv(env, "AUDIT_PROXY_VR_IP_VERIFY_DELAYS_MS", [250, 1000]),
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

function numberListEnv(env, name, fallback) {
  const raw = env[name];
  if (!raw) return fallback;
  const values = raw
    .split(",")
    .map((item) => Number.parseInt(item.trim(), 10));
  return values.every(Number.isFinite) ? values : fallback;
}

module.exports = { loadConfig };
