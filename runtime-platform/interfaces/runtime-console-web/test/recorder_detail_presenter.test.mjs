import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  displayByteSize,
  presentRecorderArtifact,
  presentRecorderIncident,
  presentRecorderObservation,
} from "../dist/recorder-detail-presenter.mjs";

test("built Console loads its generated stylesheet", async () => {
  const html = await readFile(
    new URL("../dist/index.html", import.meta.url),
    "utf8",
  );
  assert.match(
    html,
    /<link rel="stylesheet" href="\.\/runtime-console\.css" \/>/,
  );
});

test("presents only explicit Recorder observation owner fields", () => {
  assert.deepEqual(
    presentRecorderObservation({
      id: "observation-1",
      envelope: {
        occurredAt: "2026-07-24T10:00:00Z",
        bootId: "boot-1",
        sequence: 42,
        runtime: { state: "ready", version: "1.2.3" },
        time: { state: "not-reported" },
      },
      receivedAt: "2026-07-24T10:00:01Z",
    }),
    {
      id: "observation-1",
      occurredAt: "2026-07-24T10:00:00Z",
      runtimeState: "ready",
      runtimeVersion: "1.2.3",
      timeState: "not-reported",
      bootId: "boot-1",
      sequence: 42,
      receivedAt: "2026-07-24T10:00:01Z",
    },
  );
  assert.equal(presentRecorderObservation({ items: [] }), undefined);
});

test("keeps absent artifact outcomes absent instead of inventing success", () => {
  assert.deepEqual(
    presentRecorderArtifact({
      artifact: {
        artifactId: "artifact-1",
        originalFileName: "OR-01.vital",
        finalizationState: "finalized",
        finalizedAt: "2026-07-24T10:00:00Z",
        byteSize: 20_480,
      },
      attribution: {
        reportedBedName: "OR-01",
        outcome: "matched",
      },
    }),
    {
      id: "artifact-1",
      originalFileName: "OR-01.vital",
      finalizationState: "finalized",
      finalizedAt: "2026-07-24T10:00:00Z",
      byteSize: 20_480,
      reportedBedName: "OR-01",
      attributionOutcome: "matched",
    },
  );
  assert.equal(displayByteSize(20_480), "20.0 KiB (20480 B)");
  assert.equal(displayByteSize(undefined), "Not provided by owner");
});

test("presents typed Recorder incident evidence and rejects malformed items", () => {
  assert.deepEqual(
    presentRecorderIncident({
      id: "incident-1",
      occurredAt: "2026-07-24T10:00:00Z",
      receivedAt: "2026-07-24T10:00:01Z",
      runtimeIssue: {
        code: "recorder-runtime-failed",
        message: "Recorder reported its runtime failure",
        retryable: true,
        dependency: "recorder-runtime",
      },
    }),
    {
      id: "incident-1",
      code: "recorder-runtime-failed",
      message: "Recorder reported its runtime failure",
      occurredAt: "2026-07-24T10:00:00Z",
      dependency: "recorder-runtime",
      retryable: true,
      receivedAt: "2026-07-24T10:00:01Z",
    },
  );
  assert.equal(presentRecorderIncident({ runtimeIssue: [] }), undefined);
});
