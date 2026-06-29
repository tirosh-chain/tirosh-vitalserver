"use strict";

const assert = require("assert");
const test = require("node:test");
const { decideSendDataRealtimeRetention } = require("../../src/domain/send-data-realtime-retention-policy");

test("send_data realtime retention preserves latest skipped recorder missing from kept window", () => {
  const decision = decideSendDataRealtimeRetention({
    skippedCandidates: [
      { index: 0, vrcode: "VR_A", payloadBytes: 10 },
      { index: 1, vrcode: "VR_A", payloadBytes: 20 },
      { index: 2, vrcode: "VR_B", payloadBytes: 30 },
    ],
    keptCandidates: [
      { index: 3, vrcode: "VR_B", payloadBytes: 40 },
    ],
  });

  assert.deepStrictEqual(decision, {
    preservedIndexes: [1],
    skippedIndexes: [0, 2],
    skippedRealtimeItems: 2,
    skippedRealtimeBytes: 40,
    skippedRealtimeByRecorder: {
      VR_A: { items: 1, bytes: 10 },
      VR_B: { items: 1, bytes: 30 },
    },
    preservedRealtimeItems: 1,
  });
});

test("send_data realtime retention skips all candidates when recorder is already in kept window", () => {
  const decision = decideSendDataRealtimeRetention({
    skippedCandidates: [
      { index: 0, vrcode: "VR_A", payloadBytes: 10 },
      { index: 1, vrcode: "VR_A", payloadBytes: 20 },
    ],
    keptCandidates: [
      { index: 2, vrcode: "VR_A", payloadBytes: 30 },
    ],
  });

  assert.deepStrictEqual(decision, {
    preservedIndexes: [],
    skippedIndexes: [0, 1],
    skippedRealtimeItems: 2,
    skippedRealtimeBytes: 30,
    skippedRealtimeByRecorder: {
      VR_A: { items: 2, bytes: 30 },
    },
    preservedRealtimeItems: 0,
  });
});
