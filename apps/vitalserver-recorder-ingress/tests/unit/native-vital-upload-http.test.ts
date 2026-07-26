"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  nativeVitalUploadMetadataFromHeaders,
} = require("../../src/adapters/inbound/http/native-vital-upload-http");

test("native upload HTTP metadata requires explicit bed identity", () => {
  const metadata = nativeVitalUploadMetadataFromHeaders({
    "x-vital-upload-id": "upload-001",
    "x-vital-bed-name": "OR-01",
    "x-vital-filename": "OR-01_260723_100000.vital",
    "x-vital-file-size": "20971520",
  });

  assert.deepStrictEqual(metadata, {
    uploadId: "upload-001",
    bedName: "OR-01",
    declaredVrcode: null,
    filename: "OR-01_260723_100000.vital",
    declaredSizeBytes: 20_971_520,
  });
});

test("native upload HTTP metadata preserves explicit recorder identity", () => {
  const metadata = nativeVitalUploadMetadataFromHeaders({
    "x-vital-upload-id": "upload-001",
    "x-vital-bed-name": "OR-01",
    "x-vital-recorder-code": "VR-001",
    "x-vital-filename": "OR-01_260723_100000.vital",
    "x-vital-file-size": "20971520",
  });

  assert.strictEqual(metadata.declaredVrcode, "VR-001");
});

test("legacy upload without tracking headers stays outside the tracking contract", () => {
  assert.strictEqual(nativeVitalUploadMetadataFromHeaders({
    "content-type": "multipart/form-data; boundary=legacy",
  }), null);
});

test("partial tracking metadata is rejected instead of guessed from filename", () => {
  assert.throws(
    () => nativeVitalUploadMetadataFromHeaders({
      "x-vital-upload-id": "upload-001",
      "x-vital-filename": "OR-01_260723_100000.vital",
      "x-vital-file-size": "20971520",
    }),
    /x-vital-bed-name is required/,
  );
});
