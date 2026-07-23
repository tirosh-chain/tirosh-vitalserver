"use strict";

const { sendDataIngressModes } = require("./domain/send-data-ingress-contracts");

const MIB = 1024 * 1024;
const DEFAULT_REPLAY_MAX_BYTES_PER_SECOND = 20 * MIB;
const DEFAULT_REPLAY_MIN_BYTES_PER_SECOND = 1 * MIB;
const DEFAULT_REPLAY_MIN_ITEMS_PER_TICK = 50;
const DEFAULT_REPLAY_MAX_ITEMS_PER_TICK = 1000;
const DEFAULT_REPLAY_MIN_CONCURRENCY = 1;
const DEFAULT_REPLAY_MAX_CONCURRENCY = 8;
const DEFAULT_MAX_PENDING_ITEMS = 100000;
const DEFAULT_MAX_REPLAYED_ITEMS = 10000;
const DEFAULT_MAX_REALTIME_PENDING_ITEMS = 2000;
const DEFAULT_RAW_ARCHIVE_MAX_FILE_BYTES = 512 * MIB;
const DEFAULT_RAW_ARCHIVE_MAX_FILES = 24;
const DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_QUIET_MS = 5 * 60 * 1000;
const DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS = 60 * 1000;
const DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_RETRY_DELAY_MS = 60 * 1000;
const DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_REQUEST_TIMEOUT_MS = 5 * 60 * 1000;

