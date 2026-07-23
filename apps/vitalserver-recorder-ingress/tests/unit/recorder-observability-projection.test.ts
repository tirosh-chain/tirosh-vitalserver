"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  evaluateRecorderObservability,
  mergeCurrentProjection,
  reportStateAt,
  shouldReplaceCurrent,
  summarizeCurrentProjection,
} = require("../../src/domain/recorder-observability");
const {
  createRecorderObservabilityProjector,
} = require("../../src/application/recorder-observability-projector");

test("same-boot health and profile ordering uses sequence before device time", () => {
  const current = {
    ...candidate({
      recordId: "10",
      bootId: "boot-a",
      sequence: 10,
      deviceObservedAt: "2026-07-23T02:00:00Z",
      deviceTimeState: "synchronized",
    }),
    associatedProfileRecordId: null,
  };
  assert.strictEqual(shouldReplaceCurrent(candidate({
    recordId: "11",
    bootId: "boot-a",
    sequence: 11,
    deviceObservedAt: "2026-07-23T01:00:00Z",
    deviceTimeState: "synchronized",
  }), current), true);
  assert.strictEqual(shouldReplaceCurrent(candidate({
    recordId: "12",
    bootId: "boot-a",
    sequence: 9,
    deviceObservedAt: "2026-07-23T03:00:00Z",
    deviceTimeState: "synchronized",
  }), current), false);
});

test("cross-boot or untrusted device time orders by Helper receipt", () => {
  const current = {
    ...candidate({
      recordId: "20",
      bootId: "boot-a",
      receivedAt: "2026-07-23T02:00:00Z",
      deviceObservedAt: "2026-07-23T04:00:00Z",
      deviceTimeState: "unsynchronized",
      resourceType: "diagnosticEvent",
      sequence: null,
    }),
    associatedProfileRecordId: null,
  };
  assert.strictEqual(shouldReplaceCurrent(candidate({
    recordId: "21",
    bootId: "boot-b",
    receivedAt: "2026-07-23T03:00:00Z",
    deviceObservedAt: "2026-07-22T01:00:00Z",
    deviceTimeState: "synchronized",
    resourceType: "diagnosticEvent",
    sequence: null,
  }), current), true);
});

test("boot aggregate preserves start and shutdown and restart uses start only", () => {
  const started = candidate({
    recordId: "30",
    resourceType: "bootEvent",
    document: { eventType: "boot-started" },
    deviceObservedAt: "2026-07-23T01:00:00Z",
  });
  const shutdown = candidate({
    recordId: "31",
    resourceType: "bootEvent",
    document: { eventType: "shutdown-clean" },
    deviceObservedAt: "2026-07-23T02:00:00Z",
  });
  const document = mergeCurrentProjection(
    mergeCurrentProjection({}, started),
    shutdown,
  );

  assert.strictEqual(document.bootEvent.started.recordId, "30");
  assert.strictEqual(document.bootEvent.shutdown.recordId, "31");
  assert.strictEqual(
    summarizeCurrentProjection(document).lastBootStartedAt,
    "2026-07-23T01:00:00Z",
  );
});

test("summary separates collection state and does not infer severity", () => {
  const document = mergeCurrentProjection({}, candidate({
    resourceType: "observation",
    document: {
      collectionState: "partial",
      readIssues: [{ field: "network" }],
    },
  }));
  assert.deepStrictEqual(summarizeCurrentProjection(document), {
    reportState: "missing",
    collectionState: "partial",
    severity: "unknown",
    lastBootStartedAt: null,
    readIssueCount: 1,
  });
});

test("support and report state do not infer legacy support from absence", () => {
  assert.deepStrictEqual(evaluateRecorderObservability({
    currentReportState: null,
    expectation: null,
    now: "2026-07-23T01:00:00Z",
    firstReportGraceSeconds: 300,
  }), {
    supportState: "unknown",
    supportSource: null,
    reportState: "notEvaluated",
  });
  assert.deepStrictEqual(evaluateRecorderObservability({
    currentReportState: null,
    expectation: {
      supportState: "unsupported",
      source: "version_catalog",
      recorderVersion: "1.18.43",
      producerVersion: null,
      protocolVersion: null,
      catalogRevision: "2026-07-23",
      expectedSince: null,
    },
    now: "2026-07-23T01:00:00Z",
    firstReportGraceSeconds: 300,
  }), {
    supportState: "unsupported",
    supportSource: "version_catalog",
    reportState: "notEvaluated",
  });
});

