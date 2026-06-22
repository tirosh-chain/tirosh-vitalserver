"use strict";

const { recordRecorderIpSync } = require("../../observability/metrics");

function createVrIdentityStore(redis, metrics) {
  return {
    setRecorderIp(vrcode, selectedIp, policy) {
      if (!vrcode || !selectedIp) return;
      const rewritePolicy = policy || { enabled: true, verifyDelaysMs: [] };
      const redisKey = `ip_${vrcode}`;

      if (rewritePolicy.enabled === false) {
        recordRecorderIpSync(metrics, vrcode, {
          status: "disabled",
          redisKey,
          selectedIp,
          lastFailure: null,
        });
        return;
      }

      recordRecorderIpSync(metrics, vrcode, {
        status: "pending",
        redisKey,
        selectedIp,
        lastFailure: null,
      });
      writeRecorderIp(redis, metrics, vrcode, redisKey, selectedIp, "written", (writeError) => {
        if (writeError) return;
        const verifyDelaysMs = Array.isArray(rewritePolicy.verifyDelaysMs)
          ? rewritePolicy.verifyDelaysMs
          : [];
        verifyDelaysMs.forEach((delayMs, index) => {
          setTimeout(() => {
            verifyRecorderIp(redis, metrics, vrcode, redisKey, selectedIp, index === verifyDelaysMs.length - 1);
          }, Math.max(0, delayMs));
        });
      });
    },
  };
}

function writeRecorderIp(redis, metrics, vrcode, redisKey, selectedIp, successStatus, callback, successFields = {}) {
  redis.command(["SET", redisKey, selectedIp], (error) => {
    if (error) {
      metrics.redisIpWriteFailures += 1;
      recordRecorderIpSync(metrics, vrcode, {
        status: "write_failed",
        redisKey,
        selectedIp,
        lastWriteAt: new Date().toISOString(),
        lastFailure: error.message,
      });
      console.error("[recorder-ingress] ip write failed:", error.message);
      if (callback) callback(error);
      return;
    }

    recordRecorderIpSync(metrics, vrcode, {
      status: successStatus,
      redisKey,
      selectedIp,
      redisValue: selectedIp,
      lastWriteAt: new Date().toISOString(),
      lastFailure: null,
      ...successFields,
    });
    if (callback) callback(null);
  });
}

function verifyRecorderIp(redis, metrics, vrcode, redisKey, selectedIp, finalVerify) {
  redis.command(["GET", redisKey], (error, value) => {
    const verifiedAt = new Date().toISOString();
    if (error) {
      metrics.redisIpVerifyFailures += 1;
      recordRecorderIpSync(metrics, vrcode, {
        status: "verify_failed",
        redisKey,
        selectedIp,
        lastVerifiedAt: verifiedAt,
        lastFailure: error.message,
      });
      console.error("[recorder-ingress] ip verify failed:", error.message);
      return;
    }

    if (value === selectedIp) {
      recordRecorderIpSync(metrics, vrcode, {
        status: "verified",
        redisKey,
        selectedIp,
        redisValue: value,
        lastVerifiedAt: verifiedAt,
        lastFailure: null,
      });
      return;
    }

    metrics.redisIpVerifyMismatches += 1;
    recordRecorderIpSync(metrics, vrcode, {
      status: finalVerify ? "mismatch" : "correcting",
      redisKey,
      selectedIp,
      redisValue: value,
      lastVerifiedAt: verifiedAt,
      lastFailure: `redis value ${reportedRedisValue(value)} did not match selected IP ${selectedIp}`,
    });

    writeRecorderIp(
      redis,
      metrics,
      vrcode,
      redisKey,
      selectedIp,
      finalVerify ? "mismatch" : "corrected",
      null,
      finalVerify
        ? {
            redisValue: value,
            lastVerifiedAt: verifiedAt,
            lastFailure: `redis value ${reportedRedisValue(value)} did not match selected IP ${selectedIp}`,
          }
        : {}
    );
  });
}

function reportedRedisValue(value) {
  return value === null ? "<missing>" : JSON.stringify(value);
}

module.exports = { createVrIdentityStore };
