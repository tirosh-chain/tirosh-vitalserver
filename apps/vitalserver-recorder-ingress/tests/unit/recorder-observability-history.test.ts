"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  encodeIncidentCursor,
  incidentsDocument,
  parseRecorderObservabilityHistoryRoute,
  timelineDocument,
} = require("../../src/domain/recorder-observability-history");

test("timeline query requires a bounded explicit window and allowed bucket", () => {
  const route = parseRecorderObservabilityHistoryRoute(
    "/runtime/vitaldb/recorders/VR_A/observability/timeline"
      + "?from=2026-07-23T00:00:00Z"
      + "&until=2026-07-24T00:00:00Z"
      + "&bucketSeconds=900",
  );
  assert.deepStrictEqual(route, {
    kind: "timeline",
    query: {
      vrcode: "VR_A",
      from: "2026-07-23T00:00:00.000Z",
      until: "2026-07-24T00:00:00.000Z",
      bucketSeconds: 900,
    },
  });
  assert.strictEqual(parseRecorderObservabilityHistoryRoute(
    "/runtime/vitaldb/recorders/VR_A/observability/timeline"
      + "?from=2026-07-22T00:00:00Z"
      + "&until=2026-07-24T00:00:01Z"
      + "&bucketSeconds=900",
  ).reason, "timeline_window_too_large");
  assert.strictEqual(parseRecorderObservabilityHistoryRoute(
    "/runtime/vitaldb/recorders/VR_A/observability/timeline"
      + "?from=2026-07-23T00:00:00Z"
      + "&until=2026-07-24T00:00:00Z"
      + "&bucketSeconds=60",
  ).reason, "bucket_seconds_invalid");
});

test("incident cursor is opaque, bounded, and advances after the last visible row", () => {
  const cursor = encodeIncidentCursor("2026-07-24T00:00:00.000Z", "42", "panic");
  const route = parseRecorderObservabilityHistoryRoute(
    "/runtime/vitaldb/recorders/VR_A/observability/incidents"
      + "?from=2026-07-01T00:00:00Z"
      + "&until=2026-07-24T00:00:00Z"
      + `&type=panic&limit=1&cursor=${cursor}`,
  );
  assert.deepStrictEqual(route.query.cursor, {
    receivedAt: "2026-07-24T00:00:00.000Z",
    recordId: "42",
    code: "panic",
  });
  const rows = [
    incident("42", "2026-07-24T00:00:00.000Z"),
    incident("41", "2026-07-23T00:00:00.000Z"),
  ];
  const document = incidentsDocument(
    { ...route.query, cursor: null },
    rows,
  );
  assert.strictEqual(document.incidents.length, 1);
  assert.strictEqual(typeof document.nextCursor, "string");
  assert.deepStrictEqual(
    parseRecorderObservabilityHistoryRoute(
      "/runtime/vitaldb/recorders/VR_A/observability/incidents"
        + "?from=2026-07-01T00:00:00Z"
        + "&until=2026-07-24T00:00:00Z"
        + `&cursor=${document.nextCursor}`,
    ).query.cursor,
    { receivedAt: rows[0].receivedAt, recordId: rows[0].recordId, code: rows[0].code },
  );
});

test("incident cursor preserves a second explicit signal from one boot record", () => {
  const rows = [
    incident("42", "2026-07-24T00:00:00.000Z", "repeated-undervoltage"),
    incident("42", "2026-07-24T00:00:00.000Z", "boot-loop"),
  ];
  const query = {
    vrcode: "VR_A",
    from: "2026-07-01T00:00:00.000Z",
    until: "2026-07-24T00:00:00.000Z",
    incidentType: null,
    cursor: null,
    limit: 1,
  };
  const first = incidentsDocument(query, rows);
  const cursor = parseRecorderObservabilityHistoryRoute(
    "/runtime/vitaldb/recorders/VR_A/observability/incidents"
      + "?from=2026-07-01T00:00:00Z"
      + "&until=2026-07-24T00:00:00Z"
      + `&cursor=${first.nextCursor}`,
  );
  assert.strictEqual(first.incidents[0].incidentId, "42:repeated-undervoltage");
  assert.deepStrictEqual(cursor.query.cursor, {
    receivedAt: rows[0].receivedAt,
    recordId: "42",
    code: "repeated-undervoltage",
  });
});

test("timeline empty state is not reported rather than empty loaded success", () => {
  const document = timelineDocument({
    vrcode: "VR_A",
    from: "2026-07-23T00:00:00.000Z",
    until: "2026-07-24T00:00:00.000Z",
    bucketSeconds: 900,
  }, { supportState: "unknown", rows: [] });
  assert.strictEqual(document.state, "notReported");
  assert.strictEqual(document.timeBasis, "receivedAt");
});

test("timeline preserves explicit unsupported separately from no report", () => {
  const document = timelineDocument({
    vrcode: "VR_A",
    from: "2026-07-23T00:00:00.000Z",
    until: "2026-07-24T00:00:00.000Z",
    bucketSeconds: 900,
  }, { supportState: "unsupported", rows: [] });
  assert.strictEqual(document.state, "unsupported");
  assert.strictEqual(document.supportState, "unsupported");
});

function incident(recordId, receivedAt, code = "panic") {
  return {
    incidentId: `${recordId}:${code}`,
    recordId,
    eventId: `event-${recordId}`,
    category: code === "panic" ? "kernel" : "power",
    code,
    severity: "critical",
    state: "historical",
    bootId: null,
    occurredAt: receivedAt,
    receivedAt,
    timeState: "synchronized",
    summary: code,
    evidence: [],
    source: code === "panic" ? "kernelIncident" : "bootEvent",
    capturedAt: receivedAt,
    captureTimeState: "synchronized",
    incidentType: code,
    incidentBootId: null,
    messageExcerpt: "panic",
    truncated: false,
  };
}
