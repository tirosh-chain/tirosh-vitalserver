"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  beginNativeVitalUpload,
  failNativeVitalUpload,
  indexedNativeVitalUpload,
  reconcileNativeVitalUpload,
} = require("../../src/domain/native-vital-upload");

const metadata = Object.freeze({
  uploadId: "upload-001",
  bedName: "OR-01",
  declaredVrcode: null,
  filename: "OR-01_260723_100000.vital",
  declaredSizeBytes: 20_971_520,
});

test("native upload starts from explicit bed identity without inventing recorder identity", () => {
  const record = beginNativeVitalUpload(
    metadata,
    "2026-07-23T10:00:00.000Z",
  );

  assert.strictEqual(record.state, "receiving");
  assert.strictEqual(record.bedName, "OR-01");
  assert.strictEqual(record.declaredVrcode, null);
  assert.strictEqual(record.receivedAt, "2026-07-23T10:00:00.000Z");
  assert.strictEqual(record.upstreamAcceptedAt, null);
  assert.strictEqual(record.indexEvidence, null);
  assert.strictEqual(record.failure, null);
});

test("native upload only advances to reconciling after explicit upstream success", () => {
  const receiving = beginNativeVitalUpload(
    metadata,
    "2026-07-23T10:00:00.000Z",
  );
  const reconciling = reconcileNativeVitalUpload(
    receiving,
    {
      upstreamStatusCode: 200,
      upstreamResponse: "success",
      occurredAt: "2026-07-23T10:00:02.000Z",
    },
  );

  assert.strictEqual(reconciling.state, "reconciling");
  assert.strictEqual(
    reconciling.upstreamAcceptedAt,
    "2026-07-23T10:00:02.000Z",
  );
  assert.strictEqual(reconciling.failure, null);
});

test("native upload preserves upstream rejection as typed failure", () => {
  const receiving = beginNativeVitalUpload(
    metadata,
    "2026-07-23T10:00:00.000Z",
  );
  const failed = failNativeVitalUpload(receiving, {
    stage: "upstreamUpload",
    code: "upstreamRejected",
    message: "invalid vital file",
    occurredAt: "2026-07-23T10:00:02.000Z",
  });

  assert.strictEqual(failed.state, "failed");
  assert.deepStrictEqual(failed.failure, {
    stage: "upstreamUpload",
    code: "upstreamRejected",
    message: "invalid vital file",
    occurredAt: "2026-07-23T10:00:02.000Z",
  });
});

test("native upload is indexed only with matching VitalServer evidence", () => {
  const reconciling = reconcileNativeVitalUpload(
    beginNativeVitalUpload(metadata, "2026-07-23T10:00:00.000Z"),
    {
      upstreamStatusCode: 200,
      upstreamResponse: "success",
      occurredAt: "2026-07-23T10:00:02.000Z",
    },
  );
  const indexed = indexedNativeVitalUpload(
    reconciling,
    {
      filename: metadata.filename,
      sizeBytes: metadata.declaredSizeBytes,
      recordingStartedAt: 1_753_239_600,
      recordingEndedAt: 1_753_275_600,
      uploadedAt: 1_753_275_601,
    },
    "2026-07-23T10:00:03.000Z",
  );

  assert.strictEqual(indexed.state, "indexed");
  assert.strictEqual(indexed.indexedAt, "2026-07-23T10:00:03.000Z");
  assert.strictEqual(indexed.indexEvidence.filename, metadata.filename);
  assert.strictEqual(
    indexed.indexEvidence.sizeBytes,
    metadata.declaredSizeBytes,
  );
});

test("native upload rejects index evidence for a different file size", () => {
  const reconciling = reconcileNativeVitalUpload(
    beginNativeVitalUpload(metadata, "2026-07-23T10:00:00.000Z"),
    {
      upstreamStatusCode: 200,
      upstreamResponse: "success",
      occurredAt: "2026-07-23T10:00:02.000Z",
    },
  );

  assert.throws(
    () => indexedNativeVitalUpload(
      reconciling,
      {
        filename: metadata.filename,
        sizeBytes: 1,
        recordingStartedAt: null,
        recordingEndedAt: null,
        uploadedAt: null,
      },
      "2026-07-23T10:00:03.000Z",
    ),
    /size does not match/,
  );
});
