"use strict";

const assert = require("assert");
const test = require("node:test");
const { loadConfig } = require("../../src/config");

const MIB = 1024 * 1024;

test("config loads explicit redis ip rewrite policy", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_VR_IP_REWRITE_ENABLED: "0",
    RECORDER_INGRESS_VR_IP_VERIFY_DELAYS_MS: "10,250",
  }).vitalServer.ipRewrite, {
    enabled: false,
    verifyDelaysMs: [10, 250],
  });
});

test("config loads explicit redis availability policy", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_REDIS_TIMEOUT_MS: "2500",
    RECORDER_INGRESS_REDIS_MAX_QUEUE_LENGTH: "1234",
    RECORDER_INGRESS_REDIS_RETRY_MAX_ATTEMPTS: "5",
    RECORDER_INGRESS_REDIS_RETRY_BASE_DELAY_MS: "50",
    RECORDER_INGRESS_REDIS_RETRY_MAX_DELAY_MS: "2000",
    RECORDER_INGRESS_REDIS_RETRY_JITTER_RATIO: "0.5",
  }).redis, {
    host: "redis",
    port: 6379,
    timeoutMs: 2500,
    maxQueueLength: 1234,
    retry: {
      maxAttempts: 5,
      baseDelayMs: 50,
      maxDelayMs: 2000,
      jitterRatio: 0.5,
    },
  });
});

test("config enables bounded spool and replay by default", () => {
  assert.deepStrictEqual(loadConfig({}).spool, {
    enabled: true,
    mode: "spool_and_replay",
    storage: "redis_list",
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    inFlightListKey: "vitalserver:recorder_ingress:send_data:in_flight",
    replayedListKey: "vitalserver:recorder_ingress:send_data:replayed",
    deadLetterListKey: "vitalserver:recorder_ingress:send_data:dead_letter",
    maxReplayedItems: 10000,
    maxRealtimePendingItems: 2000,
    maxPendingItems: 100000,
    maxPendingBytes: 512 * 1024 * 1024,
    maxPayloadBytes: 10 * 1024 * 1024,
    replay: {
      enabled: true,
      intervalMs: 1000,
      batchSize: 1000,
      maxAttempts: 3,
      maxBytesPerSecond: 20 * MIB,
      targetTimeoutMs: 5000,
      adaptive: {
        enabled: true,
        minBytesPerSecond: 1 * MIB,
        maxBytesPerSecond: 20 * MIB,
        minItemsPerTick: 50,
        maxItemsPerTick: 1000,
        minConcurrency: 1,
        maxConcurrency: 8,
      },
    },
  });
  assert.deepStrictEqual(loadConfig({}).memoryGuard, {
    runtimeStatePath: "/run/tirosh/runtime/runtime-state.json",
    maxAgeMs: 15000,
  });
  assert.deepStrictEqual(loadConfig({}).failureLog, {
    enabled: true,
    path: "/var/log/vitalserver-recorder-ingress/failures/send-data-failures.jsonl",
  });
  assert.deepStrictEqual(loadConfig({}).rawArchive, {
    enabled: true,
    path: "/var/lib/vitalserver-recorder-ingress/raw/send-data-raw.jsonl",
    maxFileBytes: 512 * MIB,
    maxFiles: 24,
    autoExport: {
      enabled: false,
      quietWindowMs: 300000,
      scanIntervalMs: 60000,
      cursorStableMs: 60000,
      retryDelayMs: 60000,
      maxAttempts: 3,
      requestTimeoutMs: 300000,
      recoverUrl: "http://testkit:18322/raw-archive/recover-vital",
      vitalserverUrl: "http://app:80",
      uploadEndpoint: "/upload",
      outputDir: "/var/lib/vitalserver-recorder-ingress/recovery/vital-export",
      statePath: "/var/lib/vitalserver-recorder-ingress/recovery/raw-archive-auto-export-state.json",
    },
  });
});

test("config loads explicit send_data failure log settings", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_FAILURE_LOG_ENABLED: "0",
    RECORDER_INGRESS_FAILURE_LOG_PATH: "/external/send-data-failures.jsonl",
  }).failureLog, {
    enabled: false,
    path: "/external/send-data-failures.jsonl",
  });
});

