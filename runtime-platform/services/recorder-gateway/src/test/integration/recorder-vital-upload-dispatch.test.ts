import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import test from "node:test";

import { FileRecorderVitalUploadSpool } from "../../adapters/recordervitaluploadspoolfile/file-recorder-vital-upload-spool.js";
import {
  RecorderGatewayVitalUploadApplicationService,
} from "../../recordergatewayapplication/recorder-gateway-vital-upload-application-service.js";
import type {
  RecorderVitalUploadArchivePublisher,
  RecorderVitalUploadClock,
} from "../../recordergatewayapplication/recorder-gateway-vital-upload-application-ports.js";
import type {
  RecorderVitalUploadPublishOutcome,
} from "../../recordergatewaydomain/recorder-gateway-vital-upload-contracts.js";

test("Recorder Vital upload recovery retries explicit unknown dispatch idempotently", async () => {
  const root = await mkdtemp(join(tmpdir(), "recorder-vital-upload-dispatch-"));
  try {
    const spool = new FileRecorderVitalUploadSpool({
      stateDirectory: root,
      maximumUploadBytes: 1024,
    });
    const publisher = new SequencedArchivePublisher();
    const service = new RecorderGatewayVitalUploadApplicationService(
      spool,
      publisher,
      new IncrementingClock(),
    );
    await service.initializeRecorderVitalUpload();
    const boundary = "dispatch-boundary";
    const payload = Buffer.from("complete-vital-file-bytes");
    const multipart = Buffer.concat([
      Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="bedname"\r\n\r\nOR-01\r\n`),
      Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="vitalfile"; filename="case.vital"\r\n\r\n`),
      payload,
      Buffer.from(`\r\n--${boundary}--\r\n`),
    ]);
    const first = await service.admitAndDispatchRecorderVitalUpload({
      headers: {
        "content-type": `multipart/form-data; boundary=${boundary}`,
        "content-length": multipart.byteLength.toString(),
        "x-vital-upload-id": "dispatch-upload-1",
      },
      body: Readable.from([multipart]),
      receivedAt: "2026-07-24T13:00:00.000Z",
    });
    assert.equal(first.dispatch.state, "unknown");
    assert.equal(first.dispatch.revision, 2);
    assert.equal(publisher.calls, 1);

    const recovery = await service.recoverRecorderVitalUploads(10);
    assert.equal(recovery.state, "completed");
    assert.equal(recovery.attempted, 1);
    assert.equal(recovery.completed, 1);
    assert.equal(publisher.calls, 2);
    const final = await spool.readRecorderVitalUploadDispatch(first.sourceReceipt.id);
    assert.equal(final.state, "archive-admitted");
    assert.equal(final.revision, 4);
    assert.equal(final.archiveAdmissionReceipt?.outcome, "accepted");
    assert.deepEqual(await spool.listRecoverableRecorderVitalUploadDispatches(10), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

class SequencedArchivePublisher implements RecorderVitalUploadArchivePublisher {
  public calls = 0;

  public async publishRecorderVitalUpload(
    source: Parameters<RecorderVitalUploadArchivePublisher["publishRecorderVitalUpload"]>[0],
    requestId: string,
    content: Readable,
  ): Promise<RecorderVitalUploadPublishOutcome> {
    this.calls += 1;
    for await (const _chunk of content) {
      // Consuming the stream is part of the publisher contract.
    }
    if (this.calls === 1) {
      return {
        state: "unknown",
        issue: {
          code: "test-archive-outcome-unknown",
          retryable: true,
          dependency: "test-archive",
        },
      };
    }
    return {
      state: "admitted",
      receipt: {
        schemaVersion: "v1",
        requestId,
        outcome: "accepted",
        artifactReference: {
          resourceType: "archive-artifact",
          resourceId: "archive-artifact-dispatch-test",
        },
        receivedAt: source.receivedAt,
        persistedAt: "2026-07-24T13:00:05.000Z",
      },
    };
  }
}

class IncrementingClock implements RecorderVitalUploadClock {
  private tick = 0;

  public now(): string {
    this.tick += 1;
    return `2026-07-24T13:00:${this.tick.toString().padStart(2, "0")}.000Z`;
  }
}