function loadConfig(env) {
  const sendDataMode = sendDataIngressModeEnv(env, "RECORDER_INGRESS_SEND_DATA_MODE", sendDataIngressModes.SPOOL_AND_REPLAY);
  const upstreamHost = env.RECORDER_INGRESS_UPSTREAM_HOST || "app";
  const upstreamPort = numberEnv(env, "RECORDER_INGRESS_UPSTREAM_PORT", 80);
  const replayMaxBytesPerSecond = numberEnv(
    env,
    "RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND",
    DEFAULT_REPLAY_MAX_BYTES_PER_SECOND
  );
  return {
    listenPort: numberEnv(env, "RECORDER_INGRESS_PORT", 8080),
    observability: {
      enabled: booleanEnv(
        env,
        "RECORDER_INGRESS_OBSERVABILITY_ENABLED",
        true
      ),
      ledgerDirectory: env.RECORDER_INGRESS_OBSERVABILITY_LEDGER_DIRECTORY
        || "/var/lib/vitalserver-recorder-ingress/observability",
      maxRequestBytes: numberEnv(
        env,
        "RECORDER_INGRESS_OBSERVABILITY_MAX_REQUEST_BYTES",
        5 * MIB
      ),
      database: {
        host: env.RECORDER_INGRESS_POSTGRES_HOST || "postgres",
        port: numberEnv(env, "RECORDER_INGRESS_POSTGRES_PORT", 5432),
        database: env.RECORDER_INGRESS_POSTGRES_DATABASE || "vitalserver",
        user: env.RECORDER_INGRESS_POSTGRES_USER || "vitalserver",
        password: env.RECORDER_INGRESS_POSTGRES_PASSWORD || "vitalserver",
        maxConnections: numberEnv(
          env,
          "RECORDER_INGRESS_POSTGRES_MAX_CONNECTIONS",
          10
        ),
      },
      projector: {
        intervalMs: numberEnv(
          env,
          "RECORDER_INGRESS_OBSERVABILITY_PROJECTOR_INTERVAL_MS",
          1000
        ),
        batchSize: numberEnv(
          env,
          "RECORDER_INGRESS_OBSERVABILITY_PROJECTOR_BATCH_SIZE",
          100
        ),
      },
      freshnessToleranceMultiplier: numberEnv(
        env,
        "RECORDER_INGRESS_OBSERVABILITY_FRESHNESS_MULTIPLIER",
        3
      ),
      freshnessAllowanceSeconds: numberEnv(
        env,
        "RECORDER_INGRESS_OBSERVABILITY_FRESHNESS_ALLOWANCE_SECONDS",
        30
      ),
    },
    upstream: {
      host: upstreamHost,
      port: upstreamPort,
      timeoutMs: numberEnv(env, "RECORDER_INGRESS_UPSTREAM_TIMEOUT_MS", 30000),
    },
    nativeVitalUploads: {
      statePath: env.RECORDER_INGRESS_NATIVE_UPLOAD_STATE_PATH
        || "/var/lib/vitalserver-recorder-ingress/recovery/native-vital-uploads.json",
      reconciliation: {
        intervalMs: numberEnv(
          env,
          "RECORDER_INGRESS_NATIVE_UPLOAD_RECONCILE_INTERVAL_MS",
          5000
        ),
        maxAttempts: numberEnv(
          env,
          "RECORDER_INGRESS_NATIVE_UPLOAD_RECONCILE_MAX_ATTEMPTS",
          12
        ),
      },
      vitalServerIndex: {
        baseUrl: env.RECORDER_INGRESS_VITALSERVER_URL
          || `http://${upstreamHost}:${upstreamPort}`,
        adminPassword: env.VITALSERVER_ADMIN_PASSWORD || "",
        timeoutMs: numberEnv(
          env,
          "RECORDER_INGRESS_NATIVE_UPLOAD_INDEX_TIMEOUT_MS",
          5000
        ),
      },
    },
    redis: {
      host: env.VITALSERVER_REDIS_HOST || env.RECORDER_INGRESS_REDIS_HOST || "redis",
      port: numberEnv(env, "VITALSERVER_REDIS_PORT", numberEnv(env, "RECORDER_INGRESS_REDIS_PORT", 6379)),
      timeoutMs: numberEnv(env, "RECORDER_INGRESS_REDIS_TIMEOUT_MS", 1500),
      maxQueueLength: numberEnv(env, "RECORDER_INGRESS_REDIS_MAX_QUEUE_LENGTH", 50000),
      retry: {
        maxAttempts: numberEnv(env, "RECORDER_INGRESS_REDIS_RETRY_MAX_ATTEMPTS", 3),
        baseDelayMs: numberEnv(env, "RECORDER_INGRESS_REDIS_RETRY_BASE_DELAY_MS", 25),
        maxDelayMs: numberEnv(env, "RECORDER_INGRESS_REDIS_RETRY_MAX_DELAY_MS", 500),
        jitterRatio: ratioEnv(env, "RECORDER_INGRESS_REDIS_RETRY_JITTER_RATIO", 0.2),
      },
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
      inFlightListKey: env.RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST || "vitalserver:recorder_ingress:send_data:in_flight",
      replayedListKey: env.RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST || "vitalserver:recorder_ingress:send_data:replayed",
      deadLetterListKey: env.RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST || "vitalserver:recorder_ingress:send_data:dead_letter",
      maxReplayedItems: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_REPLAYED_MAX_ITEMS", DEFAULT_MAX_REPLAYED_ITEMS),
      maxRealtimePendingItems: numberEnv(
        env,
        "RECORDER_INGRESS_SEND_DATA_REALTIME_MAX_PENDING_ITEMS",
        DEFAULT_MAX_REALTIME_PENDING_ITEMS
      ),
      maxPendingItems: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS", DEFAULT_MAX_PENDING_ITEMS),
      maxPendingBytes: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES", 512 * 1024 * 1024),
      maxPayloadBytes: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES", 10 * 1024 * 1024),
      replay: {
        enabled: booleanEnv(
          env,
          "RECORDER_INGRESS_SEND_DATA_REPLAY_ENABLED",
          sendDataMode === sendDataIngressModes.SPOOL_AND_REPLAY
        ),
        intervalMs: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS", 1000),
        batchSize: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE", DEFAULT_REPLAY_MAX_ITEMS_PER_TICK),
        maxAttempts: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS", 3),
        maxBytesPerSecond: replayMaxBytesPerSecond,
        targetTimeoutMs: numberEnv(env, "RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS", 5000),
        adaptive: {
          enabled: booleanEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_ENABLED",
            false
          ),
          minBytesPerSecond: numberEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_BYTES_PER_SECOND",
            DEFAULT_REPLAY_MIN_BYTES_PER_SECOND
          ),
          maxBytesPerSecond: numberEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_BYTES_PER_SECOND",
            replayMaxBytesPerSecond
          ),
          minItemsPerTick: numberEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_ITEMS_PER_TICK",
            DEFAULT_REPLAY_MIN_ITEMS_PER_TICK
          ),
          maxItemsPerTick: numberEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_ITEMS_PER_TICK",
            DEFAULT_REPLAY_MAX_ITEMS_PER_TICK
          ),
          minConcurrency: numberEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_CONCURRENCY",
            DEFAULT_REPLAY_MIN_CONCURRENCY
          ),
          maxConcurrency: numberEnv(
            env,
            "RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_CONCURRENCY",
            DEFAULT_REPLAY_MAX_CONCURRENCY
          ),
        },
      },
    },
    memoryGuard: {
      enabled: false,
    },
    failureLog: {
      enabled: env.RECORDER_INGRESS_FAILURE_LOG_ENABLED !== "0",
      path: env.RECORDER_INGRESS_FAILURE_LOG_PATH
        || "/var/log/vitalserver-recorder-ingress/failures/send-data-failures.jsonl",
    },
    rawArchive: {
      enabled: env.RECORDER_INGRESS_RAW_ARCHIVE_ENABLED !== "0",
      path: env.RECORDER_INGRESS_RAW_ARCHIVE_PATH
        || "/var/lib/vitalserver-recorder-ingress/raw/send-data-raw.jsonl",
      maxFileBytes: numberEnv(
        env,
        "RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILE_BYTES",
        DEFAULT_RAW_ARCHIVE_MAX_FILE_BYTES
      ),
      maxFiles: numberEnv(env, "RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILES", DEFAULT_RAW_ARCHIVE_MAX_FILES),
      autoExport: {
        enabled: booleanEnv(env, "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_ENABLED", true),
        quietWindowMs: numberEnv(
          env,
          "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_QUIET_MS",
          DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_QUIET_MS
        ),
        scanIntervalMs: numberEnv(
          env,
          "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS",
          DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS
        ),
        cursorStableMs: numberEnv(
          env,
          "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_CURSOR_STABLE_MS",
          DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS
        ),
        retryDelayMs: numberEnv(
          env,
          "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_RETRY_DELAY_MS",
          DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_RETRY_DELAY_MS
        ),
        maxAttempts: numberEnv(env, "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_MAX_ATTEMPTS", 3),
        requestTimeoutMs: numberEnv(
          env,
          "RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_REQUEST_TIMEOUT_MS",
          DEFAULT_RAW_ARCHIVE_AUTO_EXPORT_REQUEST_TIMEOUT_MS
        ),
        exportUrl: env.RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_EXPORT_URL || "",
        outputDir: env.RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_OUTPUT_DIR
          || "/var/lib/vitalserver-recorder-ingress/recovery/vital-export",
        statePath: env.RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_STATE_PATH
          || "/var/lib/vitalserver-recorder-ingress/recovery/raw-archive-auto-export-state.json",
      },
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

function ratioEnv(env, name, fallback) {
  const value = Number.parseFloat(env[name] || "");
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function booleanEnv(env, name, fallback) {
  if (!Object.prototype.hasOwnProperty.call(env, name)) return fallback;
  if (env[name] === "") return fallback;
  return /^(1|true|yes)$/i.test(env[name] || "");
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
