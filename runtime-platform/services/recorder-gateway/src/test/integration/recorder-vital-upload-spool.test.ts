import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import test from "node:test";

import {
  FileRecorderVitalUploadSpool,
  RecorderVitalUploadRejectedError,
} from "../../adapters/recordervitaluploadspoolfile/file-recorder-vital-upload-spool.js";
import {
  beginRecorderVitalUploadDispatch,
  completeRecorderVitalUploadDispatch,
} from "../../recordergatewaydomain/recorder-gateway-vital-upload-contracts.js";

test("Recorder Vital upload spool streams one complete file into an atomic admission", async () => {
  const root = await mkdtemp(join(tmpdir(), "recorder-vital-upload-spool-"));
  try {
    const spool = new FileRecorderVitalUploadSpool({
      stateDirectory: root,
      maximumUploadBytes: 1024,
    });
    await spool.initializeRecorderVitalUploadSpool();
    const boundary = "vital-upload-boundary";
    const payload = Buffer.from("complete-vital-file-bytes");
    const multipart = Buffer.concat([
      Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="bedname"\r\n\r\nOR-01\r\n`),
      Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="vitalfile"; filename="OR-01_260724_100000.vital"\r\nContent-Type: application/octet-stream\r\n\r\n`),
      payload,
      Buffer.from(`\r\n--${boundary}\r\nContent-Disposition: form-data; name="vrcode"\r\n\r\nVR-001\r\n--${boundary}--\r\n`),
    ]);
    const receipt = await spool.admitRecorderVitalUpload({
      headers: {
        "content-type": `multipart/form-data; boundary=${boundary}`,
        "content-length": multipart.byteLength.toString(),
        "x-vital-upload-id": "upload-1",
        "x-vital-recorder-id": "recorder-1",
      },
      body: Readable.from([
        multipart.subarray(0, 19),
        multipart.subarray(19, 73),
        multipart.subarray(73),
      ]),
      receivedAt: "2026-07-24T10:00:00.000Z",
    });

    assert.equal(receipt.id, "recorder-vital-upload-upload-1");
    assert.equal(receipt.reportedBedName, "OR-01");
    assert.equal(receipt.declaredRecorderId, "recorder-1");
    assert.equal(receipt.declaredRecorderCode, "VR-001");
    assert.equal(receipt.byteSize, payload.byteLength);
    assert.match(receipt.sha256, /^[a-f0-9]{64}$/);
    const content = await spool.openRecorderVitalUploadContent(receipt.id);
    const chunks: Buffer[] = [];
    for await (const chunk of content) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    assert.deepEqual(Buffer.concat(chunks), payload);
    const storedReceipt = JSON.parse(
      await readFile(
        join(
          root,
          "recorder-vital-uploads",
          "admissions",
          receipt.id,
          "receipt.json",
        ),
        "utf8",
      ),
    ) as unknown;
    assert.deepEqual(storedReceipt, receipt);

    const pending = await spool.readRecorderVitalUploadDispatch(receipt.id);
    assert.equal(pending.state, "pending");
    assert.equal(pending.revision, 0);
    assert.deepEqual(
      (await spool.listRecoverableRecorderVitalUploadDispatches(10))
        .map((dispatch) => dispatch.sourceReceiptId),
      [receipt.id],
    );
    const dispatching = beginRecorderVitalUploadDispatch(
      pending,
      "2026-07-24T10:00:01.000Z",
    );
    await spool.commitRecorderVitalUploadDispatch(pending.revision, dispatching);
    const admitted = completeRecorderVitalUploadDispatch(
      dispatching,
      {
        state: "admitted",
        receipt: {
          schemaVersion: "v1",
          requestId: dispatching.requestId,
          outcome: "accepted",
          artifactReference: {
            resourceType: "archive-artifact",
            resourceId: "archive-artifact-1",
          },
          receivedAt: receipt.receivedAt,
          persistedAt: "2026-07-24T10:00:02.000Z",
        },
      },
      "2026-07-24T10:00:02.000Z",
    );
    await spool.commitRecorderVitalUploadDispatch(dispatching.revision, admitted);
    assert.equal(
      (await spool.readRecorderVitalUploadDispatch(receipt.id)).state,
      "archive-admitted",
    );
    assert.deepEqual(await spool.listRecoverableRecorderVitalUploadDispatches(10), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Recorder Vital upload spool rejects oversized content without publishing an admission", async () => {
  const root = await mkdtemp(join(tmpdir(), "recorder-vital-upload-limit-"));
  try {
    const spool = new FileRecorderVitalUploadSpool({
      stateDirectory: root,
      maximumUploadBytes: 4,
    });
    await spool.initializeRecorderVitalUploadSpool();
    const boundary = "limit-boundary";
    const multipart = Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="bedname"\r\n\r\nOR-01\r\n`
      + `--${boundary}\r\nContent-Disposition: form-data; name="vitalfile"; filename="case.vital"\r\n\r\n12345\r\n`
      + `--${boundary}--\r\n`,
    );
    await assert.rejects(
      spool.admitRecorderVitalUpload({
        headers: {
          "content-type": `multipart/form-data; boundary=${boundary}`,
          "content-length": multipart.byteLength.toString(),
        },
        body: Readable.from([multipart]),
        receivedAt: "2026-07-24T10:00:00.000Z",
      }),
      (error: unknown) => (
        error instanceof RecorderVitalUploadRejectedError
        && error.code === "recorder-vital-upload-size-exceeded"
      ),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
