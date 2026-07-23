"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  mapRecorderObservabilityDetail,
} = require("../../src/domain/recorder-observability-detail");

test("detail mapper exposes typed state without leaking aggregate JSONB", () => {
  const detail = mapRecorderObservabilityDetail({
    vrcode: "VR-001",
    supportState: "supported",
    supportSource: "accepted_report",
    reportState: "current",
    profileState: "associated",
    collectionState: "partial",
    latestObservationReceivedAt: "2026-07-24T00:00:01Z",
    readIssueCount: 1,
    expectedSince: null,
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: null,
    resources: {
      observation: {
        receivedAt: "2026-07-24T00:00:01Z",
        document: {
          eventId: "raw-event-id",
          deviceObservedAt: "2026-07-24T00:00:00Z",
          readIssues: [{
            field: "memory.availableBytes",
            state: "failed",
            detail: "proc read failed",
          }],
          payload: {
            raspberryPi: {
              temperatureCelsius: { state: "ok", value: 52.5 },
            },
            memory: {
              availableBytes: {
                state: "failed",
                detail: "proc read failed",
              },
              totalBytes: { state: "ok", value: 8589934592 },
            },
            storage: {
              root: { usedPercent: { state: "ok", value: 41.2 } },
              data: {
                usedPercent: {
                  state: "unsupported",
                  detail: "data mount is unavailable",
                },
              },
            },
            vitalRecorder: {
              activeState: { state: "ok", value: "active" },
            },
            publisher: {
              activeState: { state: "ok", value: "active" },
              bufferBytes: { state: "ok", value: 2048 },
              bufferLimitBytes: 8388608,
            },
            network: {
              interfaces: [{
                name: "eth0",
                operState: { state: "ok", value: "up" },
                carrier: { state: "ok", value: true },
                rxErrors: { state: "ok", value: 0 },
                txErrors: { state: "ok", value: 0 },
              }],
            },
          },
        },
      },
      recorderProfile: {
        associated: {
          receivedAt: "2026-07-24T00:00:00Z",
          document: {
            deviceId: "observer-001",
            bootId: "boot-001",
            deviceObservedAt: "2026-07-23T23:59:59Z",
            software: {
              vitalRecorderVersion: { state: "ok", value: "4.0.1" },
            },
            collection: {
              powerIntervalSeconds: 1,
              telemetryIntervalSeconds: 10,
              observationIntervalSeconds: 60,
            },
            capabilities: {
              inputCurrent: {
                state: "unsupported",
                detail: "not measured",
              },
            },
          },
        },
      },
      bootEvent: {
        started: {
          document: {
            bootId: "boot-001",
            deviceObservedAt: "2026-07-23T23:50:00Z",
          },
        },
      },
    },
  });

  assert.strictEqual(detail.readings.temperatureCelsius.value, 52.5);
  assert.strictEqual(detail.readings.memoryAvailableBytes.state, "failed");
  assert.strictEqual(detail.readings.dataUsedPercent.state, "unsupported");
  assert.strictEqual(detail.profile.collection.observationIntervalSeconds, 60);
  assert.strictEqual(detail.profile.software.vitalRecorderVersion.value, "4.0.1");
  assert.strictEqual(detail.boot.state, "started");
  assert.strictEqual(detail.readIssues[0].state, "failed");
  assert.strictEqual(JSON.stringify(detail).includes("raw-event-id"), false);
  assert.strictEqual(Object.hasOwn(detail, "resources"), false);
});

test("detail mapper preserves absent health as missing readings", () => {
  const detail = mapRecorderObservabilityDetail({
    vrcode: "VR-legacy",
    supportState: "unknown",
    supportSource: null,
    reportState: "notEvaluated",
    profileState: null,
    collectionState: null,
    latestObservationReceivedAt: null,
    readIssueCount: 0,
    expectedSince: null,
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: null,
    resources: null,
  });

  assert.strictEqual(detail.readings.temperatureCelsius.state, "missing");
  assert.strictEqual(detail.profile.state, "missing");
  assert.strictEqual(detail.profile.collection, null);
  assert.strictEqual(detail.boot.state, "notReported");
});

test("detail mapper does not combine shutdown and start from different boots", () => {
  const detail = mapRecorderObservabilityDetail({
    vrcode: "VR-boot",
    supportState: "supported",
    supportSource: "accepted_report",
    reportState: "current",
    profileState: "latest_unassociated",
    collectionState: "complete",
    latestObservationReceivedAt: "2026-07-24T00:00:01Z",
    readIssueCount: 0,
    expectedSince: null,
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: null,
    resources: {
      observation: {
        document: {
          deviceObservedAt: "2026-07-24T00:00:00Z",
          payload: {
            raspberryPi: {
              temperatureCelsius: { state: "ok" },
            },
          },
          readIssues: [{ field: "bad" }],
        },
      },
      bootEvent: {
        started: {
          document: {
            bootId: "current-boot",
            deviceObservedAt: "2026-07-24T00:00:00Z",
          },
        },
        shutdown: {
          document: {
            bootId: "previous-boot",
            shutdown: { shutdownAt: "2026-07-23T23:00:00Z" },
          },
        },
      },
    },
  });

  assert.strictEqual(detail.profile.state, "unassociated");
  assert.strictEqual(detail.boot.state, "started");
  assert.strictEqual(detail.boot.bootId, "current-boot");
  assert.strictEqual(detail.boot.cleanShutdownAt, null);
  assert.strictEqual(detail.readings.temperatureCelsius.state, "invalid");
  assert.strictEqual(detail.readIssues[0].state, "invalid");
});
