"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  assessRecorderOperationalHealth,
} = require("../../src/domain/recorder-operational-health");

function reading(value) {
  return { state: "ok", value };
}

test("01 pattern reports active undervoltage and throttling as critical", () => {
  const health = assessRecorderOperationalHealth({
    deviceObservedAt: "2026-07-24T05:04:25Z",
    ntpState: "synchronized",
    payload: {
      raspberryPi: {
        temperatureCelsius: reading(53.069),
        throttleFlags: reading("0x50005"),
        throttleStatus: {
          underVoltageNow: reading(true),
          frequencyCappedNow: reading(false),
          throttledNow: reading(true),
          softTemperatureLimitNow: reading(false),
          underVoltageOccurred: reading(true),
          frequencyCappedOccurred: reading(false),
          throttledOccurred: reading(true),
          softTemperatureLimitOccurred: reading(false),
        },
      },
      memory: {
        totalBytes: reading(4_030_000_000),
        availableBytes: reading(3_770_000_000),
      },
      storage: {
        root: {
          usedPercent: reading(87.84),
          readOnly: reading(false),
        },
        data: {
          usedPercent: reading(6.47),
          readOnly: reading(false),
        },
        ext4Filesystems: [],
      },
      vitalRecorder: { activeState: reading("active") },
      services: {
        systemRunning: reading("running"),
        failedUnits: reading(""),
      },
    },
  }, "current");

  assert.strictEqual(health.state, "critical");
  assert.strictEqual(health.issueCount, 1);
  assert.strictEqual(health.issues[0].code, "raspberry-pi-throttle-active");
  assert.match(health.issues[0].detail, /undervoltage/);
  assert.match(health.issues[0].detail, /CPU throttling/);
});

test("03 pattern reports degraded systemd and unsynchronized time", () => {
  const health = assessRecorderOperationalHealth({
    deviceObservedAt: "2026-07-24T05:02:29Z",
    ntpState: "unsynchronized",
    payload: {
      raspberryPi: {
        temperatureCelsius: reading(51.808),
        throttleFlags: reading("0x0"),
      },
      memory: {
        totalBytes: reading(1_990_000_000),
        availableBytes: reading(1_690_000_000),
      },
      storage: {
        root: {
          usedPercent: reading(89.57),
          readOnly: reading(false),
        },
        data: {
          usedPercent: reading(6.62),
          readOnly: reading(false),
        },
        ext4Filesystems: [],
      },
      vitalRecorder: { activeState: reading("active") },
      services: {
        systemRunning: reading("degraded"),
        failedUnits: reading("rpi-eeprom-update.service"),
      },
    },
  }, "current");

  assert.strictEqual(health.state, "warning");
  assert.deepStrictEqual(
    health.issues.map((issue) => issue.code),
    ["systemd-system-degraded", "time-not-synchronized"],
  );
  assert.match(health.issues[0].detail, /rpi-eeprom-update\.service/);
});

test("stale report retains evidence without claiming current health", () => {
  const health = assessRecorderOperationalHealth({
    deviceObservedAt: "2026-07-24T05:02:29Z",
    ntpState: "unsynchronized",
    payload: {},
  }, "stale");

  assert.strictEqual(health.state, "unknown");
  assert.strictEqual(health.issueCount, 1);
  assert.strictEqual(health.issues[0].code, "time-not-synchronized");
});
