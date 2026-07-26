"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  createNativeVitalUploadService,
} = require("../../src/application/native-vital-upload-service");

test("native upload service starts one tracked upload from explicit metadata", () => {
  const fixture = serviceFixture();

  const result = fixture.service.begin(metadata());

  assert.strictEqual(result.kind, "started");
  assert.strictEqual(result.record.state, "receiving");
  assert.strictEqual(fixture.registry.list().length, 1);
});

test("native upload service treats an indexed upload id as idempotent", () => {
  const fixture = serviceFixture();
  fixture.service.begin(metadata());
  fixture.service.recordUpstreamResult("upload-001", {
    statusCode: 200,
    responseBody: "success",
  });
  fixture.indexed = [{
    filename: metadata().filename,
    sizeBytes: metadata().declaredSizeBytes,
    recordingStartedAt: null,
    recordingEndedAt: null,
    uploadedAt: null,
  }];

  return fixture.service.runReconciliationOnce().then(() => {
    const result = fixture.service.begin(metadata());
    assert.strictEqual(result.kind, "alreadyIndexed");
    assert.strictEqual(result.record.state, "indexed");
  });
});

test("native upload service rejects reuse of an upload id with different bed", () => {
  const fixture = serviceFixture();
  fixture.service.begin(metadata());

  assert.throws(
    () => fixture.service.begin({ ...metadata(), bedName: "OR-02" }),
    /metadata conflict/,
  );
});

test("native upload service persists explicit upstream rejection", () => {
  const fixture = serviceFixture();
  fixture.service.begin(metadata());

  const failed = fixture.service.recordUpstreamResult("upload-001", {
    statusCode: 200,
    responseBody: "invalid vital file",
  });

  assert.strictEqual(failed.state, "failed");
  assert.strictEqual(failed.failure.stage, "upstreamUpload");
  assert.strictEqual(failed.failure.code, "upstreamRejected");
});

test("native upload service confirms matching VitalServer index evidence", async () => {
  const fixture = serviceFixture();
  fixture.service.begin(metadata());
  fixture.service.recordUpstreamResult("upload-001", {
    statusCode: 200,
    responseBody: "success",
  });
  fixture.indexed = [{
    filename: metadata().filename,
    sizeBytes: metadata().declaredSizeBytes,
    recordingStartedAt: 1,
    recordingEndedAt: 2,
    uploadedAt: 3,
  }];

  await fixture.service.runReconciliationOnce();

  const record = fixture.registry.get("upload-001");
  assert.strictEqual(record.state, "indexed");
  assert.deepStrictEqual(record.indexEvidence, fixture.indexed[0]);
});

test("native upload service coalesces concurrent reconciliation runs", async () => {
  const fixture = serviceFixture();
  fixture.service.begin(metadata());
  fixture.service.recordUpstreamResult("upload-001", {
    statusCode: 200,
    responseBody: "success",
  });
  let releaseIndexRead;
  let indexReadCount = 0;
  fixture.find = async () => {
    indexReadCount += 1;
    await new Promise((resolve) => {
      releaseIndexRead = resolve;
    });
    return null;
  };

  const first = fixture.service.runReconciliationOnce();
  const second = fixture.service.runReconciliationOnce();
  await new Promise((resolve) => setImmediate(resolve));
  assert.strictEqual(indexReadCount, 1);

  releaseIndexRead();
  await Promise.all([first, second]);
  assert.strictEqual(fixture.registry.get("upload-001").reconciliationAttempts, 1);
});

test("native upload service preserves interrupted receiving state as failure", () => {
  const fixture = serviceFixture();
  fixture.service.begin(metadata());

  fixture.service.recoverInterrupted();

  const record = fixture.registry.get("upload-001");
  assert.strictEqual(record.state, "failed");
  assert.strictEqual(record.failure.stage, "processInterrupted");
  assert.strictEqual(record.failure.code, "ingressRestarted");
});

function serviceFixture() {
  const records = new Map();
  const registry = {
    get(uploadId) {
      return records.get(uploadId) || null;
    },
    list() {
      return [...records.values()];
    },
    save(record) {
      records.set(record.uploadId, structuredClone(record));
    },
  };
  const fixture = {
    find: null,
    indexed: [],
    registry,
    service: null,
  };
  fixture.service = createNativeVitalUploadService({
    registry,
    vitalServerIndex: {
      async find(filename) {
        if (fixture.find) return fixture.find(filename);
        return fixture.indexed.find((item) => item.filename === filename) || null;
      },
    },
    clock: {
      now() {
        return "2026-07-23T10:00:00.000Z";
      },
    },
    reconciliation: {
      intervalMs: 60_000,
      maxAttempts: 3,
    },
  });
  return fixture;
}

function metadata() {
  return {
    uploadId: "upload-001",
    bedName: "OR-01",
    declaredVrcode: null,
    filename: "OR-01_260723_100000.vital",
    declaredSizeBytes: 20_971_520,
  };
}
