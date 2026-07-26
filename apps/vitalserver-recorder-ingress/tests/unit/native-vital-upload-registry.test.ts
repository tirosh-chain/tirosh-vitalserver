"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const {
  createNativeVitalUploadRegistry,
} = require("../../src/adapters/outbound/file/native-vital-upload-registry");
const {
  beginNativeVitalUpload,
  reconcileNativeVitalUpload,
} = require("../../src/domain/native-vital-upload");

test("native upload registry persists explicit receipt documents", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "native-upload-"));
  const statePath = path.join(directory, "native-vital-uploads.json");
  const registry = createNativeVitalUploadRegistry({ statePath });
  const record = beginNativeVitalUpload(
    metadata("upload-001"),
    "2026-07-23T10:00:00.000Z",
  );

  registry.save(record);

  const reopened = createNativeVitalUploadRegistry({ statePath });
  assert.deepStrictEqual(reopened.get("upload-001"), record);
  assert.deepStrictEqual(reopened.list(), [record]);
});

test("native upload registry rejects an invalid persisted contract", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "native-upload-"));
  const statePath = path.join(directory, "native-vital-uploads.json");
  fs.writeFileSync(statePath, JSON.stringify({
    schemaVersion: 1,
    uploads: [{ uploadId: "broken" }],
  }));

  const registry = createNativeVitalUploadRegistry({ statePath });

  assert.throws(() => registry.list(), /record contract version is invalid/);
});

test("native upload registry does not replace immutable upload metadata", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "native-upload-"));
  const registry = createNativeVitalUploadRegistry({
    statePath: path.join(directory, "native-vital-uploads.json"),
  });
  registry.save(beginNativeVitalUpload(
    metadata("upload-001"),
    "2026-07-23T10:00:00.000Z",
  ));

  assert.throws(
    () => registry.save(beginNativeVitalUpload(
      { ...metadata("upload-001"), bedName: "OR-02" },
      "2026-07-23T10:00:01.000Z",
    )),
    /immutable metadata differs/,
  );
});

test("native upload registry permits an explicit state transition", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "native-upload-"));
  const registry = createNativeVitalUploadRegistry({
    statePath: path.join(directory, "native-vital-uploads.json"),
  });
  const receiving = beginNativeVitalUpload(
    metadata("upload-001"),
    "2026-07-23T10:00:00.000Z",
  );
  registry.save(receiving);
  const reconciling = reconcileNativeVitalUpload(receiving, {
    upstreamStatusCode: 200,
    upstreamResponse: "success",
    occurredAt: "2026-07-23T10:00:02.000Z",
  });

  registry.save(reconciling);

  assert.deepStrictEqual(registry.get("upload-001"), reconciling);
});

function metadata(uploadId) {
  return {
    uploadId,
    bedName: "OR-01",
    declaredVrcode: null,
    filename: "OR-01_260723_100000.vital",
    declaredSizeBytes: 20_971_520,
  };
}
