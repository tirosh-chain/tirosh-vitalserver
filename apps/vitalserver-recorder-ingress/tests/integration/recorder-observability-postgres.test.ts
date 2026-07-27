"use strict";

const assert = require("assert");
const test = require("node:test");
const { Pool } = require("pg");
const {
  createRecorderObservabilityRepository,
} = require("../../src/adapters/outbound/postgres/recorder-observability-repository");
const {
  createRecorderObservabilityProjector,
} = require("../../src/application/recorder-observability-projector");

const port = Number(process.env.RECORDER_INGRESS_TEST_POSTGRES_PORT || 0);
const postgresTest = port ? test : test.skip;

postgresTest("PostgreSQL owns atomic admission and one-row current projection", async () => {
  const config = {
    host: "127.0.0.1",
    port,
    database: "vitalserver_test",
    user: "vitalserver",
    password: "vitalserver",
    maxConnections: 4,
    freshnessToleranceMultiplier: 3,
    freshnessAllowanceSeconds: 30,
    firstReportGraceSeconds: 300,
    eventId: eventIds([
      "10000000-0000-4000-8000-000000000001",
      "10000000-0000-4000-8000-000000000002",
      "10000000-0000-4000-8000-000000000003",
    ]),
    now: () => "2026-07-23T01:10:00Z",
  };
  const repository = createRecorderObservabilityRepository(config);
  const inspect = new Pool(config);
  await repository.ping();
  await inspect.query(
    `TRUNCATE recorder_observability.expectation_events,
              recorder_observability.expectations,
              recorder_observability.current,
              recorder_observability.records,
              recorder_observability.requests
       RESTART IDENTITY`,
  );

  const first = await repository.admit(batch({
    requestId: "00000000-0000-4000-8000-000000000001",
    lines: [preparedLine()],
  }));
  const mixed = await repository.admit(batch({
    requestId: "00000000-0000-4000-8000-000000000002",
    lines: [
      preparedLine(),
      preparedLine({
        lineNumber: 2,
        canonicalSha256: "b".repeat(64),
        rawSha256: "c".repeat(64),
        rawDocument: "{\"conflict\":true}",
      }),
      preparedLine({
        lineNumber: 3,
        document: null,
        canonicalSha256: null,
        identity: {},
        rawDocument: "{broken",
        rawSha256: "d".repeat(64),
        failureCode: "json_parse_failed",
      }),
    ],
  }));

  assert.deepStrictEqual(first, {
    accepted: 1,
    duplicates: 0,
    quarantined: 0,
  });
  assert.deepStrictEqual(mixed, {
    accepted: 0,
    duplicates: 1,
    quarantined: 2,
  });

  const evidence = await inspect.query(
    `SELECT disposition, raw_document IS NOT NULL AS has_raw,
            duplicate_of_record_id IS NOT NULL AS has_pointer
       FROM recorder_observability.records
      ORDER BY record_id`,
  );
  assert.deepStrictEqual(evidence.rows, [
    { disposition: "accepted", has_raw: false, has_pointer: false },
    { disposition: "duplicate", has_raw: false, has_pointer: true },
    { disposition: "quarantined", has_raw: true, has_pointer: false },
    { disposition: "quarantined", has_raw: true, has_pointer: false },
  ]);

  const projector = createRecorderObservabilityProjector({
    repository,
    intervalMs: 1000,
    batchSize: 10,
  });
  assert.strictEqual(await projector.runOnce(), 1);
  const current = await inspect.query(
    `SELECT vrcode, health_record_id IS NOT NULL AS has_health,
            report_state, collection_state, severity
       FROM recorder_observability.current`,
  );
  assert.deepStrictEqual(current.rows, [{
    vrcode: "BRMH-OR1",
    has_health: true,
    report_state: "missing",
    collection_state: "ok",
    severity: "unknown",
  }]);

  const supportedCommand = expectationCommand({
    commandId: "20000000-0000-4000-8000-000000000001",
    vrcode: "BRMH-OR2",
    recorderVersion: "1.19.0",
  });
  const supportedDecision = await repository.applyExpectationCommand(
    supportedCommand,
  );
  const retryDecision = await repository.applyExpectationCommand(
    supportedCommand,
  );
  const unsupportedDecision = await repository.applyExpectationCommand(
    expectationCommand({
      commandId: "20000000-0000-4000-8000-000000000002",
      vrcode: "BRMH-OR3",
      supportState: "unsupported",
      source: "version_catalog",
      recorderVersion: "1.18.43",
      expectedSince: null,
    }),
  );
  const conflictDecision = await repository.applyExpectationCommand(
    expectationCommand({
      commandId: "20000000-0000-4000-8000-000000000003",
      vrcode: "BRMH-OR2",
      supportState: "unsupported",
      source: "manual",
      expectedSince: null,
    }),
  );
  assert.strictEqual(supportedDecision.kind, "accepted");
  assert.strictEqual(retryDecision.kind, "idempotent");
  assert.strictEqual(unsupportedDecision.kind, "accepted");
  assert.deepStrictEqual(conflictDecision, {
    kind: "revisionConflict",
    currentRevision: 1,
    failure: "revisionConflict",
  });
  const timeline = await repository.readRecorderObservabilityTimeline({
    vrcode: "BRMH-OR1",
    from: "2026-07-23T01:00:00Z",
    until: "2026-07-23T02:00:00Z",
    bucketSeconds: 900,
  });
  assert.strictEqual(timeline.supportState, "supported");
  assert.strictEqual(timeline.rows.length, 1);
  assert.strictEqual(timeline.rows[0].sampleCount, 1);
  assert.strictEqual(
    timeline.rows[0].metrics.temperatureCelsius.stateCounts.absent,
    1,
  );
  const unsupportedTimeline = await repository.readRecorderObservabilityTimeline({
    vrcode: "BRMH-OR3",
    from: "2026-07-23T01:00:00Z",
    until: "2026-07-23T02:00:00Z",
    bucketSeconds: 900,
  });
  assert.deepStrictEqual(unsupportedTimeline, {
    supportState: "unsupported",
    rows: [],
  });

  await repository.admit(batch({
    requestId: "00000000-0000-4000-8000-000000000003",
    resourceType: "kernelIncident",
    receivedAt: "2026-07-23T01:05:00Z",
    lines: [preparedLine({
      rawSha256: "1".repeat(64),
      canonicalSha256: "2".repeat(64),
      rawDocument: "{\"eventId\":\"incident-1\"}",
      identity: {
        eventId: "incident-1",
        deviceId: "vr-brmh-15",
        schemaVersion: "v1",
        kind: "kernel-incident",
        siteId: "brmh",
        bootId: "boot-a",
        sequence: 2,
        deviceObservedAt: "2026-07-23T01:04:59Z",
        deviceTimeState: "synchronized",
      },
      document: {
        schemaVersion: "v1",
        eventId: "incident-1",
        deviceId: "vr-brmh-15",
        capturedAt: "2026-07-23T01:04:59Z",
        captureTimeState: "synchronized",
        incidentType: "panic",
        incidentBootId: "boot-a",
        messageExcerpt: "kernel panic",
        truncated: false,
      },
    })],
  }));
  const incidents = await repository.readRecorderObservabilityIncidents({
    vrcode: "BRMH-OR1",
    from: "2026-07-23T01:00:00Z",
    until: "2026-07-23T02:00:00Z",
    incidentType: "panic",
    cursor: null,
    limit: 10,
  });
  assert.deepStrictEqual(
    incidents.map((incident) => ({
      eventId: incident.eventId,
      incidentType: incident.incidentType,
      receivedAt: incident.receivedAt,
    })),
    [{
      eventId: "incident-1",
      incidentType: "panic",
      receivedAt: "2026-07-23T01:05:00.000Z",
    }],
  );
  const recorderWithoutObserverIncidents =
    await repository.readRecorderObservabilityIncidents({
      vrcode: "VR-WITHOUT-OBSERVER",
      from: "2026-07-23T01:00:00Z",
      until: "2026-07-23T02:00:00Z",
      incidentType: null,
      cursor: null,
      limit: 10,
    });
  assert.deepStrictEqual(recorderWithoutObserverIncidents, []);

  await repository.admit(batch({
    requestId: "00000000-0000-4000-8000-000000000004",
    resourceType: "bootEvent",
    receivedAt: "2026-07-23T01:06:00Z",
    lines: [preparedLine({
      rawSha256: "3".repeat(64),
      canonicalSha256: "4".repeat(64),
      rawDocument: "{\"eventId\":\"boot-incident-1\"}",
      identity: {
        eventId: "boot-incident-1",
        deviceId: "vr-brmh-15",
        schemaVersion: "v2",
        kind: "boot-event",
        siteId: "brmh",
        bootId: "boot-b",
        sequence: null,
        deviceObservedAt: "2026-07-23T01:05:59Z",
        deviceTimeState: "synchronized",
      },
      document: {
        schemaVersion: "v2",
        eventId: "boot-incident-1",
        deviceId: "vr-brmh-15",
        bootId: "boot-b",
        kind: "boot-event",
        eventType: "boot-started",
        deviceObservedAt: "2026-07-23T01:05:59Z",
        ntpState: "synchronized",
        assessment: {
          policyVersion: "recorder-incident/v1",
          consecutiveUnexpectedBoots: 2,
          undervoltageBootsConsidered: 2,
          evidenceState: "healthy",
          signals: [
            {
              category: "boot",
              code: "boot-loop",
              severity: "warning",
              state: "active",
              summary: "unexpected boot sequence",
            },
            {
              category: "power",
              code: "repeated-undervoltage",
              severity: "critical",
              state: "active",
              summary: "undervoltage across recent boots",
            },
          ],
        },
      },
    })],
  }));
  const firstIncidentPage = await repository.readRecorderObservabilityIncidents({
    vrcode: "BRMH-OR1",
    from: "2026-07-23T01:00:00Z",
    until: "2026-07-23T02:00:00Z",
    incidentType: null,
    cursor: null,
    limit: 1,
  });
  assert.strictEqual(firstIncidentPage[0].code, "repeated-undervoltage");
  const secondIncidentPage = await repository.readRecorderObservabilityIncidents({
    vrcode: "BRMH-OR1",
    from: "2026-07-23T01:00:00Z",
    until: "2026-07-23T02:00:00Z",
    incidentType: null,
    cursor: {
      receivedAt: firstIncidentPage[0].receivedAt,
      recordId: firstIncidentPage[0].recordId,
      code: firstIncidentPage[0].code,
    },
    limit: 1,
  });
  assert.strictEqual(secondIncidentPage[0].code, "boot-loop");

  const summaries = await repository.listCurrentRecorders();
  assert.deepStrictEqual(
    summaries.map((summary) => ({
      vrcode: summary.vrcode,
      supportState: summary.supportState,
      supportSource: summary.supportSource,
      reportState: summary.reportState,
    })),
    [
      {
        vrcode: "BRMH-OR1",
        supportState: "supported",
        supportSource: "accepted_report",
        reportState: "missing",
      },
      {
        vrcode: "BRMH-OR2",
        supportState: "supported",
        supportSource: "deployment_assignment",
        reportState: "missing",
      },
      {
        vrcode: "BRMH-OR3",
        supportState: "unsupported",
        supportSource: "version_catalog",
        reportState: "notEvaluated",
      },
    ],
  );
  const clearDecision = await repository.applyExpectationCommand(
    expectationCommand({
      commandId: "20000000-0000-4000-8000-000000000004",
      vrcode: "BRMH-OR3",
      expectedRevision: 1,
      action: "clear",
      supportState: null,
      source: null,
      recorderVersion: null,
      producerVersion: null,
      protocolVersion: null,
      catalogRevision: null,
      expectedSince: null,
      evidenceDocument: {},
    }),
  );
  assert.strictEqual(clearDecision.kind, "accepted");
  assert.deepStrictEqual(
    (await repository.listCurrentRecorders()).map((summary) => summary.vrcode),
    ["BRMH-OR1", "BRMH-OR2"],
  );

  const tables = await inspect.query(
    `SELECT tablename
       FROM pg_catalog.pg_tables
      WHERE schemaname = 'recorder_observability'
      ORDER BY tablename`,
  );
  assert.deepStrictEqual(tables.rows.map((row) => row.tablename), [
    "current",
    "expectation_events",
    "expectations",
    "records",
    "requests",
  ]);

  await repository.close();
  await inspect.end();
});

