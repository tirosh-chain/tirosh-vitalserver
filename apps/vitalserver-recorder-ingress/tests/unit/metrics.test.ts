"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  createMetrics,
  configureSendDataRawArchive,
  configureSendDataSpool,
  metricsSnapshot,
  recordSendDataRawArchived,
  recordSendDataRawArchiveWriteFailed,
  recordSendDataRealtimeSkipped,
  recordSendDataObserved,
  recordSendDataReplayQueueDrained,
  recordSendDataReplayStarted,
  recordSendDataReplaySucceeded,
  recordSendDataSpoolSpooled,
} = require("../../src/observability/metrics");

test("metrics snapshot reports send_data throughput in bytes per second", () => {
  const metrics = createMetrics();

  recordSendDataObserved(metrics, "VR_1", { bytes: 1000 });
  recordSendDataSpoolSpooled(metrics, "VR_1", 1000, 1);
  recordSendDataReplaySucceeded(metrics, "VR_1", {
    payloadBytes: 400,
    receivedAt: new Date().toISOString(),
  });

  const throughput = metricsSnapshot(metrics).throughput;

  assert.strictEqual(throughput.windowSeconds, 10);
  assert.strictEqual(throughput.observedBytesPerSecond, 100);
  assert.strictEqual(throughput.spooledBytesPerSecond, 100);
  assert.strictEqual(throughput.replayedBytesPerSecond, 40);
  assert.strictEqual(throughput.queueGrowthBytesPerSecond, 60);
});

test("metrics snapshot reports failure log write failures distinctly", () => {
  const metrics = createMetrics();

  metrics.failureLogWriteFailures = 2;

  assert.strictEqual(metricsSnapshot(metrics).failureLogWriteFailures, 2);
});

test("metrics snapshot clears pending bytes when replay consumes final pending item", () => {
  const metrics = createMetrics();
  const item = {
    vrcode: "VR_1",
    payloadBytes: 1000,
    receivedAt: new Date().toISOString(),
  };

  recordSendDataSpoolSpooled(metrics, item.vrcode, 1200, 1);
  recordSendDataReplayStarted(metrics, item.vrcode, item);

  const snapshot = metricsSnapshot(metrics);

  assert.strictEqual(snapshot.spool.pendingItems, 0);
  assert.strictEqual(snapshot.spool.pendingBytes, 0);
  assert.strictEqual(snapshot.recorders[0].spool.pendingItems, 0);
  assert.strictEqual(snapshot.recorders[0].spool.pendingBytes, 0);
});

test("metrics snapshot uses explicit spool depth for replay pending items", () => {
  const metrics = createMetrics();
  configureSendDataSpool(metrics, {
    enabled: true,
    mode: "spool_and_replay",
    storage: "redis_list",
    replay: {
      enabled: true,
      batchSize: 50,
      maxBytesPerSecond: 1024,
    },
  });

  recordSendDataSpoolSpooled(metrics, "VR_1", 100, 7);
  recordSendDataSpoolSpooled(metrics, "VR_1", 100, 3);

  const snapshot = metricsSnapshot(metrics);

  assert.strictEqual(snapshot.spool.pendingItems, 3);
  assert.strictEqual(snapshot.replay.pendingItems, 3);
});

test("metrics snapshot clears recorder pending when replay queue is explicitly drained", () => {
  const metrics = createMetrics();
  configureSendDataSpool(metrics, {
    enabled: true,
    mode: "spool_and_replay",
    storage: "redis_list",
    replay: {
      enabled: true,
      batchSize: 50,
      maxBytesPerSecond: 1024,
    },
  });

  recordSendDataSpoolSpooled(metrics, "VR_1", 100, 2);
  recordSendDataSpoolSpooled(metrics, "VR_2", 100, 2);
  recordSendDataReplayQueueDrained(metrics);

  const snapshot = metricsSnapshot(metrics);

  assert.strictEqual(snapshot.spool.pendingItems, 0);
  assert.strictEqual(snapshot.replay.pendingItems, 0);
  assert.strictEqual(snapshot.recorders[0].spool.pendingItems, 0);
  assert.strictEqual(snapshot.recorders[0].replay.pendingItems, 0);
  assert.strictEqual(snapshot.recorders[1].spool.pendingItems, 0);
  assert.strictEqual(snapshot.recorders[1].replay.pendingItems, 0);
});