test("config loads explicit send_data raw archive settings", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_RAW_ARCHIVE_ENABLED: "0",
    RECORDER_INGRESS_RAW_ARCHIVE_PATH: "/external/send-data-raw.jsonl",
    RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILE_BYTES: "1234",
    RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILES: "3",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_ENABLED: "1",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_QUIET_MS: "600000",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS: "10000",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_CURSOR_STABLE_MS: "20000",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_RETRY_DELAY_MS: "30000",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_MAX_ATTEMPTS: "5",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_REQUEST_TIMEOUT_MS: "40000",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_RECOVER_URL: "http://recover.test/raw",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_VITALSERVER_URL: "http://app.test",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_UPLOAD_ENDPOINT: "/upload_vital.php",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_OUTPUT_DIR: "/external/export",
    RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_STATE_PATH: "/external/state.json",
  }).rawArchive, {
    enabled: false,
    path: "/external/send-data-raw.jsonl",
    maxFileBytes: 1234,
    maxFiles: 3,
    autoExport: {
      enabled: true,
      quietWindowMs: 600000,
      scanIntervalMs: 10000,
      cursorStableMs: 20000,
      retryDelayMs: 30000,
      maxAttempts: 5,
      requestTimeoutMs: 40000,
      recoverUrl: "http://recover.test/raw",
      vitalserverUrl: "http://app.test",
      uploadEndpoint: "/upload_vital.php",
      outputDir: "/external/export",
      statePath: "/external/state.json",
    },
  });
});

test("config supports explicit send_data passthrough mode", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_SEND_DATA_MODE: "passthrough",
    RECORDER_INGRESS_SEND_DATA_REDIS_LIST: "custom:list",
    RECORDER_INGRESS_SEND_DATA_REPLAYED_MAX_ITEMS: "123",
    RECORDER_INGRESS_SEND_DATA_REALTIME_MAX_PENDING_ITEMS: "456",
    RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS: "7",
    RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES: "11",
    RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES: "13",
  }).spool, {
    enabled: false,
    mode: "passthrough",
    storage: "redis_list",
    listKey: "custom:list",
    inFlightListKey: "vitalserver:recorder_ingress:send_data:in_flight",
    replayedListKey: "vitalserver:recorder_ingress:send_data:replayed",
    deadLetterListKey: "vitalserver:recorder_ingress:send_data:dead_letter",
    maxReplayedItems: 123,
    maxRealtimePendingItems: 456,
    maxPendingItems: 7,
    maxPendingBytes: 11,
    maxPayloadBytes: 13,
    replay: {
      enabled: false,
      intervalMs: 1000,
      batchSize: 1000,
      maxAttempts: 3,
      maxBytesPerSecond: 20 * MIB,
      targetTimeoutMs: 5000,
      adaptive: {
        enabled: true,
        minBytesPerSecond: 1 * MIB,
        maxBytesPerSecond: 20 * MIB,
        minItemsPerTick: 50,
        maxItemsPerTick: 1000,
        minConcurrency: 1,
        maxConcurrency: 8,
      },
    },
  });
});

test("config enables send_data replay for spool_and_replay mode", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_SEND_DATA_MODE: "spool_and_replay",
    RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST: "custom:inflight",
    RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST: "custom:replayed",
    RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST: "custom:dead",
    RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS: "250",
    RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE: "4",
    RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS: "5",
    RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND: String(2 * MIB),
    RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS: "750",
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_ENABLED: "0",
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_BYTES_PER_SECOND: String(2 * MIB),
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_BYTES_PER_SECOND: String(9 * MIB),
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_ITEMS_PER_TICK: "25",
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_ITEMS_PER_TICK: "500",
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_CONCURRENCY: "2",
    RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_CONCURRENCY: "6",
  }).spool.replay, {
    enabled: true,
    intervalMs: 250,
    batchSize: 4,
    maxAttempts: 5,
    maxBytesPerSecond: 2 * MIB,
    targetTimeoutMs: 750,
    adaptive: {
      enabled: false,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 9 * MIB,
      minItemsPerTick: 25,
      maxItemsPerTick: 500,
      minConcurrency: 2,
      maxConcurrency: 6,
    },
  });
  assert.strictEqual(loadConfig({
    RECORDER_INGRESS_SEND_DATA_MODE: "spool_and_replay",
    RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST: "custom:inflight",
    RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST: "custom:replayed",
    RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST: "custom:dead",
  }).spool.inFlightListKey, "custom:inflight");
});