function expectationCommand(overrides = {}) {
  return {
    commandId: "20000000-0000-4000-8000-000000000001",
    vrcode: "BRMH-OR2",
    expectedRevision: 0,
    action: "set",
    supportState: "supported",
    source: "deployment_assignment",
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: null,
    catalogRevision: null,
    expectedSince: "2026-07-23T00:50:00Z",
    evidenceDocument: { deploymentId: "deployment-1" },
    decidedAt: "2026-07-23T00:50:00Z",
    ...overrides,
  };
}

function eventIds(values) {
  let index = 0;
  return () => values[index++] || "10000000-0000-4000-8000-999999999999";
}

function batch(overrides = {}) {
  return {
    requestId: "00000000-0000-4000-8000-000000000001",
    resourceType: "observation",
    vrcode: "BRMH-OR1",
    requestDeviceId: "vr-brmh-15",
    sourceIp: "172.31.0.157",
    receivedAt: "2026-07-23T01:00:01Z",
    lines: [preparedLine()],
    ...overrides,
  };
}

function preparedLine(overrides = {}) {
  return {
    lineNumber: 1,
    rawDocument: "{\"eventId\":\"event-1\"}",
    rawSha256: "a".repeat(64),
    document: {
      schemaVersion: "v1",
      eventId: "event-1",
      deviceId: "vr-brmh-15",
      bootId: "boot-a",
      sequence: 1,
      kind: "device-health",
      collectionState: "ok",
      deviceObservedAt: "2026-07-23T01:00:00Z",
      readIssues: [],
    },
    canonicalSha256: "e".repeat(64),
    identity: {
      eventId: "event-1",
      deviceId: "vr-brmh-15",
      schemaVersion: "v1",
      kind: "device-health",
      siteId: "brmh",
      bootId: "boot-a",
      sequence: 1,
      deviceObservedAt: "2026-07-23T01:00:00Z",
      deviceTimeState: "synchronized",
    },
    contractReceipt: "f".repeat(64),
    failureCode: null,
    failureDetail: null,
    ...overrides,
  };
}