test("accepted report is direct support evidence and invalid expectation is visible", () => {
  const expectation = {
    supportState: "supported",
    source: "manual",
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: "v1",
    catalogRevision: null,
    expectedSince: "invalid",
  };
  assert.deepStrictEqual(evaluateRecorderObservability({
    currentReportState: "stale",
    expectation: {
      ...expectation,
      supportState: "unsupported",
      expectedSince: null,
    },
    now: "2026-07-23T01:00:00Z",
    firstReportGraceSeconds: 300,
  }), {
    supportState: "supported",
    supportSource: "accepted_report",
    reportState: "stale",
  });
  assert.deepStrictEqual(evaluateRecorderObservability({
    currentReportState: null,
    expectation,
    now: "2026-07-23T01:00:00Z",
    firstReportGraceSeconds: 300,
  }), {
    supportState: "supported",
    supportSource: "manual",
    reportState: "readFailed",
  });
});

test("supported expectation waits before reporting a missing first report", () => {
  const expectation = {
    supportState: "supported",
    source: "deployment_assignment",
    recorderVersion: null,
    producerVersion: "1.0.0",
    protocolVersion: "v1",
    catalogRevision: null,
    expectedSince: "2026-07-23T01:00:00Z",
  };
  assert.strictEqual(evaluateRecorderObservability({
    currentReportState: null,
    expectation,
    now: "2026-07-23T01:04:59Z",
    firstReportGraceSeconds: 300,
  }).reportState, "awaitingFirstReport");
  assert.strictEqual(evaluateRecorderObservability({
    currentReportState: null,
    expectation,
    now: "2026-07-23T01:05:00Z",
    firstReportGraceSeconds: 300,
  }).reportState, "missing");
});

test("freshness uses associated Profile interval and no guessed default", () => {
  const health = {
    ...candidate({
      resourceType: "observation",
      receivedAt: "2026-07-23T01:00:00Z",
    }),
    associatedProfileRecordId: "50",
  };
  const profile = candidate({
    recordId: "50",
    resourceType: "recorderProfile",
    document: {
      collection: { observationIntervalSeconds: 125 },
    },
  });
  const document = {
    observation: health,
    recorderProfile: { latest: profile, associated: profile },
  };
  const policy = { toleranceMultiplier: 2, allowanceSeconds: 10 };

  assert.strictEqual(
    reportStateAt(document, "2026-07-23T01:04:00Z", policy),
    "current",
  );
  assert.strictEqual(
    reportStateAt(document, "2026-07-23T01:04:21Z", policy),
    "stale",
  );
  assert.strictEqual(
    reportStateAt(
      { observation: { ...health, associatedProfileRecordId: null } },
      "2026-07-23T01:30:00Z",
      policy,
    ),
    "missing",
  );
});

test("latest Profile replacement preserves the boot-associated Profile", () => {
  const associated = candidate({
    recordId: "60",
    resourceType: "recorderProfile",
    bootId: "boot-a",
  });
  const latest = candidate({
    recordId: "61",
    resourceType: "recorderProfile",
    bootId: "boot-b",
  });
  const document = mergeCurrentProjection({
    recorderProfile: {
      latest: associated,
      associated,
    },
  }, latest);

  assert.strictEqual(document.recorderProfile.latest.recordId, "61");
  assert.strictEqual(document.recorderProfile.associated.recordId, "60");
});

test("projector records a terminal failed state and continues the batch", async () => {
  const candidates = [
    candidate({ recordId: "40" }),
    candidate({ recordId: "41" }),
  ];
  const failed = [];
  const applied = [];
  const projector = createRecorderObservabilityProjector({
    intervalMs: 1000,
    batchSize: 10,
    repository: {
      async listPendingProjection() { return candidates; },
      async readCurrent() { return null; },
      async applyProjection(item) {
        if (item.recordId === "40") throw new Error("projection exploded");
        applied.push(item.recordId);
      },
      async failProjection(recordId, error) {
        failed.push([recordId, error]);
      },
    },
  });

  assert.strictEqual(await projector.runOnce(), 2);
  assert.deepStrictEqual(failed, [["40", "projection exploded"]]);
  assert.deepStrictEqual(applied, ["41"]);
});

function candidate(overrides = {}) {
  return {
    recordId: "1",
    vrcode: "BRMH-OR1",
    resourceType: "observation",
    document: { collectionState: "ok", readIssues: [] },
    deviceId: "vr-brmh-15",
    siteId: "brmh",
    bootId: "boot-a",
    sequence: 1,
    deviceObservedAt: "2026-07-23T01:00:00Z",
    deviceTimeState: "synchronized",
    receivedAt: "2026-07-23T01:00:01Z",
    projectionVersion: 1,
    ...overrides,
  };
}