test("metrics snapshot reports realtime coverage for active observed recorders", () => {
  const metrics = createMetrics();
  const recentItem = {
    vrcode: "VR_1",
    payloadBytes: 100,
    receivedAt: new Date().toISOString(),
  };

  recordSendDataObserved(metrics, "VR_1", { bytes: 100 });
  recordSendDataObserved(metrics, "VR_2", { bytes: 100 });
  recordSendDataReplaySucceeded(metrics, "VR_1", recentItem);
  metrics.recorders.get("VR_1").activeConnections = 1;
  metrics.recorders.get("VR_2").activeConnections = 1;

  const coverage = metricsSnapshot(metrics).realtimeCoverage;

  assert.strictEqual(coverage.windowSeconds, 60);
  assert.strictEqual(coverage.observedRecorderCount, 2);
  assert.strictEqual(coverage.activeObservedRecorderCount, 2);
  assert.strictEqual(coverage.replayedRecorderCount, 1);
  assert.deepStrictEqual(coverage.activeRecordersMissingRecentReplay, ["VR_2"]);
  assert.strictEqual(coverage.minReplayedEventsPerRecorder, 1);
  assert.strictEqual(coverage.maxReplayedEventsPerRecorder, 1);
});

test("metrics snapshot reports recorder realtime skips without throwing", () => {
  const metrics = createMetrics();
  configureSendDataSpool(metrics, {
    enabled: true,
    mode: "spool_and_replay",
    storage: "redis_list",
    replay: {
      enabled: true,
      batchSize: 50,
      maxBytesPerSecond: 1024,
    },
  });

  recordSendDataSpoolSpooled(metrics, "VR_1", 100, 3);
  recordSendDataSpoolSpooled(metrics, "VR_1", 100, 3);
  recordSendDataSpoolSpooled(metrics, "VR_2", 100, 3);
  recordSendDataRealtimeSkipped(metrics, {
    skippedRealtimeItems: 2,
    skippedRealtimeBytes: 200,
    skippedRealtimeByRecorder: {
      VR_1: { items: 1, bytes: 100 },
      VR_2: { items: 1, bytes: 100 },
    },
  });

  const snapshot = metricsSnapshot(metrics);

  assert.strictEqual(snapshot.spool.skippedRealtimeEvents, 2);
  assert.strictEqual(snapshot.spool.pendingItems, 1);
  assert.strictEqual(snapshot.spool.pendingBytes, 100);
  assert.strictEqual(snapshot.replay.pendingItems, 1);
  assert.strictEqual(snapshot.recorders[0].spool.skippedRealtimeEvents, 1);
  assert.strictEqual(snapshot.recorders[1].spool.skippedRealtimeEvents, 1);
});

test("metrics snapshot reports raw archive status distinctly", () => {
  const metrics = createMetrics();
  configureSendDataRawArchive(metrics, {
    enabled: true,
    path: "/tmp/send-data-raw.jsonl",
  });

  recordSendDataRawArchived(metrics, {
    payloadBytes: 7,
  }, {
    archiveId: "send-data-raw.jsonl",
    offset: 12,
  });
  recordSendDataRawArchiveWriteFailed(metrics, "raw_archive_write_failed", "disk full");

  const snapshot = metricsSnapshot(metrics);

  assert.strictEqual(snapshot.rawArchive.status, "failed");
  assert.strictEqual(snapshot.rawArchive.path, "/tmp/send-data-raw.jsonl");
  assert.strictEqual(snapshot.rawArchive.persistedEvents, 1);
  assert.strictEqual(snapshot.rawArchive.persistedBytes, 7);
  assert.strictEqual(snapshot.rawArchive.writeFailures, 1);
  assert.strictEqual(snapshot.rawArchive.lastArchiveId, "send-data-raw.jsonl");
  assert.strictEqual(snapshot.rawArchive.lastOffset, 12);
  assert.strictEqual(snapshot.rawArchive.lastFailure.reason, "raw_archive_write_failed");
});
