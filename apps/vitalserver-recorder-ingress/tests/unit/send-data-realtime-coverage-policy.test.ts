"use strict";

const assert = require("assert");
const test = require("node:test");
const { decideSendDataRealtimeCoverage } = require("../../src/domain/send-data-realtime-coverage-policy");

test("send_data realtime coverage reports active recorder missing recent replay", () => {
  const nowMs = Date.parse("2026-06-28T10:01:00.000Z");
  const decision = decideSendDataRealtimeCoverage({
    nowMs,
    windowSeconds: 60,
    recorders: [
      {
        vrcode: "VR_1",
        activeConnections: 1,
        sendDataEventsObserved: 10,
        replayedEvents: 2,
        lastReplayAt: "2026-06-28T10:00:45.000Z",
      },
      {
        vrcode: "VR_2",
        activeConnections: 1,
        sendDataEventsObserved: 5,
        replayedEvents: 1,
        lastReplayAt: "2026-06-28T09:59:00.000Z",
      },
      {
        vrcode: "VR_3",
        activeConnections: 0,
        sendDataEventsObserved: 7,
        replayedEvents: 0,
        lastReplayAt: null,
      },
    ],
  });

  assert.deepStrictEqual(decision, {
    windowSeconds: 60,
    observedRecorderCount: 3,
    activeObservedRecorderCount: 2,
    replayedRecorderCount: 2,
    activeRecordersMissingRecentReplay: ["VR_2"],
    minReplayedEventsPerRecorder: 1,
    maxReplayedEventsPerRecorder: 2,
    maxReplayAgeSeconds: 120,
  });
});

test("send_data realtime coverage keeps unobserved recorders out of SLO candidate set", () => {
  const decision = decideSendDataRealtimeCoverage({
    nowMs: Date.parse("2026-06-28T10:01:00.000Z"),
    windowSeconds: 60,
    recorders: [
      {
        vrcode: "VR_1",
        activeConnections: 1,
        sendDataEventsObserved: 0,
        replayedEvents: 0,
        lastReplayAt: null,
      },
    ],
  });

  assert.deepStrictEqual(decision, {
    windowSeconds: 60,
    observedRecorderCount: 0,
    activeObservedRecorderCount: 0,
    replayedRecorderCount: 0,
    activeRecordersMissingRecentReplay: [],
    minReplayedEventsPerRecorder: 0,
    maxReplayedEventsPerRecorder: 0,
    maxReplayAgeSeconds: null,
  });
});
